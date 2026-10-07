"""Errors in flight and held, from one motion_probe.gd run.
    python analyze_motion.py <probe out dir>

For each setting, style and captured pose k:
- error: mean difference (0-255, max of RGB) from the held `ssaa2x_ref` capture of the same style
  at pose k, over that reference's footprint (pixels more than 16 away from the rings-hidden
  reference), as in analyze.py;
- fly: the capture taken in flight, after k frames of camera motion; hold: the same pose after
  the probe has held it still. hold - fly is what motion costs the setting.
- same_px: the share of pixels identical between fly and hold. A setting without history (MSAA,
  no AA, the reference) must reach 1.0, which checks that every pose is reproduced exactly.
- trail: which held reference pose, from the first capture k back to k - TRAIL, the in-flight
  grommet image matches best over the whole frame. 0 means the image shows the camera where it
  is; j means it shows the camera j frames ago. The error at that best pose says whether the image
  is a clean late frame (close to the hold error) or a smear of several (well above it).
Writes summary-motion.json and overlay-motion.png (around demerzel's grommet at the first pose:
the reference in red, each setting's in-flight image in cyan, so any trail shows as colour
fringes) next to the captures."""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

THRESHOLD = 16

out = Path(sys.argv[1])
probe = json.loads((out / 'motion.json').read_text())
captures = probe['captures']
k0 = captures[0]


def load(setting, style, phase, k):
    return np.asarray(Image.open(out / f'{setting}-{style}-{phase}-{k}.png').convert('RGB')).astype(np.int16)


def diff(a, b):
    return np.abs(a - b).max(axis=2)


summary = {'godot': probe['godot'], 'renderer': probe['renderer'], 'size': probe['size'],
           'glow': probe['glow'], 'step_deg': probe['step_deg'], 'settings': {}}
refs = {(style, k): load('ssaa2x_ref', style, 'hold', k) for style in ('none', 'ring', 'grommet') for k in captures}
trail_refs = [load('ssaa2x_ref', 'grommet', 'hold', k0 - j) for j in range(probe['trail'] + 1)]
for setting, row in probe['settings'].items():
    cells = {}
    for style in ('ring', 'grommet'):
        fly_err, hold_err, same = [], [], []
        for k in captures:
            ref = refs[(style, k)]
            mask = diff(ref, refs[('none', k)]) > THRESHOLD
            fly = load(setting, style, 'fly', k)
            hold = load(setting, style, 'hold', k)
            fly_err.append(float(diff(fly, ref)[mask].mean()))
            hold_err.append(float(diff(hold, ref)[mask].mean()))
            same.append(float((diff(fly, hold) == 0).mean()))
        cells[style] = {'fly_err': round(float(np.mean(fly_err)), 2), 'hold_err': round(float(np.mean(hold_err)), 2),
                        'same_px': round(min(same), 4), 'gpu_ms': row[style]['gpu_ms']}
    fly = load(setting, 'grommet', 'fly', k0)
    by_pose = [float(diff(fly, r).mean()) for r in trail_refs]
    j = int(np.argmin(by_pose))
    cells['grommet']['trail_frames'] = j
    cells['grommet']['trail_err'] = [round(by_pose[0], 3), round(by_pose[j], 3)]
    if 'dlss_evaluations' in row:
        cells['dlss_evaluations'] = row['dlss_evaluations']
    summary['settings'][setting] = cells
(out / 'summary-motion.json').write_text(json.dumps(summary, indent=1))

print(f"{probe['godot']}  {probe['renderer']}  {probe['size'][0]:.0f}x{probe['size'][1]:.0f}  "
      f"glow {probe['glow']}  {probe['step_deg']} deg/frame, poses {captures}")
print('setting           grommet hold  grommet fly  ring hold  ring fly  same px g/r     trail  frame err at 0 / at trail  gpu ms g  dlss evals')
for setting, c in summary['settings'].items():
    g, r = c['grommet'], c['ring']
    print(f"{setting:<17} {g['hold_err']:>12.2f}  {g['fly_err']:>11.2f}  {r['hold_err']:>9.2f}  {r['fly_err']:>8.2f}  "
          f"{g['same_px']:.4f}/{r['same_px']:.4f}  {g['trail_frames']:>5}  {g['trail_err'][0]:>14.3f} / {g['trail_err'][1]:.3f}  "
          f"{g['gpu_ms']:>8.3f}  {c.get('dlss_evaluations', '-')}")

# Overlay: a 400x300 window down and left of the ring's top-right point, x2, four panels a row.
cx, cy = probe['crop_centres'][str(k0)]
cx, cy = cx - 150, cy + 100


def grey(img):
    return img[cy - 150:cy + 150, cx - 200:cx + 200].mean(axis=2).astype(np.uint8)


ref = grey(refs[('grommet', k0)])
panels = []
for setting in probe['settings']:
    img = grey(load(setting, 'grommet', 'fly', k0))
    p = Image.fromarray(np.stack([ref, img, img], axis=2)).resize((800, 600), Image.NEAREST)
    d = ImageDraw.Draw(p)
    d.rectangle((0, 0, 260, 22), fill=(0, 0, 0))
    d.text((6, 5), f'{setting} in flight (cyan) / reference (red)', fill=(255, 255, 255))
    panels.append(p)
cols = 4
rows = (len(panels) + cols - 1) // cols
sheet = Image.new('RGB', (800 * cols, 600 * rows))
for i, p in enumerate(panels):
    sheet.paste(p, (800 * (i % cols), 600 * (i // cols)))
sheet.save(out / 'overlay-motion.png')
print('overlay-motion.png:', ', '.join(probe['settings']))
