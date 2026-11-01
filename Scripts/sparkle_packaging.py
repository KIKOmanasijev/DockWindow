#!/usr/bin/env python3
"""Embed, sign and verify the pinned Sparkle.framework inside DogBar.app. Stdlib and Apple tools only.

The framework comes from SwiftPM's checksum-verified binary artifact for the exact version
pinned in Package.swift and Package.resolved. Nested code is signed inside out with the same
identity as the app; the app itself is signed by the caller, without --deep.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
VERSION = '2.10.1'
IDENTIFIER = 'org.sparkle-project.Sparkle'
FRAMEWORK = 'Contents/Frameworks/Sparkle.framework'
# Relative to the framework. XPC services are only for sandboxed apps; DogBar is not sandboxed.
HELPERS = ('Versions/B/Autoupdate', 'Versions/B/Updater.app')
MACHO = ('Versions/B/Sparkle', 'Versions/B/Autoupdate', 'Versions/B/Updater.app/Contents/MacOS/Updater')
LINKS = {'Versions/Current': 'B', 'Sparkle': 'Versions/Current/Sparkle', 'Autoupdate': 'Versions/Current/Autoupdate',
         'Updater.app': 'Versions/Current/Updater.app', 'Resources': 'Versions/Current/Resources',
         'Headers': 'Versions/Current/Headers', 'Modules': 'Versions/Current/Modules',
         'PrivateHeaders': 'Versions/Current/PrivateHeaders'}
# Updater settings every packaged DogBar must carry. The public key matches the private key
# stored only in the release Mac's login Keychain (generate_keys --account dev.hristijan.dogbar).
KEYCHAIN_ACCOUNT = 'dev.hristijan.dogbar'
PUBLIC_KEY = 'PNudz/8nyHP1fR6ADTVhfXAciGkEoyOpTEgHkJ8Hb/0='
FEED_URL = 'https://dogbar.hristijan.dev/appcast.xml'
UPDATER_INFO = dict(SUFeedURL=FEED_URL, SUPublicEDKey=PUBLIC_KEY, SUVerifyUpdateBeforeExtraction=True,
                    SURequireSignedFeed=True, SUSignedFeedFailureExpirationInterval=0,
                    SUAutomaticallyUpdate=False, SUAllowsAutomaticUpdates=False, SUEnableSystemProfiling=False)
MAGIC = {b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xce\xfa\xed\xfe', b'\xbe\xba\xfe\xca'}


class SparkleError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise SparkleError(message)


def run(*args):
    env = dict(os.environ, PATH='/usr/bin:/bin:/usr/sbin:/sbin', LC_ALL='C')
    result = subprocess.run([str(x) for x in args], cwd=ROOT, env=env, capture_output=True, text=True)
    require(result.returncode == 0, f'{args[0]} {args[1] if len(args) > 1 else ""} failed:\n{result.stdout}\n{result.stderr}')
    return result.stdout if result.stdout.strip() else result.stderr


def pinned():
    """The exact Sparkle version recorded by SwiftPM. Changing it is a reviewed edit."""
    pins = json.loads((ROOT / 'Package.resolved').read_text()).get('pins', [])
    sparkle = [x for x in pins if x.get('identity') == 'sparkle']
    require(len(sparkle) == 1 and sparkle[0].get('location') == 'https://github.com/sparkle-project/Sparkle'
            and sparkle[0].get('state', {}).get('version') == VERSION, f'Package.resolved must pin Sparkle {VERSION}')
    require(f'exact: "{VERSION}"' in (ROOT / 'Package.swift').read_text(), f'Package.swift must pin Sparkle exactly {VERSION}')
    return VERSION


def artifact(scratch):
    """SwiftPM extracts the binary target only after verifying its pinned checksum."""
    pinned()
    base = Path(scratch) / 'artifacts/sparkle/Sparkle'
    source = base / 'Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
    require(source.is_dir() and not source.is_symlink(), f'Missing Sparkle artifact in {base}; run swift package resolve')
    info = plistlib.loads((source / 'Versions/B/Resources/Info.plist').read_bytes())
    require(info.get('CFBundleIdentifier') == IDENTIFIER and info.get('CFBundleShortVersionString') == VERSION,
            f'Sparkle artifact is not {IDENTIFIER} {VERSION}')
    return source


def tools(scratch):
    pinned()
    folder = Path(scratch) / 'artifacts/sparkle/Sparkle/bin'
    for name in ('generate_appcast', 'sign_update', 'generate_keys'):
        require((folder / name).is_file() and os.access(folder / name, os.X_OK), f'Missing Sparkle tool {name}')
    return folder


def machos(root):
    found = set()
    for path in Path(root).rglob('*'):
        if path.is_file() and not path.is_symlink():
            with path.open('rb') as stream:
                if stream.read(4) in MAGIC:
                    found.add(str(path.relative_to(root)))
    return found


def embed(app, source, identity, timestamp=False):
    """Copy into a staged app, keep only arm64 slices, drop XPC services, sign nested code inside out."""
    app = Path(app)
    target = app / FRAMEWORK
    require(app.is_dir() and not target.exists(), 'Embed into a freshly staged app without a framework')
    target.parent.mkdir(parents=True, exist_ok=True)
    run('ditto', source, target)  # Preserves the versioned symlinks and executable permissions.
    shutil.rmtree(target / 'Versions/B/XPCServices')
    (target / 'XPCServices').unlink()
    require(machos(target) == set(MACHO), 'Unexpected executable code in Sparkle.framework')
    for relative in MACHO:
        binary = target / relative
        if run('xcrun', 'lipo', '-archs', binary).split() != ['arm64']:
            run('xcrun', 'lipo', binary, '-thin', 'arm64', '-output', binary)
    stamp = '--timestamp' if timestamp else '--timestamp=none'
    for relative in HELPERS:
        run('codesign', '--force', '--sign', identity, '--options', 'runtime', stamp, target / relative)
    run('codesign', '--force', '--sign', identity, '--options', 'runtime', stamp, target)


def verify(app, requirement):
    """Check the embedded framework layout and that every nested item satisfies requirement."""
    target = Path(app) / FRAMEWORK
    require(target.is_dir() and not target.is_symlink(), 'Missing embedded Sparkle.framework')
    for link, destination in LINKS.items():
        path = target / link
        require(path.is_symlink() and os.readlink(path) == destination, f'Sparkle.framework symlink {link} is wrong')
    require(set(x.name for x in target.iterdir()) == set(LINKS) - {'Versions/Current'} | {'Versions'},
            'Unexpected top-level items in Sparkle.framework')
    require(set(x.name for x in (target / 'Versions').iterdir()) == {'B', 'Current'}, 'Unexpected Sparkle framework versions')
    require(not (target / 'Versions/B/XPCServices').exists(), 'XPC services must not be embedded')
    info = plistlib.loads((target / 'Versions/B/Resources/Info.plist').read_bytes())
    require(info.get('CFBundleIdentifier') == IDENTIFIER and info.get('CFBundleShortVersionString') == VERSION,
            f'Embedded framework is not {IDENTIFIER} {VERSION}')
    require(machos(target) == set(MACHO), 'Unexpected executable code in embedded Sparkle.framework')
    for relative in MACHO:
        binary = target / relative
        require(os.access(binary, os.X_OK), f'{relative} lost its executable permission')
        require(run('xcrun', 'lipo', '-archs', binary).split() == ['arm64'], f'{relative} must be arm64 only')
    for item in [target / x for x in HELPERS] + [target]:
        run('codesign', '--verify', '--strict', '--verbose=2', '-R=' + requirement, item)
        detail = run('codesign', '--display', '--verbose=4', item)
        require('Signature=adhoc' not in detail, f'{item.name} must not be ad-hoc signed')
        require(re.search(r'flags=0x[0-9a-f]+\([^\n]*runtime', detail), f'{item.name} is missing hardened runtime')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    for command in ('embed', 'verify'):
        p = sub.add_parser(command)
        p.add_argument('--app', type=Path, required=True)
        if command == 'embed':
            p.add_argument('--scratch', type=Path, required=True, help='SwiftPM scratch path holding resolved artifacts')
            p.add_argument('--identity', required=True)
        else:
            p.add_argument('--requirement', required=True)
    args = parser.parse_args()
    try:
        if args.command == 'embed':
            embed(args.app, artifact(args.scratch), args.identity)
        else:
            verify(args.app, args.requirement)
    except (SparkleError, OSError, ValueError, KeyError, plistlib.InvalidFileException) as error:
        print(f'Sparkle packaging failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
