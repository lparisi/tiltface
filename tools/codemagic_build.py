"""Start the Codemagic workflow of codemagic.yaml for a branch, follow it to the end, download its artifacts and publish the
IPA as a GitHub release of that exact commit, the one place to take a build from.

Release names (release_names below): the tag is SemVer, v<app version>-build.<n>, where the app version is MARKETING_VERSION in
project.yml and <n> is the CI run number; the IPA is TiltFace-<version>-build.<n>-<commit>-unsigned.ipa. A build of main is
a full release marked latest, so /releases/latest always opens the newest main build; any other branch is a pre-release.

Usage: python3 tools/codemagic_build.py [--branch main] [--workflow watch-unsigned] [--out build/codemagic] [--no-release]
Token: the Codemagic API token (Teams > Personal account > Integrations > Codemagic API), as CODEMAGIC_TOKEN (in CI: the repository
secret) or in ~/.config/codemagic/token. It is read, sent only to api.codemagic.io, and never printed.
Exit code 0 only when the build finished; a failed step prints its name and the tail of its log.
"""
import argparse, json, os, re, shutil, subprocess, sys, time, urllib.request
from pathlib import Path

API = 'https://api.codemagic.io'


def token():
    # CI: the repository secret CODEMAGIC_TOKEN. Locally: the variable or the file.
    t = os.environ.get('CODEMAGIC_TOKEN', '').strip()
    f = Path.home() / '.config/codemagic/token'
    if not t and f.exists(): t = f.read_text().strip()
    if not t: sys.exit('Sem token do Codemagic: defina CODEMAGIC_TOKEN (no CI, o secret do repositório) ou crie ~/.config/codemagic/token.')
    return t


def call(method, path, body=None, raw=False):
    req = urllib.request.Request(path if path.startswith('http') else API + path, method=method,
                                 data=None if body is None else json.dumps(body).encode(),
                                 headers={'x-auth-token': TOKEN, 'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=60) as r:
        data = r.read()
    return data if raw else json.loads(data or b'{}')


def app_id(repo):
    # Two Codemagic apps can point at the same repository; the one added through the GitHub integration (provider github) can
    # read it, a "generic" SSH one without a deploy key cannot (seen: "Repository not found").
    apps = [a for a in call('GET', '/apps').get('applications', []) if repo in (a.get('repository') or {}).get('htmlUrl', '') or a.get('appName') == repo]
    apps.sort(key=lambda a: (a.get('repository') or {}).get('provider') != 'github')
    if not apps: sys.exit(f'Nenhum app do Codemagic aponta para {repo}.')
    return apps[0]['_id']


def app_version(text):
    m = re.search(r"^\s*MARKETING_VERSION:\s*['\"]?(\d+\.\d+\.\d+)['\"]?\s*$", text, re.M)
    if not m: sys.exit('project.yml sem MARKETING_VERSION no formato X.Y.Z.')
    return m.group(1)


def release_names(version, sha, branch, number=None):
    """Tag, title and asset stem of a build. SemVer: a pre-release identifier after the app version, so builds of one version
    sort by run number and all come before the plain vX.Y.Z. Without a run number (a local run) the commit identifies the build."""
    short = sha[:7]
    build = f'build.{int(number)}' if number else f'dev.{short}'
    main = branch == 'main'
    return {'tag': f'v{version}-{build}',
            'title': f'TiltFace {version} ({build.replace(".", " ")}, {short})' + ('' if main else f' [{branch}]'),
            'stem': f'TiltFace-{version}-{build}-{short}',
            'prerelease': not main}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--branch', default='main')
    ap.add_argument('--workflow', default='watch-unsigned')
    ap.add_argument('--repo', default='tiltface')
    ap.add_argument('--out', default='build/codemagic')
    ap.add_argument('--no-release', action='store_true')
    ap.add_argument('--build-number', default=os.environ.get('GITHUB_RUN_NUMBER'), help='CI run number; default GITHUB_RUN_NUMBER')
    a = ap.parse_args()
    # The commit Codemagic will check out: the branch head on GitHub right now (the release is tied to it, never to a moving branch).
    sha = subprocess.check_output(['git', 'ls-remote', 'origin', f'refs/heads/{a.branch}'], text=True).split()[0]
    build = call('POST', '/builds', {'appId': app_id(a.repo), 'workflowId': a.workflow, 'branch': a.branch})['buildId']
    print(f'build {build} iniciado ({a.workflow} @ {a.branch} {sha[:7]})', flush=True)
    seen, b = set(), {}
    while True:
        b = call('GET', f'/builds/{build}')['build']
        for s in b.get('buildActions', []):
            key = (s.get('name'), s.get('status'))
            if s.get('status') in ('success', 'failed', 'skipped') and key not in seen:
                seen.add(key); print(f"  {s['status']:8} {s['name']}", flush=True)
        if b.get('status') in ('finished', 'failed', 'canceled', 'timeout', 'skipped'): break
        time.sleep(20)
    print('resultado:', b.get('status'), b.get('message') or '')
    for s in b.get('buildActions', []):
        if s.get('status') == 'failed' and s.get('logUrl'):
            log = call('GET', s['logUrl'], raw=True).decode(errors='replace')
            print(f"--- {s['name']} (fim do log) ---\n" + '\n'.join(log.splitlines()[-60:]))
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True); files = []
    for art in b.get('artefacts', []):
        path = out / art['name']; path.write_bytes(call('GET', art['url'], raw=True)); files.append(path)
        print(f'artefato {path} ({path.stat().st_size} bytes)')
    ok = b.get('status') == 'finished'
    ipa = [f for f in files if f.suffix == '.ipa']
    if ok and ipa and not a.no_release:
        # The version of the commit that was built, not of the working copy.
        project = subprocess.check_output(['git', 'show', f'{sha}:project.yml'], text=True)
        n = release_names(app_version(project), sha, a.branch, a.build_number)
        tag = n['tag']
        named = out / f"{n['stem']}-unsigned.ipa"; shutil.copyfile(ipa[0], named)
        assets = [str(named)]
        for f in files:
            if f.name == 'build-report.json':
                report = out / f"{n['stem']}-build-report.json"; shutil.copyfile(f, report); assets.append(str(report))
        repo = os.environ.get('GITHUB_REPOSITORY', f'lparisi/{a.repo}')
        notes = (f'**iPhone app with the watch app inside (unsigned IPA):** [{named.name}](https://github.com/{repo}/releases/download/{tag}/{named.name})\n\n'
                 f'- Version {n["tag"][1:]}, commit {sha} ({a.branch})\n'
                                  f'- Codemagic build {build}, workflow {a.workflow}\n\n'
                 'Unsigned: sign and install with Sideloadly on the iPhone paired with the watch.')
        if subprocess.run(['gh', 'release', 'view', tag], capture_output=True).returncode == 0:  # the same run built again
            subprocess.run(['gh', 'release', 'upload', tag, *assets, '--clobber'], check=True)
        else:
            kind = ['--prerelease'] if n['prerelease'] else ['--latest']
            subprocess.run(['gh', 'release', 'create', tag, *assets, '--target', sha, *kind, '--title', n['title'], '--notes', notes], check=True)
        print(f'publicado: release {tag}')
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    TOKEN = token()
    main()
