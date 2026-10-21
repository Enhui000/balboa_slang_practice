# Validation record

Environment: Python 3.13, SlangPy 0.42.0, Mesa 25.2.8 lavapipe software Vulkan. These are actual compiled/executed Slang shaders. No hardware GPU, Metal device, or interactive display was available for validation; performance numbers are not hardware performance claims.

## Completed checks

- HW2.1: single triangle, nonempty image.
- HW2.2: depth_layers_mesh, perspective color/depth rendering.
- HW2.3: three_instances, model/view/projection and independent instances.
- HW2.4: torus_mobius_spin at t=2.5, animated transforms.
- HW2.5 and 2.6: crossing_sheets, compute versus hardware rasterization. Resulting PNGs matched pixel for pixel (mean absolute difference 0).
- HW2.5 and 2.6: dragon_spin at t=4.5, large mesh / animation.
- HW2.6: dragon_translate at t=5, hardware clipping.
- HW2.7: dragon_spin, uv_quad_scene, uv_sphere at t=3 and avocado. All produced nonempty color images with finite data; UV texture cases executed successfully.
- `python -m unittest discover -s tests -v`: five regression tests passed (lookat/inverse, transformation order and inverse-transpose normals, projection, raw-degree animation and endpoint clamps, invalid camera).
- `python -m compileall -q hw2 npr_demo.py tests` and `git diff --check`: passed.
- Official Utah Teapot: 19,992 vertices, 36,672 triangles, source normals length ≈1, UV range [0,1]. All five NPR modes rendered at 1024×768 with 2×2 SSAA.
- A complete 48-frame teapot rotation rendered with finite output; representative front/side/back views were visually inspected for missing surfaces, large black artifacts, and contour occlusion. This does not establish perfect temporal stability at arbitrary speed or resolution.
- Dragon: all five NPR modes rendered; standalone `lines` visibly includes head/body creases in addition to silhouette. A thinner line preset was selected to avoid overwhelming detailed geometry.
- `main.py`, project dependencies, original scenes, device/buffer/window utilities are unchanged from the parent commit.

## Reproduce

Use the normal device selection on your own machine:

```bash
uv sync
uv run python -m unittest discover -s tests -v
uv run python main.py -output outputs/hw2_7.png 2_7 scenes/hw2/dragon_spin.json
uv run python npr_demo.py --compare outputs/teapot
uv run python npr_demo.py --turntable outputs/teapot.gif
```

For the detailed model:

```bash
uv run python npr_demo.py scenes/npr/dragon.json --compare outputs/dragon \
  --normal-threshold 0.07 --depth-threshold 0.03 \
  --line-width 0.5 --line-opacity 0.8 --hatch-strength 0.28
```

Software Vulkan was supplied separately to the validation environment using `VK_DRIVER_FILES` and `LD_LIBRARY_PATH`; those machine-specific paths are intentionally not hard-coded into the application or dependency files.

## Limits of the result

The shaders render spatially antialiased screen-space contours/hatching. They do not solve arbitrary temporal flicker, invisible contours, curvature-guided hatching or path-traced line transport. HW2 compute rasterization retains the handout's front-of-camera assumptions; near-plane polygon clipping is delegated to hardware in 2.6/2.7/NPR. See README_NPR.md for port differences and scene-sensitive thresholds.
