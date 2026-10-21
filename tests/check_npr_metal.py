"""Opt-in hardware regression: uv run python tests/check_npr_metal.py.

Requires an actual Metal device. Saves images for visual inspection in
outputs/mac-regression; deliberately fails instead of falling back to Vulkan.
"""
import argparse
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
os.chdir(ROOT)

import numpy as np
import slangpy as spy
from scipy.ndimage import binary_erosion
from hw2 import npr


def main():
    parser = argparse.ArgumentParser()
    npr.add_arguments(parser)
    args = parser.parse_args([])
    renderer = npr.NPRRenderer(args)
    assert renderer.device.info.type == spy.DeviceType.metal, 'This regression must run on Metal'
    destination = Path('outputs/mac-regression')
    frames = []
    for t in (0, 3, 6, 9):
        report = renderer.diagnose(destination / f't{t}', t, 'combined')
        assert report['geometry_pixels'] > 10000, report
        assert report['output_pixels'] > 10000, report
        assert report['color_geometry_coverage_equal'], report
        assert all(report[f'{name}_finite'] for name in ('color', 'geometry', 'output')), report
        frames.append(report)

    for style in npr.STYLES:
        renderer.save(destination / f'{style}.png', 0, style)
        if style == 'toon':
            color = renderer.color.to_numpy()
            covered = np.any(np.abs(renderer.geometry.to_numpy() - [0.5, 0.5, 0, 0]) > 1e-5, axis=-1)
            bands = np.unique(np.round(color[covered, :3], 5), axis=0)
            assert len(bands) == args.color_steps + 1, bands

    combined = renderer.pixels(0, 'combined')
    geometry = renderer.geometry.to_numpy()
    covered = np.any(np.abs(geometry - [0.5, 0.5, 0, 0]) > 1e-5, axis=-1)
    mask = covered.reshape(renderer.height, args.ssaa, renderer.width, args.ssaa).all(axis=(1, 3))
    interior = binary_erosion(mask, iterations=4)
    args.line_opacity = 0
    no_lines = renderer.pixels(0, 'combined')
    line_pixels = np.any(np.abs(combined[..., :3] - no_lines[..., :3]) > 0.02, axis=-1)
    internal_lines = int((line_pixels & interior).sum())
    silhouette_lines = int((line_pixels & ~interior).sum())
    assert internal_lines > 100, internal_lines
    assert silhouette_lines > 100, silhouette_lines
    args.hatch_strength = 0
    no_hatching = renderer.pixels(0, 'combined')
    hatch_pixels = int((np.any(np.abs(no_lines[..., :3] - no_hatching[..., :3]) > 0.02, axis=-1) & interior).sum())
    assert hatch_pixels > 1000, hatch_pixels
    report = dict(frames=frames, cel_bands=len(bands), internal_line_pixels=internal_lines,
                  silhouette_line_pixels=silhouette_lines, hatch_pixels=hatch_pixels)
    (destination / 'validation.json').write_text(json.dumps(report, indent=2))
    print('Metal regression passed:', json.dumps({k: v for k, v in report.items() if k != 'frames'}))


if __name__ == '__main__':
    main()
