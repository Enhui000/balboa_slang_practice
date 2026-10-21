# Validation record

## Mac / Metal fix — 2026-10-21, branch1

Actual local environment: Apple M5, Metal backend, macOS 27.0.1 (26A434), arm64; Python 3.13.9, uv 0.12.9, SlangPy 0.42.0, NumPy 2.5.3, SciPy 1.18.1, Pillow 12.3.0. Dependencies were not changed. Initial `git status` was clean on branch1. No other branch, homework framework, original scene or `main.py` was changed.

### Confirmed failure and fix

The original diagnostic reproduced `color_pixels=0`, `geometry_pixels=0`, and 19,992 CPU vertices inside clip space. A separate 128×128 fixed-triangle probe produced 5,202 pixels with depth both off and on, and still produced 5,202 after restoring indexed draw, a scalar vertex buffer and a matrix. Adding MRT produced missing regions (for example 3,251 pixels with depth on). Changing float target formats did not fix it. The full NPR path remained blank even with fixed clip positions and constant fragments.

Enabling `MTL_DEBUG_LAYER=1` on the minimal MRT probe produced a decisive native Metal assertion:

```text
RenderPass Descriptor Validation
slice + renderTargetArrayLength is 2, but the texture only has 1 slices.
```

The RHI Metal `cmdBeginRenderPass` implementation sets `renderTargetArrayLength` to `colorAttachmentCount`: [upstream source](https://github.com/shader-slang/slang-rhi/blob/main/src/metal/metal-command.cpp). This incorrectly requests two texture layers for two independent single-layer 2D attachments. The failure occurs in render-pass configuration before a valid MRT draw; the CPU transform and PNG readback are not the cause. The `sm_6_0` and writable vertex-resource warnings also occur in successful draws and remain after the fix.

`hw2/npr.py` now uses two single-attachment passes only on Metal, retaining the same vertex shader, transforms, mesh order, RGBA32F storage, and less-depth test with a fresh depth clear per pass. `hw2/npr_lighting.slang` adds color-only and geometry-only entry points sharing the existing shading code. Other backends retain MRT. This is a project-local workaround for the pinned dependency, not a patch to the installed RHI. Metal now performs two geometry draws per mesh instead of one.

### Actual results

The hardware regression ran with Metal API Validation enabled, at 1024×768 output and 2×2 SSAA. Every row has matching color/geometry coverage and finite color, signed geometry and output values:

| Time (s) | Color pixels | Geometry pixels | Final non-background pixels |
| --- | ---: | ---: | ---: |
| 0 | 448659 | 448659 | 115199 |
| 3 | 392459 | 392459 | 100100 |
| 6 | 447308 | 447308 | 114979 |
| 9 | 389745 | 389745 | 99355 |

All five styles were rendered. The standalone toon pass has four distinct diffuse bands (three positive bands plus zero). Controlled comparisons with lines/hatching disabled found 13,392 interior pixels affected by lines, 9,888 pixels affected by lines outside the eroded interior, and 83,911 interior pixels affected by hatching (linear RGB difference > 0.02). These counts establish actual shader contributions; they are not a claim that all smooth normal variation is a semantic crease.

Exported combined, raw-color, normal and style PNGs were opened and visually inspected: the teapot, cel bands, silhouette, lid/spout structure lines and hatch strokes are visible. The default interactive command was launched successfully; the user confirmed the visible window displays the model. Automated GUI tools could not capture this Python window, so the GUI confirmation is user-observed, not an automated screenshot check.

Local evidence: `outputs/mac-check-before`, `outputs/mac-check-fixed`, `outputs/mac-regression/validation.json`, `outputs/mac-regression.log`, and the PNG/geometry files beside each report. Temporary probe scripts and shader dumps were removed after recording the findings. The retained regression is `tests/check_npr_metal.py`; it requires Metal and fails on a different backend rather than accepting Vulkan as evidence.

```bash
uv run python npr_demo.py --style combined
uv run python npr_demo.py --style combined --diagnose outputs/mac-check
MTL_DEBUG_LAYER=1 uv run python tests/check_npr_metal.py
uv run python -m unittest discover -s tests -v
```

As a control, the unchanged course path `uv run python main.py -output outputs/mac-hw2_7-control.png 2_7 scenes/npr/teapot.json` also rendered a visible teapot on this Metal device (112,164 non-background PNG pixels). It uses one color attachment and the original typed float3 buffers. The five existing HW2 math tests, Python compilation checks and `git diff --check` passed. Other Mac/GPU models, extended runtime/performance testing and the non-Metal MRT path after this change have not been revalidated.

## Earlier software Vulkan validation

Environment: Python 3.13, SlangPy 0.42.0, Mesa 25.2.8 lavapipe software Vulkan. These are actual compiled/executed Slang shaders. No hardware GPU, Metal device, or interactive display was available for this earlier validation; performance numbers are not hardware performance claims.

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
