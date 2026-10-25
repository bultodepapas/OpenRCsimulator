"""Voxel inside/outside masks from closed triangle meshes (BVH trees in mm), robust to grazing rays:
parity along three ray families, majority vote. Deterministic for a fixed grid."""
import numpy as np
from mathutils import Vector


def grid(lo, hi, vox):
    lo, hi = np.asarray(lo, float), np.asarray(hi, float)
    shape = np.ceil((hi - lo) / vox).astype(int)
    axes = [lo[k] + (np.arange(shape[k]) + 0.5) * vox for k in range(3)]
    return lo, shape, axes


def _mark(trees, lo, shape, axes, ax, vox):
    m = np.zeros(shape, bool)
    u_ax, v_ax = [k for k in range(3) if k != ax]
    d = [3.1e-4, 2.3e-4, 1.7e-4]
    d[ax] = 1.0
    d = Vector(d).normalized()
    hi_ax = axes[ax][-1] + vox
    for tb, (bl, bh) in trees:
        iu = np.where((axes[u_ax] >= bl[u_ax] - vox) & (axes[u_ax] <= bh[u_ax] + vox))[0]
        iv = np.where((axes[v_ax] >= bl[v_ax] - vox) & (axes[v_ax] <= bh[v_ax] + vox))[0]
        start = min(bl[ax], lo[ax]) - 1.0
        for i in iu:
            for k in iv:
                o = [0.0, 0.0, 0.0]
                o[u_ax], o[v_ax], o[ax] = axes[u_ax][i] + 0.0071, axes[v_ax][k] - 0.0053, start
                p = Vector(o)
                hits = []
                for _ in range(200):
                    h = tb.ray_cast(p, d, hi_ax - p[ax] + 2.0)
                    if h[0] is None:
                        break
                    hits.append(h[0][ax])
                    p = h[0] + d * 1e-5
                for c0, c1 in zip(hits[0::2], hits[1::2]):
                    j0, j1 = np.searchsorted(axes[ax], c0), np.searchsorted(axes[ax], c1)
                    idx = [None, None, None]
                    idx[u_ax], idx[v_ax], idx[ax] = i, k, slice(j0, j1)
                    m[tuple(idx)] = True
    return m


def inside(trees, lo, shape, axes, vox):
    """trees: list of (BVHTree, (bbox_lo, bbox_hi)) in the grid's units; union of their interiors."""
    s = sum(_mark(trees, lo, shape, axes, ax, vox).astype(np.int8) for ax in range(3))
    return s >= 2
