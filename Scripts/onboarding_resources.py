#!/usr/bin/env python3
"""Copy and verify the art bundled at DogBar.app/Contents/Resources/Onboarding and .../Settings.

The lists match OnboardingAssets.requiredFiles (Sources/DogBarCore/Features/Onboarding) and
SettingsAssets.requiredFiles (Sources/DogBarCore/Features/Settings). Settings scenes also reuse
the onboarding app icons and wallpapers. Run before signing: files added after codesign would
invalidate the signature.
"""
import argparse
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'Resources/Onboarding'
MASCOT = [f'Mascot/{name}.png' for name in ('welcome', 'guide', 'permissions', 'celebrate')]
APPS = [f'Product/apps/{name}.png' for name in ('finder', 'safari', 'slack', 'figma', 'calendar', 'notes', 'mail',
                                                  'chrome', 'tv', 'music', 'photos', 'messages', 'trash')]
WALLPAPERS = [f'Product/wallpapers/{name}.jpg' for name in ('tahoe', 'sequoia-blue', 'sequoia', 'sonoma')]
# Animation layers cut from the poses by Scripts/mascot_rig.py; MascotRig.layers lists the same names.
RIG = [f'Rig/{name}.png' for name in ('wave-body', 'think-body', 'arm', 'welcome-tail', 'guide-body', 'guide-tail',
                                      'celebrate-body', 'celebrate-tail', 'celebrate-paws')]
REQUIRED = MASCOT + RIG + APPS + WALLPAPERS
# Settings' small supporting mascot art. SettingsAssets.requiredFiles lists the same names.
SETTINGS_SOURCE = ROOT / 'Resources/Settings'
SETTINGS_REQUIRED = [f'Mascot/{name}.png' for name in ('guide', 'search')]
SIGNATURES = {'.png': b'\x89PNG\r\n\x1a\n', '.jpg': b'\xff\xd8\xff'}


class OnboardingResourceError(Exception):
    pass


def check(directory, required=None):
    """Every required file exists, is a real file and has the right image signature. No extras."""
    directory = Path(directory)
    required = REQUIRED if required is None else required
    for relative in required:
        path = directory / relative
        if path.is_symlink() or not path.is_file():
            raise OnboardingResourceError(f'Missing {directory.name} resource: {relative}')
        with path.open('rb') as stream:
            if not stream.read(8).startswith(SIGNATURES[path.suffix]):
                raise OnboardingResourceError(f'Not a {path.suffix} image: {relative}')
    present = {str(p.relative_to(directory)) for p in directory.rglob('*') if p.is_file() or p.is_symlink()}
    extra = present - set(required)
    if extra:
        raise OnboardingResourceError(f'Unexpected {directory.name} resources: {", ".join(sorted(extra))}')


def _copy_set(app, name, source, required):
    target = Path(app) / 'Contents/Resources' / name
    if target.exists():
        raise OnboardingResourceError(f'{name} resources already exist in this bundle')
    for relative in required:
        origin = Path(source) / relative
        if origin.is_symlink() or not origin.is_file():
            raise OnboardingResourceError(f'Missing {name} source file: {relative}')
        (target / relative).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(origin, target / relative)
    check(target, required)


def copy(app, source=SOURCE, settings_source=SETTINGS_SOURCE):
    """Copies only the required files (not the art READMEs) into the unsigned bundle, then verifies them."""
    _copy_set(app, 'Onboarding', source, REQUIRED)
    _copy_set(app, 'Settings', settings_source, SETTINGS_REQUIRED)


def verify(app):
    check(Path(app) / 'Contents/Resources/Onboarding')
    check(Path(app) / 'Contents/Resources/Settings', SETTINGS_REQUIRED)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('copy', 'verify'))
    parser.add_argument('--app', required=True, type=Path)
    args = parser.parse_args()
    try:
        (copy if args.command == 'copy' else verify)(args.app)
    except (OnboardingResourceError, OSError) as error:
        print(f'Bundled art: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
