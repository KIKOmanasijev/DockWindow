from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'Scripts'))
import onboarding_resources as o  # noqa: E402


class OnboardingResourceTests(unittest.TestCase):
    def test_repository_art_is_complete_and_copied_before_signing(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp) / 'DogBar.app'
            (app / 'Contents/Resources').mkdir(parents=True)
            o.copy(app)
            o.verify(app)
            self.assertFalse((app / 'Contents/Resources/Onboarding/Mascot/README.md').exists())
            with self.assertRaises(o.OnboardingResourceError):
                o.copy(app)

    def test_missing_extra_or_mislabelled_files_are_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp) / 'DogBar.app'
            (app / 'Contents/Resources').mkdir(parents=True)
            o.copy(app)
            root = app / 'Contents/Resources/Onboarding'
            (root / 'Mascot/guide.png').write_bytes(b'not a png')
            with self.assertRaises(o.OnboardingResourceError):
                o.verify(app)
            (root / 'Mascot/guide.png').unlink()
            with self.assertRaises(o.OnboardingResourceError):
                o.verify(app)


if __name__ == '__main__':
    unittest.main()
