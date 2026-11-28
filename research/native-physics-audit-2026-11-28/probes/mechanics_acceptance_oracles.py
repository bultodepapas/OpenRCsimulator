"""Independent scalar box-path controls. No engine, repository imports, or files."""

import math


def rotation_point(radius, yaw):
    return (radius * math.cos(yaw), radius * math.sin(yaw))


def nlerp_yaw(start, end, fraction):
    w = (1.0 - fraction) * math.cos(start / 2) + fraction * math.cos(end / 2)
    z = (1.0 - fraction) * math.sin(start / 2) + fraction * math.sin(end / 2)
    return 2 * math.atan2(z, w)


def entry(gap, hi):
    lo = 0.0
    assert gap(lo) > 0 > gap(hi)
    for _ in range(60):
        mid = (lo + hi) / 2
        if gap(mid) > 0:
            lo = mid
        else:
            hi = mid
    return hi


def clear_endpoints():
    radius = 0.9
    angle = math.radians(0.75)
    face = radius * math.cos(angle / 2)

    def gap(s):
        return face - radius * math.cos(nlerp_yaw(-angle, angle, s))

    analytic = (1 - math.tan(angle / 4) / math.tan(angle / 2)) / 2
    assert abs(entry(gap, 0.5) - analytic) < 1e-10
    assert gap(0.5) + 40e-6 > 0
    print('clear endpoints', [gap(s) * 1e6 for s in (0, .5, 1)],
          'um; crossings', analytic, 1 - analytic, 'true miss um', (face + 40e-6 - radius) * 1e6)


def synchronized_envelope():
    radius = 0.9
    angle = math.radians(11.9)
    count = math.ceil(angle / math.radians(2))
    end = 1 / count

    def rotated(s):
        return rotation_point(radius, nlerp_yaw(0, angle, s))

    start = rotated(0)
    finish = rotated(end)

    def point(s):
        # Choose linear CG translation so the probe coincides at the piece endpoints.
        return tuple(c - a - s / end * (b - a) for c, a, b in zip(rotated(s), start, finish))

    mid = point(end / 2)
    deviation = math.hypot(*mid)
    direction = tuple(c / deviation for c in mid)
    pad = radius * (1 - math.cos(nlerp_yaw(0, angle, end) / 2)) + 1e-9
    face = (deviation + pad) / 2

    def gap(s):
        return face - sum(a * b for a, b in zip(direction, point(s)))

    # Rotate the scene so this direction is world x. A wide box with left face
    # here escapes the first piece's source endpoint-plus-padding AABB.
    assert gap(0) > 0 and gap(end) > 0 and gap(end / 2) < 0 and pad < face
    print('pieces', count, 'declared pad um', pad * 1e6, 'mid deviation um', deviation * 1e6,
          'n', direction, 'face um', face * 1e6, 'first bracket root fraction', entry(gap, end / 2))


if __name__ == '__main__':
    clear_endpoints()
    synchronized_envelope()
