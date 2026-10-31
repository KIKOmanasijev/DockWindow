import argparse
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('release', Path(__file__).resolve().parents[2] / 'Scripts/release.py')
r = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(r)
TEAM = 'ABCDE12345'
SHA = 'A' * 40
SUBMISSION = {'id': '12345678-1234-1234-1234-123456789abc', 'status': 'Accepted'}

class ReleaseTests(unittest.TestCase):
    def test_identity_requires_valid_developer_id_and_team(self):
        valid = f'1) {SHA} "Developer ID Application: Example ({TEAM})"'
        self.assertEqual(r.select_identity(valid, TEAM), SHA)
        for text in ('0 valid identities found', valid.replace(TEAM, 'ZZZZZ12345'),
                     valid.replace('Developer ID Application: Example', 'DockWindow Dev'),
                     valid + '\n' + valid.replace(SHA, 'B' * 40)):
            with self.subTest(text=text), self.assertRaises(r.ReleaseError):
                r.select_identity(text, TEAM)
        self.assertEqual(r.select_identity(valid, TEAM, SHA.lower()), SHA)
        with self.assertRaises(r.ReleaseError):
            r.select_identity(valid, TEAM, '-')

    def test_missing_tools_and_platform(self):
        with patch.object(r.platform, 'system', return_value='Linux'), self.assertRaises(r.ReleaseError):
            r.prerequisites()
        with patch.object(r.platform, 'system', return_value='Darwin'), patch.object(r.shutil, 'which', return_value=None), self.assertRaises(r.ReleaseError):
            r.prerequisites()

    def test_preflight_no_fallback_and_profile_required(self):
        with patch.object(r, 'prerequisites'), patch.object(r, 'run', return_value='0 valid identities found') as run:
            with self.assertRaises(r.ReleaseError):
                r.preflight(TEAM, 'dogbar-notary')
            self.assertEqual(run.call_count, 1)
            self.assertEqual(run.call_args.args, ('security', 'find-identity', '-v', '-p', 'codesigning'))
        identity = f'{SHA} "Developer ID Application: Example ({TEAM})"'
        with patch.object(r, 'prerequisites'), patch.object(r, 'run', side_effect=[identity, r.ReleaseError('missing profile')]), self.assertRaises(r.ReleaseError):
            r.preflight(TEAM, 'dogbar-notary')

    def test_only_actual_accepted_with_id(self):
        self.assertEqual(r.accepted_submission(SUBMISSION), SUBMISSION['id'])
        for status in ('Invalid', 'In Progress', 'Rejected', 'accepted', None, True):
            with self.subTest(status=status), self.assertRaises(r.ReleaseError):
                r.accepted_submission(dict(SUBMISSION, status=status))
        for data in ({'status': 'Accepted'}, dict(SUBMISSION, id='bogus'), None):
            with self.assertRaises(r.ReleaseError):
                r.accepted_submission(data)

    def test_notary_invalid_persists_log_then_blocks(self):
        with tempfile.TemporaryDirectory() as temp:
            logs = Path(temp)
            with patch.object(r, 'run', side_effect=[json.dumps(dict(SUBMISSION, status='Invalid')), '']) as run:
                with self.assertRaises(r.ReleaseError):
                    r.notarize(Path('artifact.zip'), 'dogbar-notary', logs, 'app')
                self.assertTrue((logs / 'app-submission.json').is_file())
                self.assertIn('--wait', run.call_args_list[0].args)
                self.assertEqual(run.call_args_list[1].args[2], 'log')

    def test_manifest_contract_and_unsafe_inputs(self):
        self.assertEqual(r.validate_manifest(r.EMPTY.copy()), r.EMPTY)
        good = r.ready_manifest('1.2.3', 'a' * 64)
        self.assertEqual(r.validate_manifest(good), good)
        for v in ('../x', '1.2', '1.2.3/evil', '01.2.3', '1.2.3?x', '-1.2.3', None):
            with self.assertRaises(r.ReleaseError):
                r.ready_manifest(v, 'a' * 64)
        for change in ({'url': 'https://evil.test/a.dmg'}, {'url': '//evil/a'}, {'url': '/downloads/../evil'},
                       {'url': '/downloads/DogBar-0.0.1-arm64.dmg'}, {'sha256': 'a' * 63},
                       {'sha256': 'A' * 64}, {'notarized': False}, {'architecture': 'x86_64'},
                       {'minimumMacOS': '14.0'}, {'available': 1}):
            with self.subTest(change=change), self.assertRaises(r.ReleaseError):
                r.validate_manifest(dict(good, **change))

    def test_hash_and_symlink_gate_before_apple_tools(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(r, 'run') as run:
            dmg = Path(temp) / r.filename('1.2.3')
            dmg.write_bytes(b'tampered')
            with self.assertRaises(r.ReleaseError):
                r.verify_dmg(dmg, TEAM, '1.2.3', '1', 'a' * 64)
            run.assert_not_called()
            dmg.unlink()
            dmg.symlink_to('/no/such/path')
            with self.assertRaises(r.ReleaseError):
                r.verify_dmg(dmg, TEAM, '1.2.3', '1', 'a' * 64)

    def test_signature_requires_apple_anchor_team_timestamp_runtime(self):
        req = r.requirement(TEAM, app=True)
        self.assertIn('anchor apple generic', req)
        self.assertIn('1.2.840.113635.100.6.1.13', req)
        self.assertIn(TEAM, req)
        with patch.object(r, 'run', return_value='') as command, self.assertRaises(r.ReleaseError):
            r.verify_signature(Path('DogBar.app'), TEAM, app=True)
        self.assertIn('-R=' + req, command.call_args_list[0].args)
        for detail in (f'TeamIdentifier={TEAM}\nAuthority=Developer ID Application: Example\n',
                       'TeamIdentifier=OTHER\nTimestamp=now\nAuthority=Developer ID Application: Example\n'):
            with patch.object(r, 'run', side_effect=['', detail]), self.assertRaises(r.ReleaseError):
                r.verify_signature(Path('app'), TEAM)
        with patch.object(r, 'run', return_value='source=Developer ID\n'), self.assertRaises(r.ReleaseError):
            r.ticket_and_gatekeeper(Path('app'), app=True)

    def test_build_sequence_and_isolation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            resources = root / 'Resources'
            resources.mkdir()
            (resources / 'Info.plist').write_bytes(plistlib.dumps({}))
            (resources / 'DogBar.entitlements').write_bytes(plistlib.dumps(r.ENTITLEMENTS))
            (resources / 'AppIcon.icns').write_bytes(b'icon')
            out = root / 'dist/DogBar-1.2.3-arm64'
            events = []
            def run(*args):
                events.append(tuple(map(str, args)))
                if args[0] == 'swift':
                    binary = out / 'build/bin'
                    binary.mkdir(parents=True, exist_ok=True)
                    (binary / 'DogBar').write_bytes(b'mock binary')
                    return str(binary) if '--show-bin-path' in args else ''
                if args[:2] == ('hdiutil', 'create'):
                    Path(args[-1]).write_bytes(b'mock dmg')
                return ''
            def notary(path, profile, logs, label):
                events.append(('notarize', label))
                return SUBMISSION
            args = argparse.Namespace(version='1.2.3', build='1', team_id=TEAM, keychain_profile='dogbar-notary', identity=None)
            with patch.object(r, 'ROOT', root), patch.object(r, 'preflight', return_value=SHA), patch.object(r, 'run', side_effect=run), patch.object(r, 'notarize', side_effect=notary), patch.object(r, 'verify_signature'), patch.object(r, 'verify_app'), patch.object(r, 'verify_dmg', return_value='a' * 64) as verify:
                verify.side_effect = r.ReleaseError('untrusted final image')
                with self.assertRaises(r.ReleaseError):
                    r.build_release(args)
                self.assertFalse((out / 'release.json').exists())
                self.assertFalse((out / 'provenance.json').exists())
                shutil.rmtree(out)  # Only this test's TemporaryDirectory fixture.
                events.clear()
                verify.reset_mock(side_effect=True)
                r.build_release(args)
                verify.assert_called_once()
                app_notary = events.index(('notarize', 'app'))
                dmg_notary = events.index(('notarize', 'dmg'))
                create = next(i for i, e in enumerate(events) if e[:2] == ('hdiutil', 'create'))
                staple_app = next(i for i, e in enumerate(events) if e[:3] == ('xcrun', 'stapler', 'staple') and e[-1].endswith('.app'))
                self.assertLess(app_notary, staple_app)
                self.assertLess(staple_app, create)
                self.assertLess(create, dmg_notary)
                self.assertTrue((out / 'release.json').exists())
                self.assertFalse(any('--deep' in e for e in events if e[0] == 'codesign'))
                self.assertTrue(all('Applications/DogBar.app' not in ' '.join(e) for e in events))
                with self.assertRaises(r.ReleaseError):
                    r.build_release(args)

    def stage_fixture(self, root):
        release = root / 'dist/release'
        release.mkdir(parents=True)
        landing = root / 'landing'
        landing.mkdir()
        (landing / 'release.json').write_text(json.dumps(r.EMPTY))
        dmg = release / r.filename('1.2.3')
        dmg.write_bytes(b'fixture only, no actual signed artifact')
        m = r.ready_manifest('1.2.3', r.digest(dmg))
        (release / 'release.json').write_text(json.dumps(m))
        (release / 'provenance.json').write_text(json.dumps(dict(
            teamID=TEAM, version='1.2.3', build='2', sha256=m['sha256'],
            appSubmission=SUBMISSION, dmgSubmission=SUBMISSION)))
        args = argparse.Namespace(team_id=TEAM, version='1.2.3', build='2', release_dir=release)
        return args, m, landing / 'downloads' / dmg.name

    def test_stage_fails_closed_on_actual_verification(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            args, m, target = self.stage_fixture(root)
            with patch.object(r, 'ROOT', root), patch.object(r, 'prerequisites'), patch.object(r, 'verify_dmg', side_effect=r.ReleaseError('bad Apple ticket')), self.assertRaises(r.ReleaseError):
                r.verify_or_stage(args, stage=True)
            self.assertFalse(target.exists())
            self.assertEqual(json.loads((root / 'landing/release.json').read_text()), r.EMPTY)

    def test_stage_idempotent_only_for_identical_bytes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            args, m, target = self.stage_fixture(root)
            with patch.object(r, 'ROOT', root), patch.object(r, 'prerequisites'), patch.object(r, 'verify_dmg') as verify:
                r.verify_or_stage(args, stage=True)
                r.verify_or_stage(args, stage=True)
                self.assertEqual(verify.call_count, 2)
                self.assertEqual(json.loads((root / 'landing/release.json').read_text()), m)
                target.write_bytes(b'tampered existing immutable file')
                with self.assertRaises(r.ReleaseError):
                    r.verify_or_stage(args, stage=True)
                self.assertEqual(target.read_bytes(), b'tampered existing immutable file')

    def test_stage_rejects_stale_version_and_symlink_downloads(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            args, m, target = self.stage_fixture(root)
            (root / 'landing/release.json').write_text(json.dumps(r.ready_manifest('2.0.0', 'b' * 64)))
            with patch.object(r, 'ROOT', root), patch.object(r, 'prerequisites'), patch.object(r, 'verify_dmg') as verify:
                with self.assertRaises(r.ReleaseError):
                    r.verify_or_stage(args, stage=True)
                verify.assert_not_called()
                target.parent.rmdir()
                target.parent.symlink_to(root / 'elsewhere')
                with self.assertRaises(r.ReleaseError):
                    r.verify_or_stage(args, stage=True)

    def test_provenance_mismatch_or_fake_success_blocks(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            args, m, target = self.stage_fixture(root)
            with self.assertRaises(r.ReleaseError):
                r.load_release(args.release_dir, TEAM, '1.2.3', '3')
            provenance = args.release_dir / 'provenance.json'
            p = json.loads(provenance.read_text())
            p['dmgSubmission']['status'] = 'In Progress'
            provenance.write_text(json.dumps(p))
            with self.assertRaises(r.ReleaseError):
                r.load_release(args.release_dir, TEAM, '1.2.3', '2')

    def test_failed_final_verification_emits_no_manifest(self):
        # Existing version directories and any incomplete build cannot become release proof.
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'dist/DogBar-1.2.3-arm64').mkdir(parents=True)
            args = argparse.Namespace(version='1.2.3', build='1', team_id=TEAM, keychain_profile='dogbar-notary', identity=None)
            with patch.object(r, 'ROOT', root), patch.object(r, 'preflight', return_value=SHA), patch.object(r, 'run') as run, self.assertRaises(r.ReleaseError):
                r.build_release(args)
            run.assert_not_called()
            self.assertFalse((root / 'dist/DogBar-1.2.3-arm64/release.json').exists())

if __name__ == '__main__':
    unittest.main()
