#!/usr/bin/env python3
"""Synthetic, standard-library-only decal projection and ownership exercises.

The expected values are closed-form cases, not engine-derived golden images.
This is offline arithmetic, not Godot, GPU, browser, native geometry, actual
resource-lifetime, or performance qualification. See the result limitations.

Run: python3 projection_exercises.py --check
     python3 projection_exercises.py --check --write-results PATH
"""
from __future__ import annotations

import argparse
import base64
import json
import math
from fractions import Fraction
from pathlib import Path
from typing import Callable

EPS = 1e-10
MIB = 1024 * 1024
LIMITATIONS = [
    'Synthetic offline arithmetic only; no Godot, GPU, browser, native geometry, or performance qualification. Small well-conditioned inputs do not determine a production numerical tolerance or near-singular cutoff.',
    'Clipping inside the box and finite bounded UVs do not ensure a usable projection: a nondegenerate triangle parallel to the projection direction has zero UV area. Grazing distortion and connected-surface rejection remain separate gates.',
    'Color oracle uses linear-light RGB with straight inputs, premultiplied source-over, then straight output; it is not an sRGB canvas or tone-mapped pixel oracle.',
    'GPU byte totals are theoretical full square RGBA8 mip payloads only; exclude alignment, metadata, upload staging, retained revisions, other resources, and driver behavior.',
    'Base64 is padded separately for each of 16 assumed-unique encoded files; it excludes JSON, other bundled content, admission limits, and decode peaks.',
    'Job and frozen-handle checks are an abstract ownership model; they do not establish engine threading, GPU completion, memory lifetime, or persistence guarantees.',
]


def need(ok: bool, message: str) -> None:
    if not ok:
        raise AssertionError(message)


def approx(a: float, b: float, tol: float = EPS) -> bool:
    return math.isclose(a, b, rel_tol=tol, abs_tol=tol)


def vec_approx(a, b, tol: float = EPS) -> bool:
    return len(a) == len(b) and all(approx(float(x), float(y), tol) for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1]*b[2] - a[2]*b[1], a[2]*b[0] - a[0]*b[2], a[0]*b[1] - a[1]*b[0])


def norm(v):
    return math.sqrt(dot(v, v))


def unit(v):
    length = norm(v)
    if length == 0 or not math.isfinite(length):
        raise ValueError('normalization requires a finite nonzero vector')
    return tuple(x / length for x in v)


def polygon_vector(poly):
    """Twice the oriented area vector for a planar polygon."""
    total = [0.0, 0.0, 0.0]
    for p, q in zip(poly, poly[1:] + poly[:1]):
        c = cross(p, q)
        for k in range(3):
            total[k] += c[k]
    return tuple(total)


def polygon_area(poly):
    return norm(polygon_vector(poly)) / 2 if len(poly) >= 3 else 0.0


def deduplicate(poly):
    out = []
    for p in poly:
        if not out or norm(sub(p, out[-1])) > EPS:
            out.append(p)
    if len(out) > 1 and norm(sub(out[0], out[-1])) <= EPS:
        out.pop()
    return out


def clip_triangle(vertices):
    """Clip one triangle against -1 <= x,y,z <= 1; discard zero-area contacts.

    This small polygon exercise is not a production geometry implementation.
    The finite inputs here are deliberately small and well conditioned.
    """
    if len(vertices) != 3 or any(len(p) != 3 or not all(math.isfinite(x) for x in p) for p in vertices):
        raise ValueError('expected three finite 3D vertices')
    poly = [tuple(float(x) for x in p) for p in vertices]
    for axis in range(3):
        for sign in (1, -1):
            if not poly:
                return []
            output = []
            prev = poly[-1]
            prev_distance = 1.0 - sign * prev[axis]
            for cur in poly:
                cur_distance = 1.0 - sign * cur[axis]
                if (prev_distance >= 0.0) != (cur_distance >= 0.0):
                    t = prev_distance / (prev_distance - cur_distance)
                    t = max(0.0, min(1.0, t))
                    output.append(tuple(a + t * (b - a) for a, b in zip(prev, cur)))
                if cur_distance >= 0.0:
                    output.append(cur)
                prev, prev_distance = cur, cur_distance
            poly = deduplicate(output)
    return poly if len(poly) >= 3 and polygon_area(poly) > EPS else []


def uv(poly):
    """Map projector XY to UV: U grows with X; V decreases with Y.

    With a 2-by-2 projector, U=x/2+0.5 and V=0.5-y/2, matching
    the architecture reference convention.
    """
    return [((p[0] + 1.0) / 2.0, (1.0 - p[1]) / 2.0) for p in poly]


def uv_area(coords):
    return abs(sum(p[0]*q[1] - p[1]*q[0] for p, q in zip(coords, coords[1:] + coords[:1]))) / 2


def valid_output(poly, source):
    need(bool(poly), 'expected nonempty polygon')
    need(all(math.isfinite(x) and -1-EPS <= x <= 1+EPS for p in poly for x in p), 'nonfinite or outside clipping box')
    need(all(math.isfinite(x) and -EPS <= x <= 1+EPS for pair in uv(poly) for x in pair), 'nonfinite or outside UV bounds')
    initial = cross(sub(source[1], source[0]), sub(source[2], source[0]))
    need(dot(polygon_vector(poly), initial) > 0, 'winding reversed or zero area')


def matvec(m, v):
    return tuple(dot(row, v) for row in m)


def transpose(m):
    return tuple(tuple(m[j][i] for j in range(3)) for i in range(3))


def determinant(m):
    return dot(m[0], cross(m[1], m[2]))


def inverse(m):
    a,b,c = m[0]; d,e,f = m[1]; g,h,i = m[2]
    cof = ((e*i-f*h, f*g-d*i, d*h-e*g),
           (c*h-b*i, a*i-c*g, b*g-a*h),
           (b*f-c*e, c*d-a*f, a*e-b*d))
    det = determinant(m)
    if det == 0:
        raise ValueError('singular basis')
    adj = transpose(cof)
    return tuple(tuple(v / det for v in row) for row in adj)


def srgb_decode(c):
    need(0 <= c <= 1, 'sRGB input outside [0,1]')
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def srgb_encode(c):
    need(0 <= c <= 1, 'linear input outside [0,1]')
    return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def source_over(src, dst):
    """Linear straight RGBA -> premultiplied source-over -> straight RGBA.

    Fractions keep the half-alpha oracle exact; RGB is canonicalized to zero
    when output alpha is zero, where straight RGB has no visible meaning.
    """
    sa, da = src[3], dst[3]
    alpha = sa + da * (1 - sa)
    premult = tuple(src[i] * sa + dst[i] * da * (1 - sa) for i in range(3))
    straight = tuple(x / alpha for x in premult) if alpha else (Fraction(0),) * 3
    return (*straight, alpha)


def rational_list(v):
    return [str(x) for x in v]


def mip_bytes(side):
    need(side > 0 and side & (side - 1) == 0, 'exercise expects a positive power-of-two square')
    levels = []
    while True:
        levels.append(side * side * 4)
        if side == 1:
            return levels
        side //= 2


def run():
    cases = []
    calculations = {}
    def case(name: str, fn: Callable):
        try:
            result = fn()
            cases.append({'name': name, 'passed': True, 'observed': result})
        except Exception as exc:
            cases.append({'name': name, 'passed': False, 'error': f'{type(exc).__name__}: {exc}'})

    def inside():
        tri = [(-.5,-.5,0),(.5,-.5,0),(0,.5,0)]
        poly = clip_triangle(tri); valid_output(poly, tri)
        need(len(poly) == 3 and approx(polygon_area(poly), .5), 'inside triangle area/vertex count')
        return {'vertices': len(poly), 'area': polygon_area(poly)}
    case('clip.inside', inside)

    def crossing(reverse=False):
        # Rectangle 2x1 plus a 0.5-high trapezoid with bases 2 and 1: 11/4.
        tri = [(-2,-.5,0),(2,-.5,0),(0,1.5,0)]
        if reverse: tri.reverse()
        poly = clip_triangle(tri); valid_output(poly, tri)
        need(len(poly) == 6 and approx(polygon_area(poly), 11/4), 'crossing polygon area/vertices')
        coords = uv(poly)
        bounds = (min(x for x,y in coords), min(y for x,y in coords), max(x for x,y in coords), max(y for x,y in coords))
        need(vec_approx(bounds, (0,0,1,.75)), 'unexpected UV bounds')
        return {'vertices': len(poly), 'area': polygon_area(poly), 'uv_bounds': list(bounds), 'winding_preserved': True}
    case('clip.crossing_two_axes', crossing)
    case('clip.crossing_reverse_winding', lambda: crossing(True))

    def on_plane():
        tri = [(-.5,-.5,1),(.5,-.5,1),(0,.5,1)]
        poly=clip_triangle(tri); valid_output(poly,tri)
        need(len(poly)==3 and approx(polygon_area(poly),.5) and all(p[2]==1 for p in poly), 'on-plane geometry')
        return {'area': polygon_area(poly), 'plane': 'z=1'}
    case('clip.triangle_on_plane', on_plane)
    for name, tri in [
        ('point_contact', [(1,0,0),(2,1,0),(2,-1,0)]),
        ('edge_contact', [(1,-.5,0),(2,0,0),(1,.5,0)]),
        ('collinear', [(-.5,0,0),(0,0,0),(.5,0,0)]),
    ]:
        case('clip.degenerate_'+name, lambda tri=tri: empty_clip(tri))
    def bad_vertex():
        try:
            clip_triangle([(0,0,0),(math.nan,0,0),(0,1,0)])
        except ValueError:
            return 'rejected nonfinite vertex'
        raise AssertionError('nonfinite vertex accepted')
    case('clip.nonfinite_rejected', bad_vertex)
    for axis in range(3):
        for sign in (-1, 1):
            label = 'xyz'[axis] + ('_positive' if sign > 0 else '_negative')
            case('clip.outside_'+label, lambda axis=axis, sign=sign: outside_case(axis,sign))
            case('clip.cross_'+label, lambda axis=axis, sign=sign: cross_case(axis,sign))

    def collapsed_uv():
        tri = [(1,-.5,-.5),(1,.5,-.5),(1,0,.5)]
        poly=clip_triangle(tri); valid_output(poly,tri)
        need(approx(polygon_area(poly),.5) and approx(uv_area(uv(poly)),0), 'expected nonzero 3D area and collapsed planar UVs')
        return {'area_3d': polygon_area(poly), 'area_uv': uv_area(uv(poly)), 'implication': 'bounded UVs do not prove a usable projection'}
    case('clip.grazing_zero_uv_area', collapsed_uv)

    root13 = math.sqrt(13)
    matrices = [
        ('rotated', ((0,-1,0),(1,0,0),(0,0,1)), (1/math.sqrt(2),1/math.sqrt(2),0), 1),
        ('rotated_nonuniform', ((0,-3,0),(2,0,0),(0,0,4)), (2/root13,3/root13,0), 24),
        ('rotated_nonuniform_reflected', ((0,-3,0),(-2,0,0),(0,0,4)), (2/root13,-3/root13,0), -24),
    ]
    for name,basis,expected,expected_det in matrices:
        case('normal.'+name, lambda basis=basis, expected=expected, expected_det=expected_det: normal_case(basis,expected,expected_det))
    def singular():
        try: inverse(((1,0,0),(0,0,0),(0,0,1)))
        except ValueError: return 'exactly singular basis rejected'
        raise AssertionError('singular basis accepted')
    case('normal.singular_rejected', singular)

    half=Fraction(1,2); one=Fraction(1); zero=Fraction(0)
    red=(one,zero,zero,half); blue=(zero,zero,one,half)
    white=(one,one,one,one); clear=(zero,zero,zero,zero)
    compositions = [
        ('red_then_blue_over_white', red, blue, white, (half,Fraction(1,4),Fraction(3,4),one)),
        ('blue_then_red_over_white', blue, red, white, (Fraction(3,4),Fraction(1,4),half,one)),
        ('red_then_blue_over_transparent', red, blue, clear, (Fraction(1,3),zero,Fraction(2,3),Fraction(3,4))),
        ('blue_then_red_over_transparent', blue, red, clear, (Fraction(2,3),zero,Fraction(1,3),Fraction(3,4))),
    ]
    alpha_results={}
    for name, first, second, base, expected in compositions:
        def alpha_case(first=first,second=second,base=base,expected=expected,name=name):
            actual=source_over(second,source_over(first,base)); need(actual==expected,'source-over expected mismatch')
            alpha_results[name]=rational_list(actual); return rational_list(actual)
        case('alpha.'+name, alpha_case)
    case('alpha.zero_over_zero', lambda: zero_alpha_case(clear))
    def transfer():
        decoded=srgb_decode(.5); encoded=srgb_encode(.5)
        need(approx(decoded,.21404114048223255,1e-12) and approx(encoded,.7353569830524495,1e-12), 'sRGB anchor mismatch')
        need(approx(srgb_encode(decoded),.5,1e-12), 'sRGB roundtrip')
        return {'srgb_0.5_to_linear': decoded, 'linear_0.5_to_srgb': encoded}
    case('color.srgb_transfer_anchors',transfer)
    calculations['linear_straight_rgba_source_over'] = alpha_results

    sizes={}
    for side,per_expected,total_expected in [(256,349524,5592384),(512,1398100,22369600),(1024,5592404,89478464)]:
        def mip_case(side=side,per_expected=per_expected,total_expected=total_expected):
            levels=mip_bytes(side); per=sum(levels); total=16*per
            closed=4*((4*side*side-1)//3)
            need(per==per_expected==closed and total==total_expected, 'mip arithmetic mismatch')
            row={'size': side, 'levels': len(levels), 'bytes_each': per, 'bytes_16': total, 'candidate_32_mib_cap_bytes': 32*MIB, 'payload_fits_32_mib': total <= 32*MIB, 'headroom_bytes': 32*MIB-total}
            sizes[str(side)]=row; return row
        case('budget.rgba8_mips_'+str(side), mip_case)
    calculations['rgba8_full_mips'] = sizes
    def base64_case():
        n=MIB; per=4*((n+2)//3); encoded=base64.b64encode(bytes(n)); total=16*per
        one_stream=4*((16*n+2)//3)
        need(len(encoded)==per==1398104 and total==22369664 and one_stream==22369624, 'per-file base64 padding mismatch')
        row={'files_assumed_unique':16,'raw_bytes_each':n,'base64_bytes_each':per,'base64_bytes_16':total,'equivalent_single_stream_bytes':one_stream,'additional_separate_padding_bytes':total-one_stream,'candidate_bundle_cap_bytes':24*MIB,'base64_only_fits_cap':total <= 24*MIB,'remaining_before_json_and_other_assets':24*MIB-total}
        calculations['base64_separate_files']=row; return row
    case('budget.base64_16_separate_1mib_files',base64_case)

    def ownership():
        # Jobs write private targets even before the token is checked.
        a={'id':'A','pixels':None}; b={'id':'B','pixels':None}; c={'id':'C','pixels':None}
        state={'revision':2,'accepted':None}
        def finish(revision, target, pixels):
            target['pixels']=pixels
            publish=(revision==state['revision'])
            if publish: state['accepted']=target
            return publish
        need(finish(2,b,'B'), 'latest B was not published')
        frozen=state['accepted']
        stale_published=finish(1,a,'A')
        need(not stale_published and state['accepted'] is b and frozen['pixels']=='B', 'late A affected B')
        state['revision']=3
        need(finish(3,c,'C'), 'latest C was not published')
        need(frozen is b and frozen['pixels']=='B' and state['accepted'] is c and c['pixels']=='C', 'frozen revision changed')
        row={'completion_order':['B@2','A@1','C@3'],'late_A_published':stale_published,'active_handle':state['accepted']['id'],'frozen_handle':frozen['id'],'frozen_pixels':frozen['pixels']}
        calculations['owned_output_order']=row; return row
    case('ownership.out_of_order_and_frozen_handle',ownership)
    def unsafe_shared():
        # Counterexample: the obsolete job can write before token validation.
        shared={'pixels':'B'}; accepted=shared; frozen=shared
        shared['pixels']='A'  # stale A's in-place GPU/output write
        stale_published=False # publication rejected, but damage already occurred
        need(not stale_published and accepted['pixels']=='A' and frozen['pixels']=='A', 'shared-target counterexample did not corrupt pinned output')
        row={'late_A_published':False,'accepted_pixels_after_stale_write':accepted['pixels'],'frozen_pixels_after_stale_write':frozen['pixels'],'implication':'token checks cannot undo writes into shared output'}
        calculations['unsafe_shared_target_counterexample']=row; return row
    case('ownership.shared_target_counterexample',unsafe_shared)

    failed=sum(not c['passed'] for c in cases)
    return {'schema':'openrc.decal-projection-exercises.v1','limitations':LIMITATIONS,'summary':{'cases':len(cases),'passed':len(cases)-failed,'failed':failed},'calculations':calculations,'cases':cases}


def empty_clip(tri):
    poly=clip_triangle(tri); need(poly==[], 'degenerate contact should not emit area geometry'); return {'vertices_emitted':len(poly)}


def outside_case(axis,sign):
    tangent=(axis+1)%3; other=(axis+2)%3
    p=[0.,0.,0.]; p[axis]=2.*sign
    q=p.copy(); q[tangent]=.5
    r=p.copy(); r[other]=.5
    poly=clip_triangle([p,q,r]); need(poly==[], 'fully outside triangle was retained')
    return {'vertices_emitted':len(poly)}


def cross_case(axis,sign):
    # A right triangle of area 1, clipped at its halfway axis coordinate,
    # loses the similar triangle with one-quarter the original area.
    tangent=(axis+1)%3
    p=[0.,0.,0.]; q=p.copy(); r=p.copy(); q[axis]=2.*sign; r[tangent]=1.
    tri=[p,q,r]; poly=clip_triangle(tri); valid_output(poly,tri)
    need(len(poly)==4 and approx(polygon_area(poly),.75), 'single-plane area/vertex mismatch')
    need(any(approx(v[axis],sign) for v in poly),'intersection does not touch expected plane')
    return {'vertices':len(poly),'area':polygon_area(poly),'winding_preserved':True,'uvs_finite_and_bounded':True}


def normal_case(basis,expected,expected_det):
    # Local tangent (1,1,0) is perpendicular to local normal (1,-1,0).
    local_normal=(1.,-1.,0.); local_tangent=(1.,1.,0.)
    world_tangent=matvec(basis,local_tangent)
    world_normal=unit(matvec(transpose(inverse(basis)),local_normal))
    local_back=unit(matvec(transpose(basis),world_normal))
    det=determinant(basis)
    need(approx(det,expected_det) and vec_approx(world_normal,expected), 'expected normal/determinant mismatch')
    need(approx(dot(world_tangent,world_normal),0) and vec_approx(local_back,unit(local_normal)), 'normal perpendicularity or roundtrip')
    oriented_face=cross(matvec(basis,(1,0,0)),matvec(basis,(0,1,0)))
    transformed_face_normal=unit(matvec(transpose(inverse(basis)),(0,0,1)))
    orientation=dot(oriented_face,transformed_face_normal)
    need(orientation*det>0, 'reflection winding sign mismatch')
    return {'determinant':det,'world_normal':[round(x,9) for x in world_normal],'tangent_dot_normal':round(dot(world_tangent,world_normal),12),'roundtrip':True,'orientation_sign':1 if orientation>0 else -1}


def zero_alpha_case(clear):
    result=source_over(clear,clear); need(result==clear, 'zero-alpha canonicalization'); return rational_list(result)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true',help='print named offline exercise results and calculations')
    parser.add_argument('--write-results',type=Path,metavar='PATH',help='write compact machine-readable results')
    args=parser.parse_args()
    if not args.check and not args.write_results: parser.error('use --check and/or --write-results PATH')
    report=run()
    if args.check:
        for item in report['cases']:
            detail=item.get('observed',item.get('error'))
            print(('PASS ' if item['passed'] else 'FAIL ')+item['name']+' '+json.dumps(detail,sort_keys=True))
        print('CALCULATIONS '+json.dumps(report['calculations'],sort_keys=True))
        print('SUMMARY '+json.dumps(report['summary'],sort_keys=True))
    if args.write_results:
        args.write_results.write_text(json.dumps(report,sort_keys=True,separators=(',',':'),allow_nan=False)+'\n',encoding='utf-8')
        print('WROTE '+str(args.write_results))
    return 1 if report['summary']['failed'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
