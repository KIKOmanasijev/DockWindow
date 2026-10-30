import argparse
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('preview', Path(__file__).resolve().parents[2] / 'Scripts/build-preview.py')
p = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(p)
SHA = p.DEVELOPMENT_IDENTITY
VERSION = '0.1.0-preview.1'


class PreviewTests(unittest.TestCase):
    def test_only_explicit_preview_versions_and_positive_builds(self):
        self.assertEqual(p.version(VERSION), VERSION)
        for value in ('0.1.0', '../x', '01.1.0-preview.1', '0.1.0-preview.0', '0.1.0-preview.1/evil', '0.1.0-beta.1', None):
            with self.subTest(value=value), self.assertRaises(p.PreviewError):
                p.version(value)
        for value in ('0', '-1', '1/../x', '2; touch x', 2, '1234567890'):
            with self.subTest(value=value), self.assertRaises(p.PreviewError):
                p.build_number(value)

    def test_self_signed_identity_is_selected_without_valid_only_or_fallback(self):
        output = f'1) {SHA} "DockWindow Dev" (CSSMERR_TP_NOT_TRUSTED)\n0 valid identities found'
        self.assertEqual(p.select_identity(output, SHA.lower()), SHA)
        for text in ('0 identities found', output.replace('DockWindow Dev', 'Developer ID Application: Example'), output.replace(SHA, 'A' * 40)):
            with self.assertRaises(p.PreviewError):
                p.select_identity(text, SHA)
        for value in ('-', '', 'A' * 39, 'G' * 40):
            with self.assertRaises(p.PreviewError):
                p.fingerprint(value)

    def test_manifest_cannot_claim_notarization_or_an_external_url(self):
        value = p.manifest(VERSION, '2', 'a' * 64)
        self.assertIs(value['notarized'], False)
        self.assertEqual(value['channel'], 'preview')
        self.assertEqual(value['signing'], 'self-signed')
        self.assertEqual(value['url'], '/downloads/DogBar-0.1.0-preview.1-arm64.dmg')
        self.assertEqual(value['architecture'], 'arm64')
        for sha in ('A' * 64, 'a' * 63, 'g' * 64, None):
            with self.assertRaises(p.PreviewError):
                p.manifest(VERSION, '2', sha)

    def test_signature_is_bound_to_certificate_identifier_runtime_and_entitlements(self):
        req = p.requirement(SHA, app=True)
        self.assertIn(SHA, req)
        self.assertIn('identifier "com.dockwindow.app"', req)
        self.assertNotIn('anchor apple', req)
        detail = 'Authority=DockWindow Dev\nflags=0x10000(runtime)\n'
        xml = plistlib.dumps(p.ENTITLEMENTS).decode()
        with patch.object(p, 'run', side_effect=['', detail, xml]) as run:
            p.verify_signature(Path('DogBar.app'), SHA, app=True)
            self.assertIn('--strict', run.call_args_list[0].args)
            self.assertIn('-R=' + req, run.call_args_list[0].args)
        for bad in ('Authority=DockWindow Dev\nSignature=adhoc\n', 'Authority=Developer ID Application: Example\n', 'Authority=DockWindow Dev\n'):
            with patch.object(p, 'run', side_effect=['', bad]), self.assertRaises(p.PreviewError):
                p.verify_signature(Path('DogBar.app'), SHA, app=True)
        with patch.object(p, 'run', side_effect=['', detail, plistlib.dumps({'com.apple.security.get-task-allow': True}).decode()]), self.assertRaises(p.PreviewError):
            p.verify_signature(Path('DogBar.app'), SHA, app=True)

    def test_bad_hash_and_symlink_are_rejected_before_apple_tools(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(p, 'run') as run:
            dmg = Path(temp) / p.filename(VERSION)
            dmg.write_bytes(b'fixture')
            with self.assertRaises(p.PreviewError):
                p.verify_dmg(dmg, SHA, VERSION, '2', 'a' * 64)
            run.assert_not_called()
            dmg.unlink()
            dmg.symlink_to(Path(temp) / 'missing')
            with self.assertRaises(p.PreviewError):
                p.verify_dmg(dmg, SHA, VERSION, '2')
            run.assert_not_called()

    def test_readonly_image_is_detached_when_inner_app_verification_fails(self):
        events = []
        def run(*args):
            events.append(tuple(map(str, args)))
            if args[:2] == ('hdiutil', 'imageinfo'):
                return 'UDZO\n'
            if args[:2] == ('hdiutil', 'attach'):
                self.assertIn('-readonly', args)
                self.assertIn('-noautoopen', args)
                mount = Path(args[-1])
                (mount / 'DogBar.app').mkdir()
                (mount / 'Applications').symlink_to('/Applications')
                (mount / 'Read Me.txt').write_text(f'self-signed, not notarized\n{p.OPEN_GUIDE}')
            return ''
        with tempfile.TemporaryDirectory() as temp:
            dmg = Path(temp) / p.filename(VERSION)
            dmg.write_bytes(b'fixture')
            with patch.object(p, 'run', side_effect=run), patch.object(p, 'verify_signature'), patch.object(p, 'verify_app', side_effect=p.PreviewError('wrong app metadata')), self.assertRaises(p.PreviewError):
                p.verify_dmg(dmg, SHA, VERSION, '2')
        self.assertTrue(any(event[:2] == ('hdiutil', 'detach') for event in events))

    def test_build_is_isolated_immutable_and_manifest_follows_verification(self):
        for failed in (True, False):
            with self.subTest(failed=failed), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                resources = root / 'Resources'
                resources.mkdir()
                (resources / 'Info.plist').write_bytes(plistlib.dumps({}))
                (resources / 'DockWindow.entitlements').write_bytes(plistlib.dumps(p.ENTITLEMENTS))
                (resources / 'AppIcon.icns').write_bytes(b'fixture icon')
                out = root / 'dist' / f'DogBar-{VERSION}-arm64'
                events = []
                def run(*args):
                    events.append(tuple(map(str, args)))
                    if args[0] == 'security':
                        return f'{SHA} "DockWindow Dev" (CSSMERR_TP_NOT_TRUSTED)'
                    if args[0] == 'swift':
                        binary = out / 'build/bin'
                        binary.mkdir(parents=True, exist_ok=True)
                        (binary / 'DockWindow').write_bytes(b'fixture binary')
                        return str(binary) if '--show-bin-path' in args else ''
                    if args[:2] == ('hdiutil', 'create'):
                        Path(args[-1]).write_bytes(b'fixture dmg')
                    return ''
                args = argparse.Namespace(version=VERSION, build='2', identity=SHA)
                with patch.object(p, 'ROOT', root), patch.object(p, 'prerequisites'), patch.object(p, 'run', side_effect=run), patch.object(p, 'verify_app'), patch.object(p, 'verify_dmg', side_effect=p.PreviewError('corrupt image') if failed else None, return_value='a' * 64):
                    if failed:
                        with self.assertRaises(p.PreviewError):
                            p.build_preview(args)
                        self.assertFalse((out / 'release.json').exists())
                        self.assertFalse((out / 'provenance.json').exists())
                    else:
                        p.build_preview(args)
                        value = json.loads((out / 'release.json').read_text())
                        self.assertEqual(value, p.manifest(VERSION, '2', 'a' * 64))
                        info = plistlib.loads((out / 'image/DogBar.app/Contents/Info.plist').read_bytes())
                        self.assertEqual(info['CFBundleShortVersionString'], '0.1.0')
                        self.assertEqual(info['DogBarPreviewVersion'], VERSION)
                    self.assertTrue(any(event[:2] == ('security', 'find-identity') and '-v' not in event for event in events))
                    self.assertTrue(any('--scratch-path' in event for event in events))
                    self.assertFalse(any('--deep' in event for event in events if event[0] == 'codesign'))
                    self.assertFalse(any('notarytool' in event or 'stapler' in event or 'spctl' in event for event in events))
                    self.assertFalse(any('Applications/DockWindow.app' in ' '.join(event) for event in events))
                    with self.assertRaises(p.PreviewError):
                        p.build_preview(args)

    def test_symlink_output_root_is_rejected_without_commands(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'elsewhere').mkdir()
            (root / 'dist').symlink_to(root / 'elsewhere', target_is_directory=True)
            with patch.object(p, 'ROOT', root), patch.object(p, 'run') as run, self.assertRaises(p.PreviewError):
                p.build_preview(argparse.Namespace(version=VERSION, build='2', identity=SHA))
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
