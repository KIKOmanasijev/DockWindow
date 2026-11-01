#!/usr/bin/env python3
"""Generate, verify and stage DogBar's signed Sparkle appcast. Stdlib, Apple and Sparkle tools only.

  appcast  Verify a finished build, then run Sparkle's generate_appcast in a new private
           directory. The private EdDSA key stays in the login Keychain; this tool never reads it.
  verify   Re-check a generated appcast and archive against the public key pinned in the repo.
  stage    Copy the verified archive into landing/downloads, then the feed into landing/appcast.xml.
           No deployment or upload is performed.

Every signature is checked here with an independent Ed25519 implementation (RFC 8032),
not by asking Sparkle's tools, which would derive the public key from the Keychain.
"""
import argparse
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'Scripts'))
import sparkle_packaging as sparkle  # noqa: E402

ORIGIN = 'https://dogbar.hristijan.dev'
DOWNLOADS = ORIGIN + '/downloads/'
MINIMUM_MACOS = '26.0'
SPARKLE_NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
SIGNATURE_PREFIX = b'<!-- sparkle-signatures:\n'
CHANNELS = ('preview', 'stable')


class OTAError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise OTAError(message)


# Ed25519 verification, transcribed from RFC 8032 section 6. Verification uses only public data.
P = 2 ** 255 - 19
Q = 2 ** 252 + 27742317777372353535851937790883648493
D = -121665 * pow(121666, P - 2, P) % P
SQRT_M1 = pow(2, (P - 1) // 4, P)


def _add(a, b):
    x = (a[1] - a[0]) * (b[1] - b[0]) % P
    y = (a[1] + a[0]) * (b[1] + b[0]) % P
    c = 2 * a[3] * b[3] * D % P
    d = 2 * a[2] * b[2] % P
    e, f, g, h = y - x, d - c, d + c, y + x
    return e * f % P, g * h % P, f * g % P, e * h % P


def _multiply(scalar, point):
    result = (0, 1, 1, 0)
    while scalar > 0:
        if scalar & 1:
            result = _add(result, point)
        point = _add(point, point)
        scalar >>= 1
    return result


def _equal(a, b):
    return (a[0] * b[2] - b[0] * a[2]) % P == 0 and (a[1] * b[2] - b[1] * a[2]) % P == 0


def _recover_x(y, sign):
    if y >= P:
        return None
    x2 = (y * y - 1) * pow(D * y * y + 1, P - 2, P)
    if x2 == 0:
        return None if sign else 0
    x = pow(x2, (P + 3) // 8, P)
    if (x * x - x2) % P:
        x = x * SQRT_M1 % P
    if (x * x - x2) % P:
        return None
    return P - x if (x & 1) != sign else x


def _decompress(data):
    if len(data) != 32:
        return None
    y = int.from_bytes(data, 'little')
    sign = y >> 255
    y &= (1 << 255) - 1
    x = _recover_x(y, sign)
    return None if x is None else (x, y, 1, x * y % P)


_GY = 4 * pow(5, P - 2, P) % P
_GX = _recover_x(_GY, 0)
BASE = (_GX, _GY, 1, _GX * _GY % P)


def ed25519_verify(public, signature, chunks):
    """chunks: an iterable of message byte strings, so large archives stream through SHA-512."""
    if len(public) != 32 or len(signature) != 64:
        return False
    a, r = _decompress(public), _decompress(signature[:32])
    s = int.from_bytes(signature[32:], 'little')
    if a is None or r is None or s >= Q:
        return False
    digest = hashlib.sha512(signature[:32] + public)
    for chunk in chunks:
        digest.update(chunk)
    h = int.from_bytes(digest.digest(), 'little') % Q
    return _equal(_multiply(s, BASE), _add(r, _multiply(h, a)))


def public_key():
    key = base64.b64decode(sparkle.PUBLIC_KEY, validate=True)
    require(len(key) == 32, 'Pinned SUPublicEDKey is not a 32-byte Ed25519 key')
    return key


def file_chunks(path):
    with open(path, 'rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            yield block


def digest(path):
    value = hashlib.sha256()
    for block in file_chunks(path):
        value.update(block)
    return value.hexdigest()


def load_script(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT / 'Scripts' / name)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run(*args):
    env = dict(os.environ, PATH='/usr/bin:/bin:/usr/sbin:/sbin', LC_ALL='C')
    result = subprocess.run([str(x) for x in args], cwd=ROOT, env=env, capture_output=True, text=True)
    require(result.returncode == 0, f'{Path(str(args[0])).name} failed:\n{result.stdout}\n{result.stderr}')
    return result.stdout


def version_label(value, channel):
    number = r'(?:0|[1-9][0-9]{0,3})'
    suffix = r'-preview\.[1-9][0-9]{0,3}' if channel == 'preview' else ''
    require(isinstance(value, str) and re.fullmatch(fr'{number}\.{number}\.{number}{suffix}', value),
            f'Version {value!r} does not match the {channel} channel')
    return value


def archive_name(value):
    return f'DogBar-{value}-arm64.dmg'


def split_signed_feed(data):
    """Mirror Sparkle's SPUExtractAppcastContent: content precedes the last signature block."""
    start = data.rfind(SIGNATURE_PREFIX)
    require(start >= 0, 'Appcast is not signed')
    end = data.find(b'-->', start + len(SIGNATURE_PREFIX))
    require(end >= 0, 'Appcast signature block is not terminated')
    fields = {}
    for line in data[start + len(SIGNATURE_PREFIX):end].decode('utf-8').splitlines():
        if ':' in line:
            key, value = line.split(':', 1)
            fields[key.strip()] = value.strip()
    require(set(fields) >= {'edSignature', 'length'}, 'Appcast signature block lacks edSignature or length')
    require(not data[end + 3:].strip(), 'Unexpected content after the appcast signature block')
    return data[:start], fields


def verify_feed(path):
    """Return the parsed items of a signed appcast after checking its Ed25519 signature."""
    data = Path(path).read_bytes()
    require(len(data) < 2_000_000, 'Appcast is unexpectedly large')
    content, fields = split_signed_feed(data)
    require(fields['length'].isdigit() and int(fields['length']) == len(content), 'Appcast signed length mismatch')
    signature = base64.b64decode(fields['edSignature'], validate=True)
    require(ed25519_verify(public_key(), signature, [content]), 'Appcast Ed25519 signature does not verify with the pinned public key')
    require(b'<!DOCTYPE' not in content and b'<!ENTITY' not in content, 'Appcast must not declare a DTD or entities')
    root = ET.fromstring(content)
    channel = root.find('channel')
    require(root.tag == 'rss' and channel is not None, 'Appcast is not an RSS channel')
    items = []
    for element in channel.findall('item'):
        enclosure = element.find('enclosure')
        require(enclosure is not None, 'Appcast item without an enclosure')
        hardware = element.findtext(f'{{{SPARKLE_NS}}}hardwareRequirements') or ''
        items.append(dict(
            build=element.findtext(f'{{{SPARKLE_NS}}}version'),
            version=element.findtext(f'{{{SPARKLE_NS}}}shortVersionString'),
            channel=element.findtext(f'{{{SPARKLE_NS}}}channel'),
            minimumSystemVersion=element.findtext(f'{{{SPARKLE_NS}}}minimumSystemVersion'),
            hardware=set(hardware.replace(',', ' ').split()),
            url=enclosure.get('url'), length=enclosure.get('length'),
            signature=enclosure.get(f'{{{SPARKLE_NS}}}edSignature')))
    builds = [x['build'] for x in items]
    require(all(isinstance(b, str) and re.fullmatch(r'[1-9][0-9]{0,8}', b) for b in builds), 'Appcast item has an invalid build')
    require(len(set(builds)) == len(builds), 'Appcast repeats a build number')
    for item in items:
        require(item['channel'] in (None, 'preview'), f'Unknown appcast channel {item["channel"]!r}')
        require(item['minimumSystemVersion'] == MINIMUM_MACOS, f'Build {item["build"]} must require macOS {MINIMUM_MACOS}')
        require('arm64' in item['hardware'], f'Build {item["build"]} must require Apple Silicon')
        name = item['url'][len(DOWNLOADS):] if (item['url'] or '').startswith(DOWNLOADS) else ''
        require(re.fullmatch(r'DogBar-[0-9.]+(?:-preview\.[0-9]+)?-arm64\.dmg', name), f'Build {item["build"]} is not a versioned same-origin download')
        require(item['channel'] == 'preview' or '-preview.' not in name, f'Preview archive for build {item["build"]} is not on the preview channel')
        require(item['signature'] and (item['length'] or '').isdigit(), f'Build {item["build"]} has no EdDSA signature or length')
    return items


def verify_archive(item, archive):
    require(archive.is_file() and not archive.is_symlink(), f'Missing archive {archive.name}')
    require(int(item['length']) == archive.stat().st_size, 'Archive length differs from the appcast')
    signature = base64.b64decode(item['signature'], validate=True)
    require(ed25519_verify(public_key(), signature, file_chunks(archive)), 'Archive EdDSA signature does not verify with the pinned public key')


def find(items, build):
    matches = [x for x in items if x['build'] == build]
    require(len(matches) == 1, f'Appcast has no single item for build {build}')
    return matches[0]


def check_new_item(items, previous, value, build, channel):
    item = find(items, build)
    require(item['url'] == DOWNLOADS + archive_name(value), 'Appcast URL is not the immutable versioned download')
    require(item['channel'] == ('preview' if channel == 'preview' else None), 'Appcast item is on the wrong channel')
    require(item['version'] == value.split('-')[0], 'Appcast short version does not match the bundle')
    older = [int(x['build']) for x in items if x['build'] != build]
    require(all(int(build) > x for x in older), 'New build must be higher than every build already in the feed')
    kept = {x['build']: x for x in items}
    for old in previous:
        require(old['build'] in kept and kept[old['build']]['signature'] == old['signature']
                and kept[old['build']]['url'] == old['url'], f'Existing feed item {old["build"]} was dropped or changed')
    require(len(items) == len(previous) + 1, 'Appcast must add exactly one item')
    return item


def verify_build(channel, value, build, sha, team):
    """Repeat the channel's own artifact gates on the exact DMG before it enters the feed."""
    source = ROOT / 'dist' / f'DogBar-{value}-arm64'
    dmg = source / archive_name(value)
    manifest = json.loads((source / 'release.json').read_text())
    require(manifest.get('sha256') == sha, 'Build manifest SHA-256 differs from --sha256')
    if channel == 'preview':
        preview = load_script('build-preview.py')
        require(manifest == preview.manifest(value, build, sha), 'Preview manifest is inconsistent')
        preview.prerequisites()
        preview.verify_dmg(dmg, preview.fingerprint(preview.DEVELOPMENT_IDENTITY), value, build, sha)
    else:
        release = load_script('release.py')
        require(team, 'Stable feeds require --team-id')
        release.prerequisites()
        release.load_release(source, team, value, build)
        release.verify_dmg(dmg, team, value, build, sha)
    return dmg


def write_once(path, data):
    with open(path, 'x') as stream:
        json.dump(data, stream, indent=2)
        stream.write('\n')


def appcast(args):
    channel, build = args.channel, args.build
    value = version_label(args.version, channel)
    require(re.fullmatch(r'[1-9][0-9]{0,8}', build or ''), 'Build must be a positive integer')
    require(re.fullmatch(r'[a-f0-9]{64}', args.sha256 or ''), 'Use the full lowercase SHA-256 from the build record')
    notes = args.notes.resolve(strict=True)
    require(notes.suffix == '.md' and notes.stat().st_size < 64_000, 'Release notes must be a small Markdown file')
    out = ROOT / 'dist/ota' / f'DogBar-{value}-arm64'
    require(not out.exists() and not out.is_symlink(), 'OTA output already exists; never regenerate a published feed item')
    dmg = verify_build(channel, value, build, args.sha256, args.team_id)
    published = ROOT / 'landing/appcast.xml'
    previous = verify_feed(published) if published.exists() else []
    tools = sparkle.tools(ROOT / '.build')
    out.mkdir(parents=True)
    work = out / 'archives'
    work.mkdir()
    shutil.copyfile(dmg, work / dmg.name)
    require(digest(work / dmg.name) == args.sha256, 'Archive changed while copying')
    shutil.copyfile(notes, work / f'DogBar-{value}-arm64.md')
    if previous:
        shutil.copyfile(published, work / 'appcast.xml')
    command = [tools / 'generate_appcast', '--account', sparkle.KEYCHAIN_ACCOUNT, '--download-url-prefix', DOWNLOADS,
               '--link', ORIGIN + '/', '--embed-release-notes', '--maximum-deltas', '0', '--maximum-versions', '0']
    if channel == 'preview':
        command += ['--channel', 'preview']
    # Signs the archive and, because the bundle sets SURequireSignedFeed, the whole feed.
    run(*command, work)
    feed = work / 'appcast.xml'
    items = verify_feed(feed)
    item = check_new_item(items, previous, value, build, channel)
    verify_archive(item, work / dmg.name)
    require(digest(work / dmg.name) == args.sha256, 'Archive changed during feed generation')
    require(set(x.name for x in work.iterdir()) <= {dmg.name, f'DogBar-{value}-arm64.md', 'appcast.xml', 'old_updates'},
            'generate_appcast produced unexpected files')
    shutil.copyfile(feed, out / 'appcast.xml')
    write_once(out / 'ota.json', dict(channel=channel, version=value, build=build, archive=dmg.name, sha256=args.sha256,
               length=int(item['length']), edSignature=item['signature'], appcastSHA256=digest(out / 'appcast.xml'),
               publicKey=sparkle.PUBLIC_KEY, sparkle=sparkle.VERSION, notarized=channel == 'stable'))
    print(f'Signed {channel} appcast: {out / "appcast.xml"}\nArchive: {work / dmg.name}\nNo staging or deployment performed.')


def load_ota(directory, sha):
    directory = Path(directory).resolve(strict=True)
    record = json.loads((directory / 'ota.json').read_text())
    require(record.get('sha256') == sha, 'OTA record SHA-256 differs from --sha256')
    require(record.get('publicKey') == sparkle.PUBLIC_KEY, 'OTA record was signed for a different public key')
    value = version_label(record.get('version'), record.get('channel'))
    require(record.get('archive') == archive_name(value), 'OTA record names an unexpected archive')
    feed = directory / 'appcast.xml'
    require(digest(feed) == record.get('appcastSHA256'), 'Appcast changed since generation')
    items = verify_feed(feed)
    item = find(items, record['build'])
    require(item['url'] == DOWNLOADS + record['archive'] and item['signature'] == record['edSignature'], 'Appcast item differs from OTA record')
    archive = directory / 'archives' / record['archive']
    require(digest(archive) == sha, 'Archive SHA-256 mismatch')
    verify_archive(item, archive)
    return directory, record, items, archive


def atomic_copy(source, destination):
    fd, name = tempfile.mkstemp(prefix='.ota-', dir=destination.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(Path(source).read_bytes())
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(name, 0o644)
        os.replace(name, destination)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def stage(args):
    directory, record, items, archive = load_ota(args.dir, args.sha256)
    landing = ROOT / 'landing'
    downloads = landing / 'downloads'
    feed = landing / 'appcast.xml'
    require(not landing.is_symlink() and not downloads.is_symlink() and not feed.is_symlink(), 'Website paths must not be symlinks')
    if feed.exists():
        current = {x['build']: x for x in verify_feed(feed)}
        new = {x['build']: x for x in items}
        require(all(b in new and new[b]['signature'] == x['signature'] for b, x in current.items()),
                'Staged feed would drop or change an item that is already published')
    downloads.mkdir(exist_ok=True)
    destination = downloads / record['archive']
    if destination.exists() or destination.is_symlink():
        require(destination.is_file() and not destination.is_symlink() and digest(destination) == args.sha256,
                'Immutable download already exists with different bytes')
    else:
        with tempfile.TemporaryDirectory(prefix='.ota-', dir=downloads) as temp:
            candidate = Path(temp) / record['archive']
            shutil.copyfile(archive, candidate)
            require(digest(candidate) == args.sha256, 'Archive changed while staging')
            os.chmod(candidate, 0o644)
            os.link(candidate, destination)  # No-clobber create.
    if record['channel'] == 'preview':
        # Pre-OTA previews read preview.json and install manually; this is their one bridge.
        atomic_copy(ROOT / 'dist' / f'DogBar-{record["version"]}-arm64/release.json', landing / 'preview.json')
    # The feed goes last, so no client is offered an update before its archive is in place.
    atomic_copy(directory / 'appcast.xml', feed)
    print(f'Staged {destination} and {feed}. No deployment performed.')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    a = sub.add_parser('appcast')
    a.add_argument('--channel', choices=CHANNELS, required=True)
    a.add_argument('--version', required=True)
    a.add_argument('--build', required=True)
    a.add_argument('--sha256', required=True)
    a.add_argument('--notes', type=Path, required=True, help='Markdown release notes embedded in the signed feed')
    a.add_argument('--team-id', help='Developer ID Team ID, required for stable')
    for name in ('verify', 'stage'):
        p = sub.add_parser(name)
        p.add_argument('--dir', type=Path, required=True)
        p.add_argument('--sha256', required=True, help='Independently known archive SHA-256')
    args = parser.parse_args()
    try:
        if args.command == 'appcast':
            appcast(args)
        elif args.command == 'verify':
            _, record, _, _ = load_ota(args.dir, args.sha256)
            print(f'Verified signed appcast and archive for {record["version"]} (build {record["build"]})')
        else:
            stage(args)
    except Exception as error:  # noqa: BLE001 - every failure must block staging with a message.
        print(f'OTA blocked: {type(error).__name__}: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
