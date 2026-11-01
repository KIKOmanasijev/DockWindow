#!/usr/bin/env python3
"""Copy and verify the onboarding art bundled at DogBar.app/Contents/Resources/Onboarding.

The list matches OnboardingAssets.requiredFiles in Sources/DogBarCore/Features/Onboarding.
Run before signing: files added after codesign would invalidate the signature.
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
REQUIRED = MASCOT + APPS + WALLPAPERS
SIGNATURES = {'.png': b'\x89PNG\r\n\x1a\n', '.jpg': b'\xff\xd8\xff'}


class OnboardingResourceError(Exception):
    pass


def check(directory):
    """Every required file exists, is a real file and has the right image signature. No extras."""
    directory = Path(directory)
    for relative in REQUIRED:
        path = directory / relative
        if path.is_symlink() or not path.is_file():
            raise OnboardingResourceError(f'Missing onboarding resource: {relative}')
        with path.open('rb') as stream:
            if not stream.read(8).startswith(SIGNATURES[path.suffix]):
                raise OnboardingResourceError(f'Not a {path.suffix} image: {relative}')
    present = {str(p.relative_to(directory)) for p in directory.rglob('*') if p.is_file() or p.is_symlink()}
    extra = present - set(REQUIRED)
    if extra:
        raise OnboardingResourceError(f'Unexpected onboarding resources: {", ".join(sorted(extra))}')


def copy(app, source=SOURCE):
    """Copies only the required files (not the art README) into the unsigned bundle, then verifies them."""
    app = Path(app)
    target = app / 'Contents/Resources/Onboarding'
    if target.exists():
        raise OnboardingResourceError('Onboarding resources already exist in this bundle')
    for relative in REQUIRED:
        origin = Path(source) / relative
        if origin.is_symlink() or not origin.is_file():
            raise OnboardingResourceError(f'Missing onboarding source file: {relative}')
        (target / relative).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(origin, target / relative)
    check(target)


def verify(app):
    check(Path(app) / 'Contents/Resources/Onboarding')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('copy', 'verify'))
    parser.add_argument('--app', required=True, type=Path)
    args = parser.parse_args()
    try:
        (copy if args.command == 'copy' else verify)(args.app)
    except (OnboardingResourceError, OSError) as error:
        print(f'Onboarding resources: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
