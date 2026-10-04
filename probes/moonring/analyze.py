"""Footprints and errors from one moonring_probe.gd run.
    python analyze.py <probe out dir> [<reference dir>]

For each view and setting:
- footprint: pixels where the style's capture differs from the rings-hidden capture by more than
  16 (0-255, max of RGB), so what a reader actually sees of the ring or the grommet;
- error: mean difference from the reference capture of the same style, over the reference's
  footprint. The reference is the supersampled `ssaa2x_ref` row (scale 2.0 + MSAA 4x), from this
  run or from <reference dir> (a stock run, to score the fork's DLSS rows against stock).
GPU time and primitives come from moonring.json. Writes summary.json and crops-close.png
(the same arc of the demerzel grommet in every setting, x3) next to the captures."""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

THRESHOLD = 16
CROP = (1160, 170, 1400, 410)  # an arc of the demerzel grommet in the 1920x1080 close view

out = Path(sys.argv[1])
ref_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else out
probe = json.loads((out / 'moonring.json').read_text())


def load(d, view, setting, style):
    return np.asarray(Image.open(d / f'{view}-{setting}-{style}.png').convert('RGB')).astype(np.int16)


def diff(a, b):
    return np.abs(a - b).max(axis=2)


summary = {'godot': probe['godot'], 'renderer': probe['renderer'], 'size': probe['size'], 'views': {}}
for view, rows in probe['views'].items():
    ref = {s: load(ref_dir, view, 'ssaa2x_ref', s) for s in ('none', 'ring', 'grommet')}
    view_out = {}
    for setting, row in rows.items():
        none = load(out, view, setting, 'none')
        cells = {}
        for style in ('ring', 'grommet'):
            img = load(out, view, setting, style)
            mask = diff(ref[style], ref['none']) > THRESHOLD
            cells[style] = {
                'footprint_px': int((diff(img, none) > THRESHOLD).sum()),
                'error_vs_ref': round(float(diff(img, ref[style])[mask].mean()), 2) if mask.any() else None,
                'gpu_ms': row[style]['gpu_ms'][0],
                'primitives': row[style]['primitives'],
            }
        cells['none_gpu_ms'] = row['none']['gpu_ms'][0]
        if 'dlss_evaluations' in row:
            cells['dlss_evaluations'] = row['dlss_evaluations']
        view_out[setting] = cells
    summary['views'][view] = view_out
(out / 'summary.json').write_text(json.dumps(summary, indent=1))

print(f"{probe['godot']}  {probe['renderer']}  {probe['size'][0]:.0f}x{probe['size'][1]:.0f}  reference: {ref_dir.name}")
print('view      setting           ring px  grommet px  ring err  grommet err  gpu ms none/ring/grommet  dlss evals')
for view, rows in summary['views'].items():
    for setting, c in rows.items():
        print(f"{view:<9} {setting:<17} {c['ring']['footprint_px']:>7}  {c['grommet']['footprint_px']:>10}  "
              f"{c['ring']['error_vs_ref'] or 0:>8.2f}  {c['grommet']['error_vs_ref'] or 0:>11.2f}  "
              f"{c['none_gpu_ms']:.3f}/{c['ring']['gpu_ms']:.3f}/{c['grommet']['gpu_ms']:.3f}       "
              f"{c.get('dlss_evaluations', '-')}")

if 'close' in probe['views']:
    w = probe['size'][0] / 1920.0
    box = tuple(int(v * w) for v in CROP)
    tiles = []
    for setting in probe['views']['close']:
        tile = Image.open(out / f'close-{setting}-grommet.png').convert('RGB').crop(box)
        tiles.append(tile.resize((tile.width * 3, tile.height * 3), Image.NEAREST))
    sheet = Image.new('RGB', (sum(t.width for t in tiles), tiles[0].height))
    x = 0
    for t in tiles:
        sheet.paste(t, (x, 0))
        x += t.width
    sheet.save(out / 'crops-close.png')
    print('crops-close.png:', ', '.join(probe['views']['close']))
