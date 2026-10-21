# branch2 — refined lines

This branch adds a refined screen-space line algorithm to the frozen `branch1` result. Run `uv run python npr_demo.py` for the combined effect. `main.py`, the HW2 framework and original homework scenes remain unchanged by this optimization.

What changes:

- Linear camera depth and unit camera-space normals replace world-Z data in refined mode.
- Separate silhouette, occlusion and crease responses allow a consistent outer stroke with finer internal lines.
- Tangent-plane residuals reject depth changes caused by a continuous sloping surface. Occlusion ink is placed on the nearer surface to reduce double edges.
- Soft nonmaximum suppression operates on the unsaturated normal response. Tangential support attenuates isolated specks.
- Silhouette width uses distance in screen pixels; the crease width is independent. Existing SSAA is retained.

The existing `--line-mode original` option reproduces branch1's line algorithm and geometry inputs. It is useful for a controlled comparison; its teapot output was checked to match the branch1 PNG exactly. Standalone toon output was also checked to remain identical.

```bash
uv run python npr_demo.py --style lines
uv run python npr_demo.py --line-mode original
uv run python npr_demo.py scenes/npr/dragon.json --hatch-strength 0.28 --line-opacity 0.9
```

Controls added: `--crease-threshold` (0.055), `--crease-strength` (0.8), `--crease-width` (0.65), and `--line-mode`. Existing `--normal-threshold`/`--depth-threshold` control original mode only. `--line-width` controls the outer silhouette in refined mode.

This remains a rasterized screen-space method, not a reproduction of the paper's path-space renderer. It does not add curvature-aligned hatching or temporal reprojection. Small details can still flicker while moving. The point of this branch is to evaluate this improvement without altering branch1.

Validation: compiled and rendered actual Slang on software Vulkan, including teapot/dragon line-only and combined images, unchanged original-mode regression, unchanged cel output, and a 48-frame teapot rotation. macOS Metal and the GUI still require a local run.
