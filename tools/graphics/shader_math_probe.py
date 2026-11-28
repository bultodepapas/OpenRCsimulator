#!/usr/bin/env python3
"""Execute source-bound shader math in surfaceless OpenGL; this is not a game benchmark.

Uses the system EGL/OpenGL libraries through ctypes, with no window, socket,
third-party Python package, or installed game code. It compiles extracted GLSL
from the actual candidate. Independent geometric/coverage/transfer oracles and
baseline negative controls distinguish a mathematical repair from an image or
target-GPU performance claim. The JSON records exactly what was exercised.
"""
from __future__ import annotations

import argparse
import ctypes as C
from ctypes.util import find_library
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import platform
import re
import subprocess


def function(source: str, name: str) -> str:
    match = re.search(r"(?:float|vec[234])\s+" + re.escape(name) + r"\s*\(", source)
    if match is None:
        raise ValueError(f"missing shader function: {name}")
    opening = source.index("{", match.start())
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[match.start():end]


class OffscreenGL:
    """Small float framebuffer driver. No game/frame-time claims derive from it."""

    def __init__(self) -> None:
        library = find_library("EGL")
        if not library:
            raise RuntimeError("system EGL is unavailable; no shader result")
        self.egl = C.CDLL(library)
        self.egl.eglGetProcAddress.argtypes = [C.c_char_p]
        self.egl.eglGetProcAddress.restype = C.c_void_p
        address = self.egl.eglGetProcAddress(b"eglGetPlatformDisplayEXT")
        if not address:
            raise RuntimeError("surfaceless EGL extension is unavailable")
        platform_display = C.CFUNCTYPE(C.c_void_p, C.c_uint, C.c_void_p, C.POINTER(C.c_int))(address)
        self.display = platform_display(0x31DD, None, None)  # EGL_PLATFORM_SURFACELESS_MESA
        init = self._egl("eglInitialize", C.c_uint, C.c_void_p, C.POINTER(C.c_int), C.POINTER(C.c_int))
        major, minor = C.c_int(), C.c_int()
        if not init(self.display, C.byref(major), C.byref(minor)):
            raise RuntimeError("surfaceless EGL initialization failed")
        if not self._egl("eglBindAPI", C.c_uint, C.c_uint)(0x30A2):
            raise RuntimeError("OpenGL API binding failed")
        attributes = (C.c_int * 13)(0x3033, 1, 0x3040, 8, 0x3024, 8, 0x3023, 8,
                                    0x3022, 8, 0x3021, 8, 0x3038)
        config, count = C.c_void_p(), C.c_int()
        choose = self._egl("eglChooseConfig", C.c_uint, C.c_void_p, C.POINTER(C.c_int),
                           C.POINTER(C.c_void_p), C.c_int, C.POINTER(C.c_int))
        if not choose(self.display, attributes, C.byref(config), 1, C.byref(count)) or not count.value:
            raise RuntimeError("no float-probe OpenGL context configuration")
        create = self._egl("eglCreateContext", C.c_void_p, C.c_void_p, C.c_void_p,
                           C.c_void_p, C.POINTER(C.c_int))
        self.context = create(self.display, config, None, (C.c_int * 5)(0x3098, 3, 0x30FB, 3, 0x3038))
        current = self._egl("eglMakeCurrent", C.c_uint, C.c_void_p, C.c_void_p, C.c_void_p, C.c_void_p)
        if not self.context or not current(self.display, None, None, self.context):
            raise RuntimeError("OpenGL context creation failed")
        string = self.gl("glGetString", C.c_char_p, C.c_uint)
        self.identity = {"renderer": string(0x1F01).decode(), "version": string(0x1F02).decode(),
                         "vendor": string(0x1F00).decode(), "egl": f"{major.value}.{minor.value}"}
        self.vao = C.c_uint()
        self.gl("glGenVertexArrays", None, C.c_int, C.POINTER(C.c_uint))(1, C.byref(self.vao))
        self.gl("glBindVertexArray", None, C.c_uint)(self.vao.value)

    def _egl(self, name, result, *args):
        fn = getattr(self.egl, name)
        fn.restype, fn.argtypes = result, list(args)
        return fn

    def gl(self, name, result, *args):
        pointer = self.egl.eglGetProcAddress(name.encode())
        if not pointer:
            raise RuntimeError(f"missing GL procedure {name}")
        return C.CFUNCTYPE(result, *args)(pointer)

    def shader(self, kind: int, source: str) -> int:
        shader = self.gl("glCreateShader", C.c_uint, C.c_uint)(kind)
        data = C.c_char_p(source.encode())
        self.gl("glShaderSource", None, C.c_uint, C.c_int, C.POINTER(C.c_char_p), C.c_void_p)(
            shader, 1, C.byref(data), None)
        self.gl("glCompileShader", None, C.c_uint)(shader)
        success = C.c_int()
        self.gl("glGetShaderiv", None, C.c_uint, C.c_uint, C.POINTER(C.c_int))(shader, 0x8B81, C.byref(success))
        if not success.value:
            log = C.create_string_buffer(16384)
            self.gl("glGetShaderInfoLog", None, C.c_uint, C.c_int, C.c_void_p, C.c_void_p)(shader, len(log), None, log)
            raise RuntimeError(log.value.decode())
        return shader

    def render(self, body: str, rows: list[list[float]] | None = None, *, width: int = 0,
               height: int = 1, uniforms: dict | None = None) -> list[list[float]]:
        width = width or len(rows or [])
        if width < 1:
            raise ValueError("empty probe")
        vertex = self.shader(0x8B31, """#version 330 core
void main() { vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0); }
""")
        fragment = self.shader(0x8B30, "#version 330 core\nuniform sampler2D inputs;\nout vec4 result;\n" + body)
        program = self.gl("glCreateProgram", C.c_uint)()
        attach = self.gl("glAttachShader", None, C.c_uint, C.c_uint)
        attach(program, vertex)
        attach(program, fragment)
        self.gl("glLinkProgram", None, C.c_uint)(program)
        success = C.c_int()
        self.gl("glGetProgramiv", None, C.c_uint, C.c_uint, C.POINTER(C.c_int))(program, 0x8B82, C.byref(success))
        if not success.value:
            raise RuntimeError("GL probe link failed")
        self.gl("glUseProgram", None, C.c_uint)(program)
        get_uniform = self.gl("glGetUniformLocation", C.c_int, C.c_uint, C.c_char_p)
        for name, value in (uniforms or {}).items():
            location = get_uniform(program, name.encode())
            if isinstance(value, (bool, int)):
                self.gl("glUniform1i", None, C.c_int, C.c_int)(location, int(value))
            elif isinstance(value, (tuple, list)):
                self.gl("glUniform3f", None, C.c_int, C.c_float, C.c_float, C.c_float)(location, *value)
            else:
                self.gl("glUniform1f", None, C.c_int, C.c_float)(location, value)
        textures = (C.c_uint * 2)()
        self.gl("glGenTextures", None, C.c_int, C.POINTER(C.c_uint))(2, textures)
        bind_texture = self.gl("glBindTexture", None, C.c_uint, C.c_uint)
        image = self.gl("glTexImage2D", None, C.c_uint, C.c_int, C.c_int, C.c_int,
                        C.c_int, C.c_int, C.c_uint, C.c_uint, C.c_void_p)
        parameter = self.gl("glTexParameteri", None, C.c_uint, C.c_uint, C.c_int)
        self.gl("glActiveTexture", None, C.c_uint)(0x84C0)
        bind_texture(0x0DE1, textures[0])
        parameter(0x0DE1, 0x2801, 0x2600)
        parameter(0x0DE1, 0x2800, 0x2600)
        input_data = (C.c_float * (width * height * 4))(*[v for row in (rows or [[0.0] * 4] * (width * height)) for v in row])
        image(0x0DE1, 0, 0x8814, width, height, 0, 0x1908, 0x1406, input_data)
        self.gl("glUniform1i", None, C.c_int, C.c_int)(get_uniform(program, b"inputs"), 0)
        self.gl("glActiveTexture", None, C.c_uint)(0x84C1)
        bind_texture(0x0DE1, textures[1])
        parameter(0x0DE1, 0x2801, 0x2600)
        parameter(0x0DE1, 0x2800, 0x2600)
        image(0x0DE1, 0, 0x8814, width, height, 0, 0x1908, 0x1406, None)
        framebuffer = C.c_uint()
        self.gl("glGenFramebuffers", None, C.c_int, C.POINTER(C.c_uint))(1, C.byref(framebuffer))
        self.gl("glBindFramebuffer", None, C.c_uint, C.c_uint)(0x8D40, framebuffer.value)
        self.gl("glFramebufferTexture2D", None, C.c_uint, C.c_uint, C.c_uint, C.c_uint, C.c_int)(
            0x8D40, 0x8CE0, 0x0DE1, textures[1], 0)
        if self.gl("glCheckFramebufferStatus", C.c_uint, C.c_uint)(0x8D40) != 0x8CD5:
            raise RuntimeError("incomplete float framebuffer")
        self.gl("glViewport", None, C.c_int, C.c_int, C.c_int, C.c_int)(0, 0, width, height)
        self.gl("glDrawArrays", None, C.c_uint, C.c_int, C.c_int)(0x0004, 0, 3)
        pixels = (C.c_float * (width * height * 4))()
        self.gl("glReadPixels", None, C.c_int, C.c_int, C.c_int, C.c_int, C.c_uint, C.c_uint, C.c_void_p)(
            0, 0, width, height, 0x1908, 0x1406, pixels)
        error = self.gl("glGetError", C.c_uint)()
        self.gl("glDeleteFramebuffers", None, C.c_int, C.POINTER(C.c_uint))(1, C.byref(framebuffer))
        self.gl("glDeleteTextures", None, C.c_int, C.POINTER(C.c_uint))(2, textures)
        self.gl("glDeleteProgram", None, C.c_uint)(program)
        delete_shader = self.gl("glDeleteShader", None, C.c_uint)
        delete_shader(vertex)
        delete_shader(fragment)
        if error:
            raise RuntimeError(f"GL error {error:#x}")
        return [list(pixels[i:i + 4]) for i in range(0, len(pixels), 4)]

    def close(self):
        self._egl("eglMakeCurrent", C.c_uint, C.c_void_p, C.c_void_p, C.c_void_p, C.c_void_p)(self.display, None, None, None)
        self._egl("eglDestroyContext", C.c_uint, C.c_void_p, C.c_void_p)(self.display, self.context)
        self._egl("eglTerminate", C.c_uint, C.c_void_p)(self.display)


def run(repo: Path, baseline: str) -> dict:
    sources: dict[str, str] = {}

    def read(path: str) -> str:
        source = (repo / path).read_text()
        sources[path] = hashlib.sha256(source.encode()).hexdigest()
        return source

    def old(path: str) -> str:
        return subprocess.check_output(["git", "show", f"{baseline}:{path}"], cwd=repo, text=True)

    report = {"format": "openrc-native-shader-math v1", "utc": datetime.now(timezone.utc).isoformat(),
              "baseline": baseline, "platform": platform.platform(), "source_sha256": sources,
              "scope": "Extracted GLSL numeric behavior on the named OpenGL implementation; no game images, FPS, GPU/CPU frame times, memory benchmark or target qualification.",
              "probes": {}}
    gl = OffscreenGL()
    report["opengl"] = gl.identity
    checks = report["probes"]
    try:
        # The geometric oracle varies the camera axis while keeping a ray segment's
        # Euclidean length fixed. Orthographic off-centre VIEW must not scale it.
        water = read("app/render/lake/water.gdshader")
        rows, expected = [], []
        for length in [0.0, 0.02, 0.5, 2.0, 8.0, 20.0]:
            for angle in [0.0, 15.0, 45.0, 80.0]:
                cosine = math.cos(math.radians(angle))
                rows.append([length * cosine, cosine, 0.0, 0.46])
                expected.append(min(length, 12.0))
        for cosine in [0.01, 0.2, 0.7, 1.0]:
            rows.append([2.0, cosine, 1.0, 0.46])
            expected.append(2.0)
        rows += [[-1.0, 0.5, 0.0, 0.46], [0.0, 0.0, 0.0, 0.46]]
        expected += [0.0, 0.0]
        pixels = gl.render(function(water, "water_optical_path_m") + """
void main() { vec4 p=texelFetch(inputs, ivec2(gl_FragCoord.xy), 0);
float length_m=water_optical_path_m(p.x,p.y,p.z); result=vec4(length_m,1.0-exp(-length_m*p.w),0.0,1.0); }
""", rows)
        length_error = max(abs(p[0] - e) for p, e in zip(pixels, expected))
        attenuation_error = max(abs(p[1] - (1.0 - math.exp(-e * row[3]))) for p, e, row in zip(pixels, expected, rows))
        checks["water_ray_length"] = {"cases": len(rows), "max_length_error_m": length_error,
            "max_absorption_error": attenuation_error, "pass": length_error < 2e-5 and attenuation_error < 2e-6,
            "baseline_2m_center_absorption": 1.0 - math.exp(-0.92),
            "baseline_2m_45deg_absorption": 1.0 - math.exp(-0.92 / math.sqrt(2.0))}

        lens = read("app/render/lens/lens_film.gdshader")
        rim = re.search(r"float rim_distance =.*?;\s*float rim =.*?;", lens, re.S).group(0)
        rows = [[0.5, 0.5 - 0.006 - x * 0.008, 0, 0] for x in [-4, -2, -1, -0.5, 0, 0.5, 1, 2, 4]]
        pixels = gl.render("void main(){vec4 p=texelFetch(inputs,ivec2(gl_FragCoord.xy),0);float edge=p.x;float y=p.y;"
                           + rim + "result=vec4(rim);}", rows)
        expected = [0.35 * math.exp(-x * x) for x in [-4, -2, -1, -0.5, 0, 0.5, 1, 2, 4]]
        error = max(abs(p[0] - e) for p, e in zip(pixels, expected))
        checks["signed_gaussian_rim"] = {"cases": len(rows), "max_error": error,
            "finite": all(math.isfinite(v) for p in pixels for v in p), "pass": error < 2e-6,
            "baseline_limit": "Negative-base pow is undefined by GLSL; a driver's constant-folding is not a portable pass."}

        colors = read("app/scenery/vertex_color_linear.gdshaderinc")
        country = read("app/render/landscape_upgrade/countryside_surface.gdshader")
        if "COLOR.rgb = vertex_color_to_linear(COLOR.rgb);" not in country:
            raise ValueError("palette transfer is not bound at the audited vertex stage")
        rows = [[x, x, x, 1] for x in [0, 0.02, 0.04045, 81 / 255, 83 / 255, 0.5, 1]]
        transfer_errors = []
        for compatibility in [False, True]:
            pixels = gl.render(f"#define OUTPUT_IS_SRGB {'true' if compatibility else 'false'}\n" + colors +
                "void main(){vec3 c=texelFetch(inputs,ivec2(gl_FragCoord.xy),0).rgb;result=vec4(vertex_color_to_linear(c),1.0);}", rows)
            expected = [r[0] if compatibility else r[0] / 12.92 if r[0] <= 0.04045 else ((r[0] + 0.055) / 1.055) ** 2.4 for r in rows]
            transfer_errors.append(max(abs(p[0] - e) for p, e in zip(pixels, expected)))
        checks["palette_transfer"] = {"cases": 2 * len(rows), "max_errors_rd_compatibility": transfer_errors,
            "pass": max(transfer_errors) < 2e-6, "road_srgb": 81 / 255,
            "road_linear": ((81 / 255 + 0.055) / 1.055) ** 2.4}

        windsock = read("app/render/windsock_deformation.gdshaderinc")
        tangent = re.search(r"vec3 surface_tangent = [^;]+;", windsock).group(0)
        rows = [[0.45, 0.18, 2.5, 0], [0.5, 0.5, 3, 0], [0.3, 0.1, 1, 0]]
        pixels = gl.render("void main(){vec4 p=texelFetch(inputs,ivec2(gl_FragCoord.xy),0);"
            "float throat_diameter_m=p.x,tail_diameter_m=p.y,length_m=p.z;vec3 axis=vec3(1,0,0),radial=vec3(0,1,0);"
            + tangent + "result=vec4(surface_tangent,1);}", rows)
        errors = []
        for p, row in zip(pixels, rows):
            step = row[2] * 1e-4
            radius = lambda s: (row[0] + (row[1] - row[0]) * s / row[2]) * 0.5
            slope = (radius(row[2] / 2 + step) - radius(row[2] / 2 - step)) / (2 * step)
            oracle = [1 / math.hypot(1, slope), slope / math.hypot(1, slope), 0]
            errors.append(max(abs(x - y) for x, y in zip(p[:3], oracle)))
        checks["windsock_rigid_taper"] = {"cases": len(rows), "max_error": max(errors), "pass": max(errors) < 2e-6,
            "scope": "Exact radius derivative in straight rigid section; flexible/folded cloth remains approximate."}

        veneer = read("app/assets/vehicle-paints/turbo-lumber-evolution/aserradero.gdshader")
        rows = [[phase * width, width, footprint * width, 0] for width in [0.034, 0.037, 0.039, 0.043]
                for phase in [-3.2, -0.5, 0, 0.1, 0.5, 1.0, 3.7] for footprint in [0.025, 0.1, 0.5, 1, 2, 7.5]]
        pixels = gl.render(function(veneer, "billet_integral") + "\n" + function(veneer, "billet_joint") +
            "void main(){vec4 p=texelFetch(inputs,ivec2(gl_FragCoord.xy),0);result=vec4(billet_joint(p.x,p.y,p.z));}", rows)
        errors = []
        for pixel, (centre, period, span, _) in zip(pixels, rows):
            left, right = centre - span / 2, centre + span / 2
            coverage = sum(max(0.0, min(right, k * period + 0.00055) - max(left, k * period - 0.00055))
                           for k in range(math.floor(left / period) - 1, math.ceil(right / period) + 2)) / span
            errors.append(abs(pixel[0] - coverage))
        checks["veneer_periodic_coverage"] = {"cases": len(rows), "max_error": max(errors), "pass": max(errors) < 1e-4,
            "one_top_board_mean_coverage": 0.0011 / 0.043, "baseline_equal_phase_extremes": [0.0, 1.0]}

        roof = read("app/scenery/pit_shelter_roof.gdshader")
        read("app/scenery/building_roofs.gdshader")
        rows = [[1 / pixels_per_tile, sign, kind, 0.67] for pixels_per_tile in [1, 900, 1080, 1800, 1e6]
                for sign in [-1, 1] for kind in [0, 1, 2, 3]]
        body = function(roof, "normal_from_uv") + """
void main(){vec4 p=texelFetch(inputs,ivec2(gl_FragCoord.xy),0);float s=p.x;
vec2 ux=vec2(s*p.y,0),uy=vec2(0,s);vec3 px=vec3(s,0,0),py=vec3(0,s,0);
if(p.z==1.0){ux=vec2(0);uy=vec2(0);} if(p.z==2.0){uy=ux;} if(p.z==3.0){py=px;}
result=vec4(normal_from_uv(vec3(0,0,1),ux,uy,px,py,vec3(249,139,164)/255.0,p.w),1);}
"""
        pixels = gl.render(body, rows)
        errors = []
        for pixel, (_, sign, kind, strength) in zip(pixels, rows):
            normal = [(249 / 255 * 2 - 1) * strength * sign, (139 / 255 * 2 - 1) * strength, 164 / 255 * 2 - 1] if kind == 0 else [0, 0, 1]
            length = math.sqrt(sum(x * x for x in normal))
            errors.append(max(abs(v - n / length) for v, n in zip(pixel[:3], normal)))
        checks["roof_frame_conditioning"] = {"cases": len(rows), "max_error": max(errors), "pass": max(errors) < 3e-6,
            "scope": "Executes production shelter helper; building inline consumer receives full-scene CI coverage separately."}

        ground = read("app/render/ground.gdshader")
        contribution = re.search(r"SPECULAR_LIGHT \+= [^;]+;", ground).group(0)
        rows = [[amount, 0, 0, 0] for amount in [0.0, 0.7, 1.0]]
        pixels = gl.render("void main(){float SPECULAR_AMOUNT=texelFetch(inputs,ivec2(gl_FragCoord.xy),0).x;"
            "vec3 SPECULAR_LIGHT=vec3(0),LIGHT_COLOR=vec3(1);float ATTENUATION=1.0,transmission=1.0,"
            "rc_soil_specular=0.1,distribution=0.3,geometry=0.7,fresnel=0.04,nv=0.8;"
            + contribution + "result=vec4(SPECULAR_LIGHT,1);}", rows)
        coefficient = 0.1 * 0.3 * 0.7 * 0.04 / (4.0 * 0.8)
        error = max(abs(pixel[0] - coefficient * row[0]) for pixel, row in zip(pixels, rows))
        checks["positional_specular_control"] = {"cases": len(rows), "max_error": error,
            "pass": error < 1e-9 and pixels[0][0] == 0.0, "controls": [row[0] for row in rows],
            "scope": "Exact dirt specular accumulation expression; diffuse and full-light transport excluded."}

        rain_path = "app/render/weather/rain_curtain.gdshader"
        rain = read(rain_path)
        lods = {}
        for name, source in [("baseline", old(rain_path)), ("candidate", rain)]:
            if name == "candidate":
                snippet = re.search(r"vec2 fine_uv =.*?;\s*float fine =.*?;", source, re.S).group(0)
                snippet = snippet.replace("textureGrad(", "observe_explicit(")
            else:
                snippet = re.search(r"float fine = [^;]+;", source).group(0)
                snippet = snippet.replace("texture(", "observe_implicit(")
            body = """
uniform sampler2D cloud_texture;
vec4 observe_explicit(sampler2D unused_map,vec2 uv,vec2 dx,vec2 dy){
return vec4(log2(max(2048.0*max(length(dx),length(dy)),1.0)));}
vec4 observe_implicit(sampler2D unused_map,vec2 uv){
return observe_explicit(unused_map,uv,dFdx(uv),dFdy(uv));}
void main(){vec2 UV=gl_FragCoord.xy/vec2(500.0,2.0);
""" + snippet + "result=vec4(fine);}\n"
            lods[name] = [p[0] for p in gl.render(body, width=500, height=2)]
        expected = math.log2(2048.0 * 3.0 / 500.0)
        error = max(abs(value - expected) for value in lods["candidate"])
        checks["rain_repeat_footprint"] = {"cases": len(lods["candidate"]), "expected_lod": expected,
            "baseline_peak_lod": max(lods["baseline"]), "candidate_max_error": error,
            "pass": error < 1e-4 and max(lods["baseline"]) - expected > 4.0,
            "instrumentation": "Observe the exact sample coordinates/gradients at a 2048-square mip footprint; texture filtering, image content and compositing excluded."}

        moon_path = "app/render/world/moon_disc.gdshaderinc"
        moon = read(moon_path)
        moon_values = {}
        for name, source in [("baseline", old(moon_path)), ("candidate", moon)]:
            # Observe the exact LOD scalar before texture fetch. No synthetic
            # image is presented as a simulator capture.
            source = re.sub(r"(uniform sampler2D\s+\w+)\s*:[^;]+;", r"\1;", source)
            source, count = re.subn(r"(float lod = [^;]+;)", r"\1\nreturn vec3(lod, aa, rr);", source)
            if count != 1:
                raise ValueError("moon LOD observation point changed")
            body = source + """
void main(){vec2 xy=(gl_FragCoord.xy-vec2(17.0))*sin(moon_radius)*0.2;
vec3 d=vec3(xy,-sqrt(max(1.0-dot(xy,xy),0.0)));result=vec4(moon_disc(d),1.0);}
"""
            pixels = gl.render(body, width=32, height=32,
                uniforms={"moon_dir": (0, 0, -1), "moon_lin": (1, 1, 1), "moon_textured": True})
            moon_values[name] = [pixels[y * 32 + x][0] for y in [16, 17] for x in [16, 17]]
        expected_lod = math.log2(512 * 0.2 / math.sqrt(0.98))
        error = max(abs(value - expected_lod) for value in moon_values["candidate"])
        checks["moon_center_footprint"] = {"cases": 4, "lod": moon_values, "expected_conservative_lod": expected_lod,
            "max_error": error, "pass": error < 2e-5 and all(v == 0 for v in moon_values["baseline"]),
            "instrumentation": "Insert return of LOD, radial AA and radius immediately after original LOD assignment; texture fetch and radiometry excluded."}
        report["ok"] = all(item["pass"] for item in checks.values())
        report["case_count"] = sum(item["cases"] for item in checks.values())
    finally:
        gl.close()
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--baseline", default="71306784a250d634854f0c8bab3a927cc46a61b8")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if args.out.exists():
        parser.error("output must be new")
    result = run(args.repo.resolve(), args.baseline)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("x") as output:
        json.dump(result, output, indent=2, allow_nan=False)
        output.write("\n")
    print(json.dumps({"ok": result["ok"], "case_count": result["case_count"], "opengl": result["opengl"], "out": str(args.out)}))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
