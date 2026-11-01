#!/usr/bin/env python3
"""Cut the onboarding mascot poses into animation layers.

Reads Resources/Onboarding/Mascot/{welcome,guide,permissions,celebrate}.png (1254 px square,
same camera) and writes Resources/Onboarding/Rig/*.png on one shared canvas, so every layer
lines up when drawn at the same frame. MascotRig in Sources/DogBarCore/Features/Onboarding
uses the same coordinates (pivots, eyes, paw tip) in this canvas, divided by 1254.

Layers:
  {frame}-body   the pose without its tail (and without the raised arm for wave/think)
  {frame}-tail   the tail alone, drawn behind the body, wagged around TAIL_PIVOT
  arm            welcome's raised forearm and paw, rotated around ARM_PIVOT (wave, scratch)
  celebrate-paws both raised paws, drawn in front of an edge the dog peeks over

Frames: wave (welcome), think (welcome body and paw with the permissions head: curious,
one paw up to scratch), guide, celebrate. Requires Pillow. Deterministic; rerun after art changes.
"""
from pathlib import Path
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'Resources/Onboarding/Mascot'
OUT = ROOT / 'Resources/Onboarding/Rig'
CANVAS = 1254
SIZE = 768  # 2x of the largest on-screen mascot (about 300 pt) with headroom

TAIL = [(60, 660), (330, 660), (400, 770), (405, 875), (378, 925), (376, 1020), (355, 1040), (340, 1140), (60, 1140)]
ARM = [(282, 468), (420, 460), (486, 500), (492, 650), (516, 790), (380, 812), (348, 700), (286, 624)]
HEAD = [(150, 0), (1150, 0), (1150, 700), (980, 690), (860, 620), (720, 590), (560, 600), (470, 610), (300, 600), (150, 560)]
PAWS = [[(245, 425), (380, 410), (455, 440), (470, 560), (470, 700), (440, 760), (330, 760), (310, 640), (250, 600)],
        [(865, 465), (1000, 455), (1080, 500), (1080, 640), (1000, 700), (1000, 790), (850, 800), (840, 680), (862, 600)]]


def mask(polygons, blur=0):
    layer = Image.new('L', (CANVAS, CANVAS), 0)
    draw = ImageDraw.Draw(layer)
    for polygon in polygons:
        draw.polygon(polygon, fill=255)
    return layer.filter(ImageFilter.GaussianBlur(blur)) if blur else layer


def keep(image, area):
    """The image's pixels inside `area` only."""
    result = image.copy()
    result.putalpha(ImageChops.multiply(image.getchannel('A'), area))
    return result


def without(image, area):
    return keep(image, ImageChops.invert(area))


def save(image, name):
    # Resample premultiplied so transparent edges keep their colour.
    small = image.convert('RGBa').resize((SIZE, SIZE), Image.LANCZOS).convert('RGBA')
    small.save(OUT / f'{name}.png', optimize=True)


def main():
    poses = {name: Image.open(SOURCE / f'{name}.png').convert('RGBA') for name in ('welcome', 'guide', 'permissions', 'celebrate')}
    if any(image.size != (CANVAS, CANVAS) for image in poses.values()):
        sys.exit('Mascot poses must be 1254 px squares on the shared canvas')
    OUT.mkdir(parents=True, exist_ok=True)
    tail, arm, head = mask([TAIL]), mask([ARM], 2), mask([HEAD], 14)
    welcome, permissions = poses['welcome'], poses['permissions']

    # Under the raised arm, fill with the permissions pose (ear and chest), so the arm can move.
    wave = welcome.copy()
    wave.paste(permissions, (0, 0), arm)
    save(without(without(wave, arm), tail), 'wave-body')
    # Curious: permissions head on the welcome body, which has one front leg down.
    think = welcome.copy()
    think.paste(permissions, (0, 0), ImageChops.lighter(head, arm))
    save(without(without(think, arm), tail), 'think-body')
    save(keep(welcome, arm), 'arm')
    save(keep(welcome, tail), 'welcome-tail')
    for name in ('guide', 'celebrate'):
        save(without(poses[name], tail), f'{name}-body')
        save(keep(poses[name], tail), f'{name}-tail')
    save(keep(poses['celebrate'], mask(PAWS, 1.5)), 'celebrate-paws')
    print(f'Wrote rig layers to {OUT}')


if __name__ == '__main__':
    main()
