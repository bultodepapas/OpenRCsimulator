"""Compare complete furniture meshes and integrate vertex-albedo differences over their surfaces."""

import argparse
from collections import Counter
import json
from pathlib import Path

import numpy as np


def load_arrays(directory, prefab):
    return {
        name: np.fromfile(directory / f"{prefab}-{name}.bin", dtype="<f4").reshape(-1, 3, channels)
        for name, channels in (("verts", 3), ("norms", 3), ("cols", 4), ("rendercols", 4))
    }


def records(*attributes):
    return [triangle.tobytes() for triangle in np.concatenate(attributes, axis=2)]


def signed_double_area(a, b, c):
    ab, ac = b - a, c - a
    return ab[0] * ac[1] - ab[1] * ac[0]


def intersect_triangles(triangle, clip):
    """Clip a triangle by the three left half-planes of a counterclockwise triangle."""
    polygon = list(triangle)
    for a, b in zip(clip, np.roll(clip, -1, axis=0)):
        result = []
        for current, previous in zip(polygon, polygon[-1:] + polygon[:-1]):
            h = signed_double_area(a, b, previous)
            k = signed_double_area(a, b, current)
            if (h >= 0) != (k >= 0):
                result.append(previous + (current - previous) * (h / (h - k)))
            if k >= 0:
                result.append(current)
        polygon = result
    return polygon


def quad(x0, x1):
    return np.array([[[x0, 1], [x1, 0], [x1, 1]], [[x0, 1], [x0, 0], [x1, 0]]])


def affine(vertices):
    return np.column_stack((vertices, np.ones(3)))


def compare_strip(old_bounds, new_bounds, old_colors, new_colors):
    """Return peak RGB error and its squared integral in local (metres, unit width)."""
    peak, integral = np.zeros(3), np.zeros(3)
    covered = 0.0
    for old_tri, old_rgb in zip(quad(*old_bounds), old_colors[:, :, :3]):
        for new_tri, new_rgb in zip(quad(*new_bounds), new_colors[:, :, :3]):
            difference = np.linalg.solve(affine(old_tri), old_rgb) - np.linalg.solve(affine(new_tri), new_rgb)
            polygon = intersect_triangles(old_tri, new_tri)
            for index in range(1, len(polygon) - 1):
                triangle = [polygon[0], polygon[index], polygon[index + 1]]
                area = abs(signed_double_area(*triangle)) * 0.5
                if area <= 1e-15:
                    continue
                delta = affine(triangle) @ difference
                covered += area
                peak = np.maximum(peak, np.abs(delta).max(axis=0))
                integral += area / 6 * (delta**2 + delta * np.roll(delta, -1, axis=0)).sum(axis=0)
    assert abs(covered - (old_bounds[1] - old_bounds[0])) < 1e-10
    return peak, integral


def surface_area(positions):
    a, b, c = positions.astype(float).transpose(1, 0, 2)
    return float(np.linalg.norm(np.cross(b - a, c - a), axis=1).sum() * 0.5)


def compare(before, after, prefab, boards, segments):
    old, new = (load_arrays(path, prefab) for path in (before, after))
    original = Counter(records(old["verts"], old["norms"], old["cols"]))
    candidate = Counter(records(new["verts"], new["norms"], new["cols"]))
    located = {key: i for i, key in enumerate(records(new["verts"], new["cols"]))}
    peaks = {key: np.zeros(3) for key in ("cols", "rendercols")}
    integral, max_angle, affected_area = np.zeros(3), 0.0, 0.0
    # Each plank has 8 faces between successive rings, 12 cap triangles, then two 42-triangle fasteners.
    per_plank = 16 * (segments + 2) + 12 + 84
    for board in range(boards):
        for face in (0, 2, 4, 6):
            for ring in range(1, segments + 1, 2):
                first = board * per_plank + 2 * (8 * ring + face)
                last = first + 16
                # Godot stores [a,c,b] and [a,d,c]. The outside four corners survive the merge.
                def endpoints(channel):
                    data = old[channel]
                    return np.array([data[first, 0], data[last, 1], data[last, 2],
                                     data[first, 0], data[first + 1, 1], data[last, 1]]).reshape(2, 3, -1)

                positions = endpoints("verts")
                merged = [located[key] for key in records(positions, endpoints("cols"))]
                candidate.subtract(records(new["verts"][merged], new["norms"][merged], new["cols"][merged]))
                width = np.linalg.norm((positions[0, 0] - positions[0, 1])[1:].astype(float))
                start, end = positions[0, [0, 2], 0].astype(float)
                for index in (first, last):
                    pair = slice(index, index + 2)
                    original.subtract(records(old["verts"][pair], old["norms"][pair], old["cols"][pair]))
                    vertices = old["verts"][pair]
                    assert np.all(vertices[0, [0, 2], 1:] == positions[0, 0, 1:])
                    assert np.all(vertices[0, 1, 1:] == positions[1, 1, 1:])
                    x0, x1 = vertices[0, [0, 2], 0].astype(float)
                    affected_area += width * (x1 - x0)
                    for channel in peaks:
                        peak, squared = compare_strip((x0, x1), (start, end), old[channel][pair], new[channel][merged])
                        peaks[channel] = np.maximum(peaks[channel], peak)
                        if channel == "rendercols":
                            integral += squared * width
                    old_normals = old["norms"][pair].reshape(-1, 3).astype(float)
                    new_normals = new["norms"][merged].reshape(-1, 3).astype(float)
                    for normal in old_normals:
                        angles = np.arctan2(np.linalg.norm(np.cross(normal, new_normals), axis=1), new_normals @ normal)
                        max_angle = max(max_angle, float(np.rad2deg(angles).max()))
    assert original == candidate and min(candidate.values()) >= 0
    assert np.all(old["cols"][:, :, 3] == 1) and np.all(new["cols"][:, :, 3] == 1)
    area = surface_area(old["verts"])
    assert abs(area - surface_area(new["verts"])) < 5e-7
    return dict(prefab=prefab, before=len(old["verts"]), after=len(new["verts"]),
                bit_identical_unmodified_triangles=original.total(), total_area_m2=area,
                affected_area_m2=affected_area, affected_area_fraction=affected_area / area,
                max_abs_rgb_255=(255 * peaks["rendercols"]).tolist(),
                preupload_max_abs_rgb_255=(255 * peaks["cols"]).tolist(),
                area_rms_rgb_255_affected=(255 * np.sqrt(integral / affected_area)).tolist(),
                area_rms_rgb_255_whole=(255 * np.sqrt(integral / area)).tolist(),
                max_normal_difference_degrees=max_angle)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    args = parser.parse_args()
    results = [compare(args.before, args.after, *spec) for spec in (("picnic", 9, 16), ("bench", 6, 14))]
    print(json.dumps(results, indent=2))
