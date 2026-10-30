#!/usr/bin/env python3
"""Build an explicitly unnotarized, self-signed DogBar preview. No publishing."""
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

ROOT = Path(__file__).resolve().parents[1]
DEVELOPMENT_IDENTITY = 'F6525801B1C563EA82693EBE71D63C6CA41538C6'
ENTITLEMENTS = {'com.apple.security.automation.apple-events': True}
OPEN_GUIDE = 'https://support.apple.com/102445'


class PreviewError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise PreviewError(message)


def version(value):
    number = r'(?:0|[1-9][0-9]{0,3})'
    require(isinstance(value, str) and re.fullmatch(fr'{number}\.{number}\.{number}-preview\.[1-9][0-9]{{0,3}}', value),
            'Use a preview version such as 0.1.0-preview.1')
    return value


def build_number(value):
    require(isinstance(value, str) and re.fullmatch(r'[1-9][0-9]{0,8}', value), 'Build must be a positive integer, up to 9 digits')
    return value


def fingerprint(value):
    require(isinstance(value, str) and re.fullmatch(r'[A-Fa-f0-9]{40}', value), 'Identity must be its 40-character certificate SHA-1 fingerprint')
    return value.upper()


def filename(value):
    return f'DogBar-{version(value)}-arm64.dmg'


def run(*args):
    env = dict(os.environ, PATH='/usr/bin:/bin:/usr/sbin:/sbin', LC_ALL='C')
    result = subprocess.run([str(x) for x in args], cwd=ROOT, env=env, capture_output=True, text=True)
    require(result.returncode == 0, f'{args[0]} {args[1] if len(args) > 1 else ""} failed:\n{result.stdout}\n{result.stderr}')
    return result.stdout if result.stdout.strip() else result.stderr


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def select_identity(output, requested):
    requested = fingerprint(requested)
    matches = {sha.upper() for sha, name in re.findall(r'\b([A-Fa-f0-9]{40})\s+"([^"\n]+)"', output)
               if name == 'DockWindow Dev'}
    require(requested in matches, 'Requested DockWindow Dev signing identity is unavailable; preview builds never fall back to ad-hoc signing')
    return requested


def prerequisites():
    require(platform.system() == 'Darwin', 'Preview packaging requires macOS and Apple tools')
    for name in ('security', 'codesign', 'hdiutil', 'swift', 'xcrun'):
        require(shutil.which(name, path='/usr/bin:/bin:/usr/sbin:/sbin'), f'Missing Apple tool: {name}')
    run('xcrun', '--find', 'lipo')
    run('swift', '--version')


def requirement(identity, app=False):
    value = f'certificate leaf = H"{fingerprint(identity)}"'
    if app:
        value += ' and identifier "com.dockwindow.app"'
    return value


def verify_signature(path, identity, app=False):
    run('codesign', '--verify', '--deep', '--strict', '-R=' + requirement(identity, app), path)
    detail = run('codesign', '--display', '--verbose=4', path)
    require('Authority=DockWindow Dev\n' in detail and 'Signature=adhoc' not in detail,
            'Expected the self-signed DockWindow Dev identity, not ad-hoc or Developer ID signing')
    if app:
        require(re.search(r'flags=0x[0-9a-f]+\([^\n]*runtime', detail), 'Missing hardened runtime')
        xml = run('codesign', '--display', '--entitlements', '-', '--xml', path)
        begin, end = xml.find('<?xml'), xml.find('</plist>')
        require(begin >= 0 and end >= begin, 'Cannot read signed entitlements')
        require(plistlib.loads(xml[begin:end + len('</plist>')].encode()) == ENTITLEMENTS,
                'Unexpected signed entitlements')


def verify_app(app, identity, value, build):
    version(value)
    build_number(build)
    require(app.is_dir() and not app.is_symlink(), 'Expected a real DogBar.app bundle')
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    expected = dict(CFBundleIdentifier='com.dockwindow.app', CFBundleExecutable='DockWindow',
                    CFBundleName='DogBar', CFBundleDisplayName='DogBar',
                    CFBundleShortVersionString=value.split('-')[0], DogBarPreviewVersion=value,
                    CFBundleVersion=build, LSMinimumSystemVersion='14.0')
    require(all(info.get(key) == item for key, item in expected.items()), 'Preview app metadata mismatch')
    require(run('xcrun', 'lipo', '-archs', app / 'Contents/MacOS/DockWindow').strip() == 'arm64', 'Preview executable must be arm64 only')
    verify_signature(app, identity, app=True)


def verify_dmg(dmg, identity, value, build, expected_hash=None):
    version(value)
    build_number(build)
    require(dmg.is_file() and not dmg.is_symlink() and dmg.name == filename(value), 'Unexpected preview DMG path or filename')
    before = digest(dmg)
    if expected_hash is not None:
        require(isinstance(expected_hash, str) and re.fullmatch(r'[a-f0-9]{64}', expected_hash), 'Invalid SHA-256')
        require(before == expected_hash, 'Preview DMG hash mismatch')
    verify_signature(dmg, identity)
    run('hdiutil', 'verify', dmg)
    require(run('hdiutil', 'imageinfo', '-format', dmg).strip().splitlines()[-1] == 'UDZO', 'Preview DMG must be compressed read-only UDZO')
    with tempfile.TemporaryDirectory(prefix='dogbar-preview-verify-') as temp:
        mount = Path(temp) / 'volume'
        mount.mkdir()
        attached = False
        try:
            run('hdiutil', 'attach', dmg, '-readonly', '-noautoopen', '-mountpoint', mount)
            attached = True
            permitted = {'DogBar.app', 'Applications', 'Read Me.txt', '.DS_Store', '.fseventsd', '.Trashes', '.HFS+ Private Directory Data\r', '.Spotlight-V100'}
            require(set(x.name for x in mount.iterdir()) <= permitted, 'Unexpected files in preview DMG')
            link = mount / 'Applications'
            require(link.is_symlink() and os.readlink(link) == '/Applications', 'Missing Applications shortcut')
            readme = mount / 'Read Me.txt'
            require(readme.is_file() and not readme.is_symlink(), 'Missing preview installation note')
            text = readme.read_text()
            require('not notarized' in text and 'self-signed' in text and OPEN_GUIDE in text, 'Missing clear preview disclosure')
            verify_app(mount / 'DogBar.app', identity, value, build)
        finally:
            if attached or os.path.ismount(mount):
                run('hdiutil', 'detach', mount)
    require(digest(dmg) == before, 'Preview DMG changed during verification')
    return before


def manifest(value, build, sha):
    version(value)
    build_number(build)
    require(isinstance(sha, str) and re.fullmatch(r'[a-f0-9]{64}', sha), 'Invalid SHA-256')
    return dict(available=True, notarized=False, channel='preview', signing='self-signed',
                version=value, build=build, url='/downloads/' + filename(value), sha256=sha,
                architecture='arm64', minimumMacOS='14.0')


def write_json(path, value):
    # New immutable output directory only. No replacing an existing success marker.
    with path.open('x') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')


def build_preview(args):
    value, build = version(args.version), build_number(args.build)
    identity = fingerprint(args.identity)
    parent = ROOT / 'dist'
    require(not parent.is_symlink(), 'dist must not be a symlink')
    out = parent / f'DogBar-{value}-arm64'
    require(not out.exists() and not out.is_symlink(), 'Preview version output already exists; choose a new version')
    prerequisites()
    # Valid-only identity lookup excludes this deliberately self-signed local certificate.
    select_identity(run('security', 'find-identity', '-p', 'codesigning'), identity)
    entitlements = ROOT / 'Resources/DockWindow.entitlements'
    require(plistlib.loads(entitlements.read_bytes()) == ENTITLEMENTS, 'Review changed entitlements before packaging')
    parent.mkdir(exist_ok=True)
    out.mkdir()
    scratch = out / 'build'
    command = ['swift', 'build', '--scratch-path', scratch, '-c', 'release', '--triple', 'arm64-apple-macosx14.0', '--product', 'DockWindow']
    run(*command)
    binary_dir = Path(run(*command, '--show-bin-path').strip())
    require(binary_dir.resolve().is_relative_to(scratch.resolve()), 'Swift executable must come from the isolated preview build')
    stage = out / 'image'
    app = stage / 'DogBar.app'
    (app / 'Contents/MacOS').mkdir(parents=True)
    (app / 'Contents/Resources').mkdir()
    shutil.copy2(binary_dir / 'DockWindow', app / 'Contents/MacOS/DockWindow')
    shutil.copy2(ROOT / 'Resources/AppIcon.icns', app / 'Contents/Resources/AppIcon.icns')
    info = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())
    info.update(CFBundleIdentifier='com.dockwindow.app', CFBundleExecutable='DockWindow',
                CFBundleName='DogBar', CFBundleDisplayName='DogBar',
                CFBundleShortVersionString=value.split('-')[0], DogBarPreviewVersion=value,
                CFBundleVersion=build, LSMinimumSystemVersion='14.0')
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    run('codesign', '--force', '--sign', identity, '--options', 'runtime', '--timestamp=none', '--entitlements', entitlements, app)
    verify_app(app, identity, value, build)
    (stage / 'Applications').symlink_to('/Applications')
    (stage / 'Read Me.txt').write_text(
        f'DogBar {value} (build {build})\n\n'
        'This is an experimental, self-signed preview, not notarized by Apple. macOS Gatekeeper may block it.\n'
        'Requires Apple Silicon and macOS 14 or newer.\n\n'
        'Copy DogBar.app to Applications, then open it. Grant Accessibility and Screen Recording in System Settings when requested.\n'
        'If macOS blocks opening, review the developer and source before using Apple\'s Privacy & Security > Open Anyway flow:\n'
        f'{OPEN_GUIDE}\n\n'
        'A code signature detects modification; this self-signed certificate does not establish Apple-verified developer identity.\n'
        'Do not disable Gatekeeper or remove quarantine to install.\n')
    dmg = out / filename(value)
    run('hdiutil', 'create', '-volname', 'DogBar Preview', '-srcfolder', stage, '-format', 'UDZO', '-fs', 'HFS+', dmg)
    run('codesign', '--sign', identity, '--timestamp=none', dmg)
    sha = verify_dmg(dmg, identity, value, build)
    write_json(out / 'provenance.json', dict(version=value, build=build, signing='self-signed',
               certificateSHA1=identity, sha256=sha, notarized=False))
    write_json(out / 'release.json', manifest(value, build, sha))
    print(f'Unnotarized self-signed preview: {dmg}\nSHA-256: {sha}\nManifest: {out / "release.json"}\nNo website staging or deployment performed.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True)
    parser.add_argument('--identity', default=DEVELOPMENT_IDENTITY, help='DockWindow Dev certificate SHA-1 fingerprint')
    parser.add_argument('--verify-dmg', type=Path, help='Verify an existing preview instead of building')
    parser.add_argument('--sha256', help='Required expected hash with --verify-dmg')
    args = parser.parse_args()
    try:
        if args.verify_dmg is not None:
            require(args.sha256 is not None, '--verify-dmg requires an independently known --sha256')
            prerequisites()
            sha = verify_dmg(args.verify_dmg, fingerprint(args.identity), args.version, args.build, args.sha256)
            print(f'Verified unnotarized self-signed preview: {args.verify_dmg}\nSHA-256: {sha}')
        else:
            require(args.sha256 is None, '--sha256 is only valid with --verify-dmg')
            build_preview(args)
    except (PreviewError, OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f'Preview failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
