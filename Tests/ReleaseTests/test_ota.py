import base64
import hashlib
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[2] / 'Scripts'
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location('ota', SCRIPTS / 'ota.py')
o = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(o)

# RFC 8032 section 7.1, test 1. Public test data only; never a real DogBar key.
SECRET = bytes.fromhex('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60')
PUBLIC = bytes.fromhex('d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a')
EMPTY_SIGNATURE = bytes.fromhex('e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b')


def compress(point):
    inverse = pow(point[2], o.P - 2, o.P)
    x, y = point[0] * inverse % o.P, point[1] * inverse % o.P
    return (y | ((x & 1) << 255)).to_bytes(32, 'little')


def sign(message):
    """Test-only RFC 8032 signer for building fixtures."""
    h = hashlib.sha512(SECRET).digest()
    a = (int.from_bytes(h[:32], 'little') & ((1 << 254) - 8)) | (1 << 254)
    r = int.from_bytes(hashlib.sha512(h[32:] + message).digest(), 'little') % o.Q
    big_r = compress(o._multiply(r, o.BASE))
    k = int.from_bytes(hashlib.sha512(big_r + PUBLIC + message).digest(), 'little') % o.Q
    return big_r + ((r + k * a) % o.Q).to_bytes(32, 'little')


def item(build, version, archive, channel='preview', minimum='26.0', hardware='arm64'):
    channel_xml = f'<sparkle:channel>{channel}</sparkle:channel>' if channel else ''
    signature = base64.b64encode(sign(archive)).decode()
    return (f'<item><title>{version}</title><sparkle:version>{build}</sparkle:version>'
            f'<sparkle:shortVersionString>{version.split("-")[0]}</sparkle:shortVersionString>{channel_xml}'
            f'<sparkle:minimumSystemVersion>{minimum}</sparkle:minimumSystemVersion>'
            f'<sparkle:hardwareRequirements>{hardware}</sparkle:hardwareRequirements>'
            f'<enclosure url="{o.DOWNLOADS}DogBar-{version}-arm64.dmg" length="{len(archive)}" type="application/octet-stream" sparkle:edSignature="{signature}"/></item>')


def feed(*items):
    content = ('<?xml version="1.0" standalone="yes"?>\n<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">'
               f'<channel><title>DogBar</title>{"".join(items)}</channel></rss>\n').encode()
    signature = base64.b64encode(sign(content)).decode()
    return content + f'<!-- sparkle-signatures:\nedSignature: {signature}\nlength: {len(content)}\n-->\n'.encode()


class OTATests(unittest.TestCase):
    def setUp(self):
        patcher = patch.object(o.sparkle, 'PUBLIC_KEY', base64.b64encode(PUBLIC).decode())
        patcher.start()
        self.addCleanup(patcher.stop)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write(self, data, name='appcast.xml'):
        path = self.root / name
        path.write_bytes(data)
        return path

    def test_rfc8032_vector_and_tampering(self):
        self.assertTrue(o.ed25519_verify(PUBLIC, EMPTY_SIGNATURE, [b'']))
        self.assertEqual(sign(b''), EMPTY_SIGNATURE)
        self.assertFalse(o.ed25519_verify(PUBLIC, EMPTY_SIGNATURE, [b'x']))
        self.assertFalse(o.ed25519_verify(PUBLIC, EMPTY_SIGNATURE[:63] + b'\x00', [b'']))
        self.assertFalse(o.ed25519_verify(PUBLIC[:31], EMPTY_SIGNATURE, [b'']))

    def test_signed_feed_and_archive_verify(self):
        archive = b'fixture dmg'
        items = o.verify_feed(self.write(feed(item('7', '0.1.0-preview.6', archive))))
        self.assertEqual(items[0]['build'], '7')
        self.assertEqual(items[0]['channel'], 'preview')
        path = self.write(archive, 'DogBar-0.1.0-preview.6-arm64.dmg')
        o.verify_archive(items[0], path)
        path.write_bytes(b'fixture dmh')
        with self.assertRaises(o.OTAError):
            o.verify_archive(items[0], path)

    def test_unsigned_tampered_or_truncated_feeds_are_rejected(self):
        signed = feed(item('7', '0.1.0-preview.6', b'a'))
        content, _ = o.split_signed_feed(signed)
        for data in (content, signed.replace(b'<title>DogBar', b'<title>Evil!'), signed + b'<rss/>',
                     signed.replace(b'length: ', b'length: 1')):
            with self.subTest(data=data[-40:]), self.assertRaises(o.OTAError):
                o.verify_feed(self.write(data))

    def test_feed_policy_rejects_unsafe_items(self):
        bad = [
            item('7', '0.1.0-preview.6', b'a', channel=None),  # Preview archive offered to stable builds.
            item('7', '0.1.0-preview.6', b'a', channel='beta'),
            item('7', '0.1.0-preview.6', b'a', minimum='12.0'),
            item('7', '0.1.0-preview.6', b'a', hardware='x86_64'),
            item('7', '0.1.0-preview.6', b'a').replace(o.DOWNLOADS, 'https://example.com/downloads/'),
            item('7', '0.1.0-preview.6', b'a') + item('7', '0.1.0-preview.7', b'b'),
        ]
        for value in bad:
            with self.subTest(value=value[:60]), self.assertRaises(o.OTAError):
                o.verify_feed(self.write(feed(value)))

    def test_new_item_must_be_higher_and_preserve_published_items(self):
        old = o.verify_feed(self.write(feed(item('7', '0.1.0-preview.6', b'a'))))
        both = o.verify_feed(self.write(feed(item('8', '0.1.0-preview.7', b'b'), item('7', '0.1.0-preview.6', b'a'))))
        self.assertEqual(o.check_new_item(both, old, '0.1.0-preview.7', '8', 'preview')['build'], '8')
        with self.assertRaises(o.OTAError):
            o.check_new_item(both, old, '0.1.0-preview.7', '8', 'stable')
        lower = o.verify_feed(self.write(feed(item('6', '0.1.0-preview.7', b'b'), item('7', '0.1.0-preview.6', b'a'))))
        with self.assertRaises(o.OTAError):
            o.check_new_item(lower, old, '0.1.0-preview.7', '6', 'preview')
        dropped = o.verify_feed(self.write(feed(item('8', '0.1.0-preview.7', b'b'))))
        with self.assertRaises(o.OTAError):
            o.check_new_item(dropped, old, '0.1.0-preview.7', '8', 'preview')

    def test_versions_follow_their_channel(self):
        self.assertEqual(o.version_label('0.1.0-preview.6', 'preview'), '0.1.0-preview.6')
        self.assertEqual(o.version_label('1.0.0', 'stable'), '1.0.0')
        for value, channel in (('0.1.0-preview.6', 'stable'), ('../x', 'preview'), ('0.1.0-beta.1', 'preview'), (None, 'stable')):
            with self.subTest(value=value), self.assertRaises(o.OTAError):
                o.version_label(value, channel)


if __name__ == '__main__':
    unittest.main()
