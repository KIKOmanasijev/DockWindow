#!/usr/bin/env python3
"""Fail-closed DogBar distribution. Python stdlib and Apple tools only."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
EMPTY = dict(available=False, version=None, url=None, sha256=None,
             architecture='arm64', minimumMacOS='14.0', notarized=False)
ENTITLEMENTS = {'com.apple.security.automation.apple-events': True}
TOOLS = ('security', 'codesign', 'spctl', 'hdiutil', 'ditto', 'xcrun', 'swift')

class ReleaseError(Exception):
    pass

def require(ok, message):
    if not ok:
        raise ReleaseError(message)

def version(value):
    require(isinstance(value, str) and re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', value),
            'Version must be three numeric components, for example 1.2.3')
    return value

def build_number(value):
    require(isinstance(value, str) and re.fullmatch(r'[1-9][0-9]{0,8}', value), 'Build must be a positive integer (up to 9 digits)')
    return value

def team_id(value):
    require(isinstance(value, str) and re.fullmatch(r'[A-Z0-9]{10}', value), 'Team ID must be 10 uppercase alphanumeric characters')
    return value

def filename(v):
    return f'DogBar-{version(v)}-arm64.dmg'

def digest(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def run(*args):
    # No shell interpolation and no credentials in arguments. Apple tools resolve
    # through a restricted PATH; xcrun selects the active Xcode toolchain.
    env = dict(os.environ, PATH='/usr/bin:/bin:/usr/sbin:/sbin', LC_ALL='C')
    p = subprocess.run([str(a) for a in args], cwd=ROOT, env=env, capture_output=True, text=True)
    require(p.returncode == 0, f'{args[0]} {args[1] if len(args)>1 else ""} failed:\n{p.stdout}\n{p.stderr}')
    return p.stdout if p.stdout.strip() else p.stderr

def prerequisites():
    require(platform.system() == 'Darwin', 'Release tools require macOS')
    for tool in TOOLS:
        require(shutil.which(tool, path='/usr/bin:/bin:/usr/sbin:/sbin'), f'Missing Apple tool: {tool}')
    for tool in ('notarytool', 'stapler', 'lipo'):
        run('xcrun', '--find', tool)
    run('swift', '--version')

def select_identity(output, team, requested=None):
    team_id(team)
    candidates = []
    for sha, name in re.findall(r'\b([A-Fa-f0-9]{40})\s+"([^"\n]+)"', output):
        if name.startswith('Developer ID Application: ') and name.endswith(f'({team})'):
            candidates.append(sha.upper())
    if requested:
        require(re.fullmatch(r'[A-Fa-f0-9]{40}', requested), 'Identity must be its 40-character SHA-1 fingerprint')
        candidates = [x for x in candidates if x == requested.upper()]
    require(len(candidates) == 1, 'Need exactly one valid Apple Developer ID Application identity for this Team ID; use --identity SHA1 to disambiguate. Local/self-signed development certificates cannot release.')
    return candidates[0]

def preflight(team, profile=None, identity=None):
    team_id(team)
    prerequisites()
    selected = select_identity(run('security', 'find-identity', '-v', '-p', 'codesigning'), team, identity)
    if profile is not None:
        require(isinstance(profile, str) and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,79}', profile), 'Use a simple nonempty Keychain profile name')
        run('xcrun', 'notarytool', 'history', '--keychain-profile', profile, '--output-format', 'json')
    return selected

def ready_manifest(v, sha):
    require(isinstance(sha, str) and re.fullmatch(r'[a-f0-9]{64}', sha), 'Invalid SHA-256')
    return dict(EMPTY, available=True, version=version(v), url='/downloads/' + filename(v), sha256=sha, notarized=True)

def validate_manifest(m):
    require(isinstance(m, dict) and set(m) == set(EMPTY), 'Unexpected manifest fields')
    if m.get('available') is False and m.get('notarized') is False and m == EMPTY:
        return m
    require(m.get('available') is True and m.get('notarized') is True, 'Manifest is not approved')
    require(m == ready_manifest(m.get('version'), m.get('sha256')), 'Unsafe or inconsistent release manifest')
    return m

def atomic_json(path, data):
    fd, name = tempfile.mkstemp(prefix='.release-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(data, f, indent=2)
            f.write('\n')
            f.flush()
            os.fsync(f.fileno())
        os.chmod(name, 0o644)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)

def accepted_submission(data):
    require(isinstance(data, dict) and data.get('status') == 'Accepted', 'Notarization status must be exactly Accepted')
    try:
        return str(uuid.UUID(data['id']))
    except (KeyError, ValueError, TypeError, AttributeError):
        raise ReleaseError('Notarization response missing valid submission UUID')

def notarize(path, profile, logs, label):
    raw = run('xcrun', 'notarytool', 'submit', path, '--keychain-profile', profile, '--wait', '--output-format', 'json')
    # Persist response even when Apple reports Invalid with exit status zero.
    (logs / f'{label}-submission.json').write_text(raw)
    data = json.loads(raw)
    try:
        submission = str(uuid.UUID(data['id']))
    except (KeyError, ValueError, TypeError, AttributeError):
        raise ReleaseError('Notarization response missing valid submission UUID')
    run('xcrun', 'notarytool', 'log', submission, '--keychain-profile', profile, logs / f'{label}-notary-log.json')
    accepted_submission(data)
    return data

def requirement(team, app=False):
    # Apple-issued Developer ID Application leaf OID; a name alone is not proof.
    r = f'anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "{team_id(team)}"'
    if app:
        r += ' and identifier "com.dockwindow.app"'
    return r

def verify_signature(path, team, app=False):
    run('codesign', '--verify', '--deep', '--strict', '--verbose=2', '-R', requirement(team, app), path)
    detail = run('codesign', '--display', '--verbose=4', path)
    require(f'TeamIdentifier={team}\n' in detail, 'Unexpected code signing TeamIdentifier')
    require('Authority=Developer ID Application: ' in detail and 'Timestamp=' in detail,
            'Missing Developer ID authority or secure timestamp')
    if app:
        require(re.search(r'flags=0x[0-9a-f]+\([^\n]*runtime', detail), 'Missing hardened runtime')
        ent = run('codesign', '--display', '--entitlements', '-', '--xml', path)
        start = ent.find('<?xml')
        end = ent.find('</plist>')
        require(start >= 0 and end >= start, 'Cannot inspect app entitlements')
        require(plistlib.loads(ent[start:end + len('</plist>')].encode()) == ENTITLEMENTS, 'Unexpected or unsafe app entitlements')

def ticket_and_gatekeeper(path, app=False):
    run('xcrun', 'stapler', 'validate', path)
    args = ['spctl', '--assess', '--ignore-cache', '--no-cache', '--type', 'execute' if app else 'open', '--verbose=2']
    if not app:
        args += ['--context', 'context:primary-signature']
    result = run(*args, path)
    require(re.search(r'^source=Notarized Developer ID\s*$', result, re.M), 'Gatekeeper must report Notarized Developer ID')

def verify_app(app, team, v, build):
    require(not app.is_symlink() and app.is_dir(), 'Missing real DogBar.app bundle')
    p = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    expected = dict(CFBundleIdentifier='com.dockwindow.app', CFBundleExecutable='DockWindow',
                    CFBundleName='DogBar', CFBundleShortVersionString=v, CFBundleVersion=build,
                    LSMinimumSystemVersion='14.0')
    require(all(p.get(k) == val for k, val in expected.items()), 'App metadata does not match requested release')
    binary = app / 'Contents/MacOS/DockWindow'
    require(run('xcrun', 'lipo', '-archs', binary).strip() == 'arm64', 'Release must be arm64 only')
    verify_signature(app, team, app=True)
    ticket_and_gatekeeper(app, app=True)

def verify_dmg(dmg, team, v, build, sha=None):
    version(v)
    build_number(build)
    team_id(team)
    require(dmg.name == filename(v) and not dmg.is_symlink() and dmg.is_file(), 'Unexpected DMG filename or path')
    if sha is not None:
        require(re.fullmatch(r'[a-f0-9]{64}', sha or ''), 'Invalid expected hash')
        require(digest(dmg) == sha, 'DMG SHA-256 mismatch')
    verify_signature(dmg, team)
    ticket_and_gatekeeper(dmg)
    run('hdiutil', 'verify', dmg)
    require(run('hdiutil', 'imageinfo', '-format', dmg).strip().splitlines()[-1] == 'UDZO', 'DMG must be compressed read-only UDZO')
    with tempfile.TemporaryDirectory(prefix='dogbar-verify-') as temp:
        mount = Path(temp) / 'volume'
        mount.mkdir()
        attached = False
        try:
            run('hdiutil', 'attach', dmg, '-readonly', '-noautoopen', '-mountpoint', mount)
            attached = True
            require(set(x.name for x in mount.iterdir()) <= {'DogBar.app', 'Applications', '.DS_Store', '.fseventsd', '.Trashes', '.HFS+ Private Directory Data\r', '.Spotlight-V100'}, 'Unexpected DMG contents')
            link = mount / 'Applications'
            require(link.is_symlink() and os.readlink(link) == '/Applications', 'Missing Applications shortcut')
            verify_app(mount / 'DogBar.app', team, v, build)
        finally:
            if attached:
                run('hdiutil', 'detach', mount)
    final_hash = digest(dmg)
    if sha is not None:
        require(final_hash == sha, 'DMG changed during verification')
    return final_hash

def build_release(args):
    v, b = version(args.version), build_number(args.build)
    selected = preflight(args.team_id, args.keychain_profile, args.identity)
    out = ROOT / 'dist' / f'DogBar-{v}-arm64'
    require(not out.exists() and not out.is_symlink(), 'Release version output already exists; never overwrite it')
    out.parent.mkdir(exist_ok=True)
    require(not out.parent.is_symlink(), 'dist must not be a symlink')
    out.mkdir()
    logs = out / 'logs'
    logs.mkdir()
    entitlements = ROOT / 'Resources/DockWindow.entitlements'
    require(plistlib.loads(entitlements.read_bytes()) == ENTITLEMENTS, 'Review changed entitlements before releasing')
    scratch = out / 'build'
    swift = ['swift', 'build', '--scratch-path', scratch, '-c', 'release', '--triple', 'arm64-apple-macosx14.0', '--product', 'DockWindow']
    run(*swift)
    bin_dir = Path(run(*swift, '--show-bin-path').strip())
    require(bin_dir.resolve().is_relative_to(scratch.resolve()), 'Swift binary must be inside isolated scratch directory')
    stage = out / 'image'
    app = stage / 'DogBar.app'
    (app / 'Contents/MacOS').mkdir(parents=True)
    (app / 'Contents/Resources').mkdir()
    shutil.copy2(bin_dir / 'DockWindow', app / 'Contents/MacOS/DockWindow')
    shutil.copy2(ROOT / 'Resources/AppIcon.icns', app / 'Contents/Resources/AppIcon.icns')
    info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    info.update(CFBundleIdentifier='com.dockwindow.app', CFBundleExecutable='DockWindow', CFBundleName='DogBar', CFBundleDisplayName='DogBar', CFBundleShortVersionString=v, CFBundleVersion=b, LSMinimumSystemVersion='14.0')
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    # Never sign --deep. The current product has one executable, no nested code.
    run('codesign', '--force', '--sign', selected, '--options', 'runtime', '--timestamp', '--entitlements', entitlements, app)
    verify_signature(app, args.team_id, app=True)
    archive = out / 'DogBar-notary.zip'
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, archive)
    app_submission = notarize(archive, args.keychain_profile, logs, 'app')
    run('xcrun', 'stapler', 'staple', app)
    verify_app(app, args.team_id, v, b)
    (stage / 'Applications').symlink_to('/Applications')
    dmg = out / filename(v)
    run('hdiutil', 'create', '-volname', 'DogBar', '-srcfolder', stage, '-format', 'UDZO', '-fs', 'HFS+', dmg)
    run('codesign', '--sign', selected, '--timestamp', dmg)
    verify_signature(dmg, args.team_id)
    dmg_submission = notarize(dmg, args.keychain_profile, logs, 'dmg')
    run('xcrun', 'stapler', 'staple', dmg)
    sha = verify_dmg(dmg, args.team_id, v, b)
    # This is the only success marker. Failed builds retain diagnostics but no manifest.
    atomic_json(out / 'provenance.json', dict(teamID=args.team_id, build=b, version=v, sha256=sha,
                appSubmission=app_submission, dmgSubmission=dmg_submission))
    atomic_json(out / 'release.json', ready_manifest(v, sha))
    print(f'Verified release: {dmg}\nSHA-256: {sha}')

def load_release(directory, team, v, build):
    manifest = validate_manifest(json.loads((directory / 'release.json').read_text()))
    require(manifest['available'] is True and manifest['version'] == v, 'Release manifest version mismatch')
    p = json.loads((directory / 'provenance.json').read_text())
    require(p.get('teamID') == team and p.get('version') == v and p.get('build') == build and p.get('sha256') == manifest['sha256'], 'Release provenance mismatch')
    accepted_submission(p.get('appSubmission'))
    accepted_submission(p.get('dmgSubmission'))
    return manifest

def verify_or_stage(args, stage=False):
    prerequisites()
    team_id(args.team_id)
    v, b = version(args.version), build_number(args.build)
    directory = args.release_dir.resolve(strict=True)
    m = load_release(directory, args.team_id, v, b)
    source = directory / filename(v)
    if not stage:
        verify_dmg(source, args.team_id, v, b, m['sha256'])
        print('Release independently verified')
        return
    landing = ROOT / 'landing'
    downloads = landing / 'downloads'
    require(not landing.is_symlink() and not downloads.is_symlink(), 'Website paths must not be symlinks')
    downloads.mkdir(exist_ok=True)
    manifest_path = landing / 'release.json'
    require(not manifest_path.is_symlink(), 'Website manifest must not be a symlink')
    old = validate_manifest(json.loads(manifest_path.read_text()))
    if old['available']:
        require(tuple(map(int, v.split('.'))) >= tuple(map(int, old['version'].split('.'))), 'Refusing stale website release')
        if old['version'] == v:
            require(old == m, 'Same version has different metadata')
    # Copy first into a private candidate, then verify the exact bytes to be staged.
    # Candidate keeps the canonical filename for metadata validation.
    with tempfile.TemporaryDirectory(prefix='.release-', dir=downloads) as temp:
        candidate = Path(temp) / filename(v)
        require(not source.is_symlink() and source.is_file(), 'Source must be a regular DMG')
        shutil.copyfile(source, candidate)
        verify_dmg(candidate, args.team_id, v, b, m['sha256'])
        destination = downloads / filename(v)
        if destination.exists() or destination.is_symlink():
            require(not destination.is_symlink() and destination.is_file() and digest(destination) == m['sha256'], 'Immutable download already exists with different bytes')
        else:
            os.chmod(candidate, 0o644)
            # Atomic no-clobber create; a concurrent publisher cannot overwrite it.
            os.link(candidate, destination)
        require(digest(destination) == m['sha256'], 'Staged DMG changed')
        atomic_json(manifest_path, m)
    print(f'Staged {destination}; website manifest updated. No deployment performed.')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    for command in ('preflight', 'build', 'verify', 'stage'):
        p = sub.add_parser(command)
        p.add_argument('--team-id', required=True)
        if command in ('preflight', 'build'):
            p.add_argument('--keychain-profile', required=True)
            p.add_argument('--identity')
        if command != 'preflight':
            p.add_argument('--version', required=True)
            p.add_argument('--build', required=True)
        if command in ('verify', 'stage'):
            p.add_argument('--release-dir', type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == 'preflight':
            preflight(args.team_id, args.keychain_profile, args.identity)
            print('Release prerequisites passed')
        elif args.command == 'build':
            build_release(args)
        else:
            verify_or_stage(args, stage=args.command == 'stage')
    except (ReleaseError, OSError, ValueError, KeyError, TypeError) as error:
        print(f'Release blocked: {error}', file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
