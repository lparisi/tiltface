"""Build TiltFace on a Mac (Codemagic M2 or any Mac with Xcode) without Apple credentials and package an unsigned IPA.

The IPA is the iPhone host app with the watch app embedded at TiltFace.app/Watch/TiltFaceWatch.app.
It is NOT installable as-is: sign and install it with Sideloadly onto the iPhone paired with the watch.

Usage: python3 tools/build.py [--check]
Same approach as partikel-capture/tools/build_ios.py: pinned XcodeGen, isolated attempt folder, build-report.json.
"""
import argparse
import hashlib
import json
import platform
import plistlib
import shutil
import stat
import subprocess
import sys
import urllib.request
import uuid
import zipfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GENERATOR_URL = 'https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip'
GENERATOR_SHA256 = '4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806'
HOST = 'TiltFace'
WATCH = 'TiltFaceWatch'


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def plist(app):
    return plistlib.loads((app / 'Info.plist').read_bytes())


def check_bundle(app, platform_name):
    """The bundle exists, was built for the right device platform and has its executable."""
    if not app.is_dir():
        raise ValueError(f'Bundle missing: {app}')
    info = plist(app)
    if info.get('CFBundleSupportedPlatforms') != [platform_name]:
        raise ValueError(f'{app.name} built for {info.get("CFBundleSupportedPlatforms")}, expected {platform_name}.')
    executable = info.get('CFBundleExecutable', '')
    if not executable or not (app / executable).is_file():
        raise ValueError(f'{app.name}: executable missing.')
    if (app / 'embedded.mobileprovision').exists():
        raise ValueError(f'{app.name}: unexpected provisioning profile in an unsigned build.')
    archs = subprocess.run(['lipo', '-archs', str(app / executable)], capture_output=True, text=True).stdout.split()
    return info, archs


def package(app, target):
    host, host_archs = check_bundle(app, 'iPhoneOS')
    watch_app = app / 'Watch' / f'{WATCH}.app'
    watch, watch_archs = check_bundle(watch_app, 'WatchOS')
    if not watch.get('WKApplication'):
        raise ValueError('Watch app Info.plist lacks WKApplication.')
    if watch.get('WKCompanionAppBundleIdentifier') != host['CFBundleIdentifier']:
        raise ValueError('WKCompanionAppBundleIdentifier does not match the iPhone app.')
    if not watch['CFBundleIdentifier'].startswith(host['CFBundleIdentifier'] + '.'):
        raise ValueError('Watch bundle ID must be prefixed by the iPhone bundle ID.')
    files = []
    with zipfile.ZipFile(target, 'x', compression=zipfile.ZIP_DEFLATED) as archive:
        for item in sorted(app.rglob('*')):
            if item.is_symlink():
                raise ValueError('Unexpected symlink in the bundle.')
            if item.is_file():
                relative = item.relative_to(app).as_posix()
                archive.write(item, 'Payload/' + app.name + '/' + relative)
                files.append({'path': relative, 'bytes': item.stat().st_size})
    with zipfile.ZipFile(target) as archive:
        if archive.testzip() is not None:
            raise ValueError('IPA integrity check failed.')
    return {'host': {'bundleId': host['CFBundleIdentifier'], 'version': host['CFBundleShortVersionString'],
                     'build': host['CFBundleVersion'], 'minimumOS': host.get('MinimumOSVersion'), 'archs': host_archs},
            'watch': {'bundleId': watch['CFBundleIdentifier'], 'minimumOS': watch.get('MinimumOSVersion'),
                      'archs': watch_archs, 'runsIndependently': watch.get('WKRunsIndependentlyOfCompanionApp')},
            'files': len(files), 'ipaSha256': sha256(target), 'ipaBytes': target.stat().st_size,
            'signing': 'requires_local_signing', 'installableAsIs': False}


def generator(attempt):
    archive = attempt / 'xcodegen-2.46.0.zip'
    urllib.request.urlretrieve(GENERATOR_URL, archive)
    if sha256(archive) != GENERATOR_SHA256:
        raise ValueError('XcodeGen SHA-256 differs from the pinned release.')
    destination = attempt / 'generator'
    with zipfile.ZipFile(archive) as source:
        for member in source.infolist():
            path = Path(member.filename)
            if path.is_absolute() or '..' in path.parts or stat.S_ISLNK(member.external_attr >> 16):
                raise ValueError('Invalid path in the XcodeGen archive.')
        source.extractall(destination)
    binary = destination / 'xcodegen/bin/xcodegen'
    binary.chmod(0o755)
    return binary


def command(args, log):
    with log.open('ab') as output:
        output.write(('\n' + json.dumps([str(a) for a in args]) + '\n').encode())
        output.flush()
        result = subprocess.run([str(a) for a in args], cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
    if result.returncode != 0:
        # Surface the compiler errors in the CI log, not only in build.log.
        lines = log.read_text(errors='replace').splitlines()
        errors = [l for l in lines if ' error: ' in l or l.startswith('error:')]
        print('\n'.join((errors or lines)[-40:]), file=sys.stderr)
        raise subprocess.CalledProcessError(result.returncode, args[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Check the Mac/Xcode without building.')
    args = parser.parse_args()
    if platform.system() != 'Darwin':
        print('Run this on a Mac with Xcode (Codemagic does it in CI).', file=sys.stderr)
        return 2
    xcode = subprocess.check_output(['xcodebuild', '-version'], text=True).strip()
    ios_sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-version'], text=True).strip()
    watch_sdk = subprocess.check_output(['xcrun', '--sdk', 'watchos', '--show-sdk-version'], text=True).strip()
    print(f'{xcode}\niPhoneOS SDK {ios_sdk}\nwatchOS SDK {watch_sdk}', flush=True)
    if int(watch_sdk.split('.')[0]) < 10:
        raise RuntimeError('watchOS SDK older than the 10.0 deployment target.')
    if args.check:
        return 0

    attempt = ROOT / 'build' / (datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8])
    attempt.mkdir(parents=True)
    log = attempt / 'build.log'
    git = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True, capture_output=True)
    report = {'schema': 'tiltface.build.v1', 'state': 'started', 'xcode': xcode, 'iosSDK': ios_sdk,
              'watchSDK': watch_sdk, 'macOS': platform.mac_ver()[0], 'appleAccountUsed': False,
              'sourceRevision': git.stdout.strip() if git.returncode == 0 else None}
    try:
        xcodegen = generator(attempt)
        command([xcodegen, 'generate', '--spec', ROOT / 'project.yml', '--project', attempt], log)
        # No -sdk and no ARCHS override: the iOS host builds for iPhoneOS and Xcode builds the embedded
        # watch app for watchOS with its own architectures (arm64_32 + arm64).
        command(['xcodebuild', '-project', attempt / f'{HOST}.xcodeproj', '-scheme', HOST,
                 '-destination', 'generic/platform=iOS', '-configuration', 'Release',
                 '-derivedDataPath', attempt / 'DerivedData', '-resultBundlePath', attempt / 'build.xcresult',
                 'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'build'], log)
        app = attempt / f'DerivedData/Build/Products/Release-iphoneos/{HOST}.app'
        ipa = attempt / f'{HOST}-unsigned.ipa'
        report['artifact'] = package(app, ipa)
        report['state'] = 'compiled_requires_local_signing'
        print(f'{ipa}\nCompiled. Sign and install with Sideloadly on the iPhone paired with the watch.', flush=True)
    except Exception as error:
        report['state'] = 'failed'
        report['error'] = str(error)
        print(f'Build failed: {error}\nLog: {log}', file=sys.stderr)
        raise
    finally:
        (attempt / 'build-report.json').write_text(json.dumps(report, indent=2) + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
