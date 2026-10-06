# Moon ring → rope grommet: tracer bullet receipt

**Date:** 2026-10-04. **Request:** "Recommend one smallest measurable craft-derived visual asset integration (sculpture, metalwork, textile, knot or origami), with exact files, baseline, and forked DLSS comparison method", then "oui go" to implement it: IXQL `RENDER GROMMET`, forwarded by GA's ForceRadiant to this scene, and a native DLSS comparison.

## What changed

- `scripts/grommet_mesh.gd` builds a rope grommet. A grommet is one strand laid around itself p times; its centreline is the (p, q) torus knot. The scene uses p = 3, q = 41: a lay angle of about 24°, 10,496 triangles per ring, one shared mesh. `check()` refuses a grommet that cannot be laid:
  - gcd(p, q) ≠ 1, because the curve would close as several loops;
  - strands that would cut through each other, because the centreline gap 2a·sin(π/p)·cos(lay) is not larger than the strand diameter.
- `scripts/prime_radiant.gd`:
  - `moon_ring_style` (`"ring"` by default, unchanged) and `set_moon_ring_style()`.
  - A `governance:render` message `{target, action: on|off|toggle}`, acknowledged by `godot:render-applied {target, action, applied, style, rings}`.
  - The grommet keeps the ring's node transform and core radius (1.515). The ring is unshaded at alpha 0.2 with no depth test; the grommet is lit, opaque, and coloured like its planet.
- `tests/grommet_test.gd`: craft rules, mesh counts, winding and radial extent, plus the bridge message on the real scene. A mutant with one triangle per quad flipped fails with "5248 triangles wound counter-clockwise from outside".

## Method

`moonring_probe.gd` seeds the scene (7), pauses the tree before the first frame, and places every orbit from its seeded start angle, so all captures share one frozen layout. For each view and anti-aliasing setting it renders three styles: rings hidden, ring, grommet. `analyze.py` then computes two numbers:

- **footprint**: pixels that differ from the rings-hidden capture by more than 16 (0-255, max of RGB). It is visible coverage, not geometric coverage: the thin ring is drawn at alpha 0.2, so its faint anti-aliased edges fall under the threshold, while the opaque grommet counts in full;
- **error**: the mean difference from the reference over the reference's footprint. The reference is `ssaa2x_ref` (scale 2.0 bilinear + MSAA 4x), from the stock run. Each style has its own mask and contrast, so compare errors across settings within one style, never ring against grommet.

Views:

- `overview`: the scene's own orbit camera at t = 0;
- `close`: 3.9 units from the demerzel planet.

All runs used an RTX 5080 at 1920x1080 with vsync off.

```powershell
godot --headless --path . --script res://tests/grommet_test.gd
godot --path . --rendering-method forward_plus --rendering-driver vulkan --resolution 1920x1080 `
  --script res://probes/moonring/moonring_probe.gd -- --out=<dir> [--no-glow] [--dlss]
python probes/moonring/analyze.py <dir> [<stock dir as reference>]
```

The fork runs used a copy of the project without `.godot/`, so its 4.6.3 editor never rewrote this checkout's import cache.

## Results

Glow is off in the tables below. Glow's blur is counted in internal pixels, so it widens under DLSS and narrows in the 2x reference. With glow on, the stock close MSAA 2x grommet footprint is 182,253 px and the reference's is 154,798 px. That gap is halo, not geometry.

**Close view (stock 4.6.1 rows, then the fork's DLSS rows):**

| setting | ring px | grommet px | ring err | grommet err | GPU ms none / ring / grommet | DLSS evaluations |
|---|---:|---:|---:|---:|---|---:|
| MSAA 2x (project) | 25,909 | 123,286 | 2.65 | 2.15 | 0.130 / 0.132 / 0.153 | – |
| no AA | 24,274 | 121,606 | 4.38 | 3.03 | 0.087 / 0.093 / 0.109 | – |
| SSAA 2x reference | 26,675 | 125,734 | 0 | 0 | 0.598 / 0.629 / 0.687 | – |
| DLAA (fork) | 25,814 | 125,261 | 1.95 | 2.50 | 0.669 / 0.670 / 0.687 | 7,568 |
| DLSS Quality 0.667 (fork) | 26,169 | 126,976 | 3.29 | 3.78 | 0.637 / 0.637 / 0.646 | 7,081 |
| DLSS Performance 0.5 (fork) | 25,790 | 125,020 | 3.03 | 4.40 | 0.634 / 0.635 / 0.640 | 7,033 |

`images/ring-vs-grommet-close.png` shows the close view, ring then grommet (stock, glow on, MSAA 2x, half size). `images/dlss-crops-close.png` shows the same arc of the grommet in every setting of the fork's glow-off run, in this order: DLAA, DLSS Performance, DLSS Quality, MSAA 2x, no AA, reference.

**Overview (orbit camera), MSAA 2x:**

- The ring covers 963 px, the grommet 2,146 px: 2.2 times more visible coverage.
- Under DLAA they cover 904 and 2,263 px.

**Findings:**

- **The grommet costs little.** With glow off, it adds 0.006-0.023 ms of GPU time over the rings-hidden frame in every row, except the 2x supersampled reference (+0.089 ms). With glow on, it adds up to 0.026 ms. With three grommets in the close view, the frame draws 31,488 more primitives, against 2,304 more for three rings.
- **The fork measures the same layout.** Its MSAA 2x, no-AA and reference rows reproduce stock's footprints exactly (Godot 4.6.1 and fork 4.6.3, e1157bf), so the comparison is like-for-like.
- **DLSS ran.** Evaluations rose by 7,000 to 8,000 per row.
- **DLSS has a fixed cost here.** It adds about 0.5 ms (0.13 → 0.64-0.67 ms).
- **DLSS does not beat MSAA 2x on the grommet.** Close-view error is 2.15 under MSAA 2x against 2.50 under DLAA, 3.78 under Quality and 4.40 under Performance.
- **Compatibility, as on the web (stock, glow on), close view, MSAA 2x:**
  - footprints: ring 25,444 px, grommet 140,325 px;
  - errors: 2.32 and 3.66.

  The geometry is the same; colours are more saturated, as Compatibility has no sRGB conversion.
- **One outlier did not reproduce.** In the first fork run with glow, the overview reference rows took about 98 ms per frame (21 frames) with rings hidden or shown. Two reruns gave 0.69 ms.

**Web, end to end (stock 4.6.1 Web export, Compatibility, single-threaded):**

- Setup: GA's dev server, `/test/prime-radiant`, the Godot panel's Viewer tab.
- `ixql:exec "RENDER GROMMET ON"` logged `[Godot] RENDER grommet on: applied=true style=grommet rings=6`.
- `RENDER GROMMET OFF` logged `style=ring`.
- `RENDER KNOT TOGGLE` is a parse error: nothing reaches Godot.
- In the docked panel (360x151 CSS px) no ring is readable.
- In fullscreen the grommets read as coloured circles, but at the orbit distance of 40 a strand is 1-2 px, so the lay does not show.

## To verify

- **Motion.** DLSS is temporal, and every frame here is static. Rerun with the orbit running and a fixed camera path before drawing a conclusion about DLSS.
- **A way to see the rope.** The scene has no close-up camera: `governance:select` only turns the camera. The three strands read only from about 4 units away.
- **Meaning.** The faint ring said "this planet has moons". An opaque, lit rope is louder. Whether it should stay a toggle or become the default is a design decision, not a measurement.
- **Phones and the published web build.** Nothing was published.
- **Existing code, left alone.**
  - `_setup_camera` calls `look_at` before `add_child`, which logs "Node not inside tree" on every start.
  - `_add_moon_ring` says "flat horizontal ring", but `TorusMesh` already lies in XZ, so `rotation.x = PI/2` stands the ring up. The grommet keeps that transform.
- **Relation to `codex/craft-dsl-lab`.** That plain-weave prototype (uncommitted, separate worktree) checks a craft program before rendering. `GrommetMesh.check()` plays the same role for the knot domain: strand continuity and no interpenetration. The two share no schema yet.
