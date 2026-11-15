"""Offline opaque-triangle and selected-sun fixture oracle, not a renderer.

Geometry inputs are explicitly rounded to binary32; ideal plane/barycentric
math then uses exact rational arithmetic, converting outputs to float64.
Only small, well-conditioned, interior fixture
cases are supported. This is not a model of Vulkan edge rules, GPU precision,
Godot's BRDF/quantization, scene lifetime, or native performance. No I/O.
"""

from dataclasses import dataclass
from fractions import Fraction
import math
import struct


IDENTITY = ((1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0))


class AmbiguousFixture(ValueError):
    """Case cannot supply an unambiguous portable GPU correctness oracle."""


def _number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("finite real number required")
    try:
        result = float(value)
    except OverflowError as error:
        raise ValueError("finite real number required") from error
    if not math.isfinite(result):
        raise ValueError("finite real number required")
    return result


def binary32(value):
    """Return the exact host value of a finite IEEE binary32 input."""
    try:
        result = struct.unpack('<f', struct.pack('<f', _number(value)))[0]
    except (OverflowError, struct.error) as error:
        raise ValueError("input is outside finite binary32") from error
    if not math.isfinite(result):
        raise ValueError("input is outside finite binary32")
    return result


def _vector(value, convert=binary32, size=3):
    if not isinstance(value, (list, tuple)) or len(value) != size:
        raise ValueError(f"expected {size} components")
    return tuple(convert(component) for component in value)


def _uint(value, bits):
    if type(value) is not int or not 0 <= value < (1 << bits):
        raise ValueError(f"unsigned {bits}-bit integer required")
    return value


def _sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def _dot(a, b):
    return _number(sum(x * y for x, y in zip(a, b)))


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def _exact_vector(value):
    return tuple(Fraction(component) for component in value)


def _exact_dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def _point(matrix, vertex):
    vertex = _exact_vector(vertex)
    return tuple(_exact_dot(_exact_vector(row[:3]), vertex) + Fraction(row[3])
                 for row in matrix)


@dataclass(frozen=True)
class Ray:
    origin: tuple
    direction: tuple
    t_min: float
    t_max: float
    cull_mask: int = 255

    def __post_init__(self):
        object.__setattr__(self, 'origin', _vector(self.origin))
        object.__setattr__(self, 'direction', _vector(self.direction))
        object.__setattr__(self, 't_min', binary32(self.t_min))
        object.__setattr__(self, 't_max', binary32(self.t_max))
        _uint(self.cull_mask, 8)
        if _dot(self.direction, self.direction) == 0:
            raise ValueError("nonzero binary32 direction required")
        if not 0 <= self.t_min < self.t_max:
            raise ValueError("strict finite nonnegative fixture interval required")


@dataclass(frozen=True)
class Instance:
    instance_custom_index: int
    triangles: tuple
    transform_rows: tuple = IDENTITY
    mask: int = 255

    def __post_init__(self):
        _uint(self.instance_custom_index, 24)
        _uint(self.mask, 8)
        if not isinstance(self.transform_rows, (list, tuple)) or len(self.transform_rows) != 3:
            raise ValueError("three mathematical affine rows required")
        rows = tuple(_vector(row, size=4) for row in self.transform_rows)
        linear = tuple(_exact_vector(row[:3]) for row in rows)
        if _exact_dot(linear[0], _cross(linear[1], linear[2])) == 0:
            raise ValueError("singular binary32 transform is outside fixture domain")
        object.__setattr__(self, 'transform_rows', rows)
        if not isinstance(self.triangles, (list, tuple)) or not self.triangles:
            raise ValueError("one or more opaque triangles required")
        triangles = []
        for source in self.triangles:
            if not isinstance(source, (list, tuple)) or len(source) != 3:
                raise ValueError("triangle requires three vertices")
            triangle = tuple(_vector(vertex) for vertex in source)
            a, b, c = (_point(rows, vertex) for vertex in triangle)
            normal = _cross(_sub(b, a), _sub(c, a))
            if _exact_dot(normal, normal) == 0:
                raise ValueError("degenerate transformed fixture triangle")
            triangles.append(triangle)
        object.__setattr__(self, 'triangles', tuple(triangles))


@dataclass(frozen=True)
class Hit:
    t: float
    distance_m: float
    instance_custom_index: int
    primitive_index: int
    barycentric: tuple


def _triangle_hit(ray, a, b, c):
    """Exact plane/barycentric geometry over the binary32-rounded inputs."""
    origin, direction = _exact_vector(ray.origin), _exact_vector(ray.direction)
    ab, ac = _sub(b, a), _sub(c, a)
    normal = _cross(ab, ac)
    divisor = _exact_dot(normal, direction)
    offset = _exact_dot(normal, _sub(a, origin))
    if divisor == 0:
        if offset == 0:
            raise AmbiguousFixture("coplanar ray is outside fixture domain")
        return None
    t = offset / divisor
    if t < ray.t_min or t > ray.t_max:
        return None
    point = tuple(o + t * d for o, d in zip(origin, direction))
    ap = _sub(point, a)
    aa, ab_ac, cc = _exact_dot(ab, ab), _exact_dot(ab, ac), _exact_dot(ac, ac)
    pa, pc = _exact_dot(ap, ab), _exact_dot(ap, ac)
    denominator = aa * cc - ab_ac * ab_ac
    if denominator <= 0:
        raise ValueError("ill-conditioned triangle is outside fixture domain")
    v = (cc * pa - ab_ac * pc) / denominator
    w = (aa * pc - ab_ac * pa) / denominator
    weights = (1 - v - w, v, w)
    if min(weights) < 0:
        return None
    if min(weights) == 0 or t in (ray.t_min, ray.t_max):
        raise AmbiguousFixture("edge, vertex or interval endpoint is not a strict oracle")
    return t, weights


def trace_closest(instances, ray):
    """Return closest interior hit or None; no direction normalization or culling.

    All geometry is opaque and two-sided. Custom IDs are unique in this fixture
    contract. Native closest-hit checks must finish traversal without a
    terminate-on-first-hit flag. An any-hit shadow check may assert only hit/miss.
    """
    if not isinstance(ray, Ray):
        raise ValueError("Ray required")
    instances = tuple(instances)
    if any(not isinstance(instance, Instance) for instance in instances):
        raise ValueError("Instance required")
    ids = [instance.instance_custom_index for instance in instances]
    if len(set(ids)) != len(ids):
        raise ValueError("fixture custom indices must be unique")
    candidates = []
    for instance in instances:
        if not (ray.cull_mask & instance.mask):
            continue
        for primitive_index, triangle in enumerate(instance.triangles):
            vertices = tuple(_point(instance.transform_rows, vertex) for vertex in triangle)
            result = _triangle_hit(ray, *vertices)
            if result is not None:
                t, weights = result
                distance = _number(float(t) * math.sqrt(_dot(ray.direction, ray.direction)))
                hit = Hit(float(t), distance, instance.instance_custom_index,
                          primitive_index, tuple(float(weight) for weight in weights))
                candidates.append((t, hit))
    candidates.sort(key=lambda candidate: candidate[0])
    if len(candidates) > 1 and candidates[0][0] == candidates[1][0]:
        raise AmbiguousFixture("equal nearest hits have no unique identity oracle")
    return candidates[0][1] if candidates else None


def _factor(value):
    value = _number(value)
    if not 0 <= value <= 1:
        raise ValueError("factor must be between zero and one")
    return value


def _color(value):
    result = _vector(value, convert=_number)
    if min(result) < 0:
        raise ValueError("fixture radiance must be nonnegative")
    return result


@dataclass(frozen=True)
class LightResult:
    effective_visibility: float
    ambient: tuple
    emission: tuple
    other_lights: tuple
    sun_diffuse: tuple
    sun_specular: tuple
    total: tuple


def shade_selected_sun(*, ambient, emission, other_lights, sun_diffuse,
                       sun_specular, raw_visibility, opacity, fade_to_lit,
                       cloud_transmission):
    """Ideal linear fixture energy, not a bit-exact Godot pixel expectation.

    other_lights already includes its existing cloud/visibility policy. Sun
    inputs are unshadowed direct components; no raster visibility is multiplied.
    fade_to_lit is a pre-evaluated blend weight, never a physical distance.
    HDR values above one are allowed. No BRDF, exposure or quantization is modeled.
    """
    ambient, emission, other_lights = map(_color, (ambient, emission, other_lights))
    diffuse, specular = map(_color, (sun_diffuse, sun_specular))
    raw_visibility, opacity, fade_to_lit, cloud_transmission = map(
        _factor, (raw_visibility, opacity, fade_to_lit, cloud_transmission))
    effective = 1 - opacity * (1 - raw_visibility) * (1 - fade_to_lit)
    factor = effective * cloud_transmission
    diffuse = tuple(value * factor for value in diffuse)
    specular = tuple(value * factor for value in specular)
    total = tuple(_number(sum(channel)) for channel in zip(
        ambient, emission, other_lights, diffuse, specular))
    return LightResult(effective, ambient, emission, other_lights, diffuse, specular, total)
