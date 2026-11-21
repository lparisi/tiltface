"""Record the two faces in the watchOS Simulator (run on a Mac with Xcode; CI: .github/workflows/demo-videos.yml).

Builds the watch app for the simulator, boots the largest available Apple Watch, and records each face while the app
runs its scripted demo motion (`-demoFace physics|world`). Outputs go to build/demo/:
  physics.mp4, world.mp4   screen recordings (or physics-frames/, world-frames/ PNG sequences if recording fails)
  *-still.png              one screenshot per face, mid-recording
  record-log.txt

Usage: python3 tools/record_demo.py [--physics-seconds 24] [--world-seconds 18]
"""
import argparse
import json
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build  # noqa: E402  (pinned XcodeGen download)

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build' / 'demo'
BUNDLE = 'digital.svrn.tiltface.watchkitapp'
LOG = OUT / 'record-log.txt'


def log(*parts):
    line = ' '.join(str(p) for p in parts)
    print(line, flush=True)
    with LOG.open('a') as f:
        f.write(line + '\n')


def run(args, **kw):
    log('$', ' '.join(str(a) for a in args))
    return subprocess.run([str(a) for a in args], check=True, text=True, capture_output=True, **kw).stdout


def pick_device():
    runtimes = json.loads(run(['xcrun', 'simctl', 'list', '-j', 'runtimes']))['runtimes']
    watch = [r for r in runtimes if r.get('platform') == 'watchOS' and r.get('isAvailable')]
    if not watch:
        raise RuntimeError('No watchOS simulator runtime installed.')
    rt = max(watch, key=lambda r: [int(x) for x in r['version'].split('.')])
    types = rt.get('supportedDeviceTypes') or json.loads(run(['xcrun', 'simctl', 'list', '-j', 'devicetypes']))['devicetypes']

    def score(t):
        name = t['name']
        m = re.search(r'(\d+)mm', name)
        mm = int(m.group(1)) if m else 0
        series = re.search(r'Series (\d+)', name)
        ultra = 'Ultra' in name
        return (0 if ultra else 1, int(series.group(1)) if series else 0, mm)

    candidates = [t for t in types if 'Apple Watch' in t['name']]
    dt = max(candidates, key=score)
    log('runtime', rt['identifier'], rt['version'], '| device type', dt['name'])
    return rt['identifier'], dt['identifier']


def build_app(work):
    xcodegen = build.generator(work)
    run([xcodegen, 'generate', '--spec', ROOT / 'project.yml', '--project', ROOT])
    sym = work / 'sym'
    proc = subprocess.run(['xcodebuild', '-project', str(ROOT / 'TiltFace.xcodeproj'), '-target', 'TiltFaceWatch',
                           '-sdk', 'watchsimulator', '-configuration', 'Release', f'SYMROOT={sym}',
                           'CODE_SIGNING_ALLOWED=NO', 'build'], text=True, capture_output=True)
    (OUT / 'xcodebuild.log').write_text(proc.stdout + proc.stderr)
    if proc.returncode != 0:
        errors = [l for l in (proc.stdout + proc.stderr).splitlines() if ' error: ' in l or l.startswith('error:')]
        print('\n'.join(errors[-40:]), file=sys.stderr)
        raise RuntimeError('Simulator build failed.')
    app = sym / 'Release-watchsimulator' / 'TiltFaceWatch.app'
    if not app.is_dir():
        raise RuntimeError(f'App not found at {app}')
    return app


def record(udid, face, seconds):
    video = OUT / f'{face}.mp4'
    applog = open(OUT / f'{face}-app-log.txt', 'w')
    logger = subprocess.Popen(['xcrun', 'simctl', 'spawn', udid, 'log', 'stream', '--level', 'debug', '--style', 'compact',
                               '--predicate', 'process == "TiltFaceWatch"'], stdout=applog, stderr=subprocess.STDOUT)
    rec = subprocess.Popen(['xcrun', 'simctl', 'io', udid, 'recordVideo', '--codec=h264', '--force', str(video)],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    time.sleep(2.0)
    run(['xcrun', 'simctl', 'launch', '--terminate-running-process', udid, BUNDLE, '-demoFace', face])
    t0 = time.time()
    still_taken = False
    while time.time() - t0 < seconds:
        if not still_taken and time.time() - t0 > seconds * 0.55:
            run(['xcrun', 'simctl', 'io', udid, 'screenshot', str(OUT / f'{face}-still.png')])
            still_taken = True
        time.sleep(0.2)
    rec.send_signal(signal.SIGINT)
    try:
        out, _ = rec.communicate(timeout=30)
        log(f'recordVideo ({face}):', (out or '').strip()[-400:])
    except subprocess.TimeoutExpired:
        rec.kill()
    ok = video.exists() and video.stat().st_size > 50_000
    if not ok:
        log(f'recordVideo produced nothing usable for {face}; capturing a PNG sequence instead.')
        frames = OUT / f'{face}-frames'
        frames.mkdir(exist_ok=True)
        run(['xcrun', 'simctl', 'launch', '--terminate-running-process', udid, BUNDLE, '-demoFace', face])
        t0 = time.time()
        i = 0
        while time.time() - t0 < seconds:
            subprocess.run(['xcrun', 'simctl', 'io', udid, 'screenshot', str(frames / f'{i:05d}.png')],
                           capture_output=True)
            i += 1
        (frames / 'duration.txt').write_text(f'{time.time() - t0:.3f}\n')
        log(f'{face}: {i} frames in {seconds}s')
    subprocess.run(['xcrun', 'simctl', 'terminate', udid, BUNDLE], capture_output=True)
    time.sleep(1.0)
    logger.terminate()
    applog.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--physics-seconds', type=float, default=24)
    ap.add_argument('--world-seconds', type=float, default=18)
    a = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    work = ROOT / 'build' / 'demo-work'
    work.mkdir(parents=True, exist_ok=True)
    log(run(['xcodebuild', '-version']).strip())

    app = build_app(work)
    runtime, devtype = pick_device()
    udid = run(['xcrun', 'simctl', 'create', 'TiltFace Demo', devtype, runtime]).strip()
    run(['xcrun', 'simctl', 'boot', udid])
    run(['xcrun', 'simctl', 'bootstatus', udid, '-b'])
    time.sleep(8)   # let the watch settle after first boot
    run(['xcrun', 'simctl', 'install', udid, app])
    try:
        record(udid, 'physics', a.physics_seconds)
        record(udid, 'world', a.world_seconds)
    finally:
        subprocess.run(['xcrun', 'simctl', 'shutdown', udid], capture_output=True)
    log('done:', sorted(p.name for p in OUT.iterdir()))


if __name__ == '__main__':
    main()
