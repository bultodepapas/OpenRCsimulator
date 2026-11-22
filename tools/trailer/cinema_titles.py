"""Frame-addressed, transparent title plates for the 1080p trailer.

All cue times are global frame numbers in the half-open interval [in_frame,
out_frame). With a nonzero entrance fade the first frame is transparent and
the title first reaches full opacity at in_frame + fade_in_frames. A nonzero
exit fade ends transparent at out_frame - 1. A zero-length fade is opaque at
that boundary, which is essential for disclosures. At least one fully opaque
frame is required. The y coordinate is the top of the first line's visible ink;
x anchors each line's visible ink according to align.

This module creates graphics only; it neither captures nor changes simulator
state. Composite the resulting numbered RGBA PNGs onto real footage at 60 fps.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import re
import shutil
import unicodedata
from pathlib import Path

import PIL
from PIL import Image, ImageDraw, ImageFilter, ImageFont, features

W, H, FPS = 1920, 1080, 60
FONT_DIR = Path(__file__).resolve().parent / "assets" / "fonts"
_EXPECTED = {
    "BarlowCondensed-Regular.ttf": "583cec5da3b84bc4dc7c9c72e2a565c94d34e431518b19d7e250b7830ad5f996",
    "BarlowCondensed-SemiBold.ttf": "7b619d14bc2327509a9ef32b0890f709626f7ecc9ff61191c2a4314c5499d2d9",
    "OFL.txt": "186d750eb496a4c17a76385f82be6aea2ac1cf2de074a811d63786cf374ea73f",
}
_FIELDS = {
    "id", "role", "lines", "in_frame", "out_frame", "x", "y", "align",
    "size", "tracking", "color", "fade_in_frames", "fade_out_frames",
    "drift_px", "shadow_alpha",
}
_MAX_FRAME = 10_000_000


def _sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def dependency_identity(font_dir=None):
    """Verify the vendored assets and return a JSON-serializable cache identity.

    The pinned digests, provenance entries and local bytes must all agree. The
    Pillow and text-layout library versions are reported because font hashes
    alone do not guarantee identical rasterization across machines.
    """
    directory = Path(font_dir) if font_dir is not None else FONT_DIR
    provenance_path = directory / "provenance.json"
    try:
        records = json.loads(provenance_path.read_text(encoding="utf-8"))
        if not isinstance(records, list):
            raise ValueError("provenance must be a list")
        entries = {entry["file"]: entry for entry in records}
        if len(entries) != len(records) or set(entries) != set(_EXPECTED):
            raise ValueError("provenance asset list does not match the pinned assets")
        assets = {}
        for name, expected in _EXPECTED.items():
            record = entries[name]
            if record["sha256"] != expected or _sha256(directory / name) != expected:
                raise ValueError(f"asset digest mismatch: {name}")
            source = record["source"]
            if source != f"https://raw.githubusercontent.com/google/fonts/main/ofl/barlowcondensed/{name}":
                raise ValueError(f"unexpected asset source: {name}")
            assets[name] = {"sha256": expected, "source": source}
    except (OSError, KeyError, TypeError, json.JSONDecodeError) as exc:
        raise ValueError(f"could not verify title asset provenance: {exc}") from exc
    return {
        "assets": assets,
        "provenance_sha256": _sha256(provenance_path),
        "pillow": PIL.__version__,
        "freetype": features.version_module("freetype2"),
        "raqm": features.version_feature("raqm") if features.check_feature("raqm") else None,
    }


def _integer(value, name, low, high):
    if isinstance(value, bool) or not isinstance(value, int) or not low <= value <= high:
        raise ValueError(f"{name} must be an integer from {low} to {high}")
    return value


def _number(value, name, low, high):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{name} must be a finite number from {low} to {high}")
    if not low <= value <= high or not math.isfinite(value):
        raise ValueError(f"{name} must be a finite number from {low} to {high}")
    return float(value)


def _font(size, role):
    name = "BarlowCondensed-Regular.ttf" if role == "label" else "BarlowCondensed-SemiBold.ttf"
    return ImageFont.truetype(str(FONT_DIR / name), size)


def _line_mask(text, font, tracking):
    """Render a trimmed ink mask with pair kerning plus explicit tracking.

    Glyphs are drawn separately to add tracking; pair advances include the
    kerning that would otherwise be lost. Disable ligatures when libraqm is
    available because separated glyphs cannot draw a shaped ligature.
    """
    use_features = ["-liga", "-clig"] if features.check_feature("raqm") else None
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    positions = []
    cursor = 0.0
    for index, char in enumerate(text):
        positions.append(cursor)
        if index + 1 < len(text):
            pair = text[index:index + 2]
            cursor += (probe.textlength(pair, font=font, features=use_features)
                       - probe.textlength(text[index + 1], font=font, features=use_features)
                       + tracking)
    boxes = [probe.textbbox((pos, 0), char, font=font, features=use_features)
             for pos, char in zip(positions, text)]
    left = math.floor(min(box[0] for box in boxes)) - 2
    top = math.floor(min(box[1] for box in boxes)) - 2
    right = math.ceil(max(box[2] for box in boxes)) + 2
    bottom = math.ceil(max(box[3] for box in boxes)) + 2
    mask = Image.new("L", (right - left, bottom - top))
    draw = ImageDraw.Draw(mask)
    for pos, char in zip(positions, text):
        draw.text((pos - left, -top), char, font=font, fill=255, features=use_features)
    ink = mask.getbbox()
    if ink is None:
        raise ValueError("each line must contain visible text")
    return mask.crop(ink)


def _prepare(cue):
    if not isinstance(cue, dict):
        raise ValueError("cue must be an object")
    unknown = set(cue) - _FIELDS
    if unknown:
        raise ValueError(f"unknown cue fields: {', '.join(sorted(map(str, unknown)))}")
    for name in ("id", "role", "lines", "in_frame", "out_frame", "x", "y", "align"):
        if name not in cue:
            raise ValueError(f"missing cue field: {name}")
    identifier = cue["id"]
    if (not isinstance(identifier, str) or not identifier.strip() or len(identifier) > 128
            or any(unicodedata.category(c).startswith("C") for c in identifier)):
        raise ValueError("id must be a nonempty printable string of at most 128 characters")
    role = cue["role"]
    if role not in ("headline", "label", "endcard"):
        raise ValueError("role must be headline, label or endcard")
    lines = cue["lines"]
    if not isinstance(lines, list) or not 1 <= len(lines) <= 3:
        raise ValueError("lines must contain one to three strings")
    for line in lines:
        if (not isinstance(line, str) or not line.strip() or len(line) > 256
                or any(unicodedata.category(c).startswith(("C", "M")) for c in line)):
            raise ValueError("lines must contain printable text with no controls or combining marks")
    start = _integer(cue["in_frame"], "in_frame", 0, _MAX_FRAME)
    end = _integer(cue["out_frame"], "out_frame", 1, _MAX_FRAME)
    if end <= start:
        raise ValueError("out_frame must be later than in_frame")
    align = cue["align"]
    if align not in ("left", "center", "right"):
        raise ValueError("align must be left, center or right")
    x = _number(cue["x"], "x", 0, W)
    y = _number(cue["y"], "y", 0, H)
    size = _integer(cue.get("size", 32 if role == "label" else 96), "size", 12, 240)
    tracking = _number(cue.get("tracking", 2 if role == "label" else 4), "tracking", 0, 32)
    entrance = _integer(cue.get("fade_in_frames", 0 if role == "label" else 18),
                        "fade_in_frames", 0, _MAX_FRAME)
    exit_ = _integer(cue.get("fade_out_frames", 0 if role == "label" else 12),
                     "fade_out_frames", 0, _MAX_FRAME)
    if end - start <= entrance + exit_:
        raise ValueError("cue must have at least one fully opaque settled frame")
    drift = _number(cue.get("drift_px", 0 if role == "label" else 8), "drift_px", 0, 96)
    shadow = _integer(cue.get("shadow_alpha", 100), "shadow_alpha", 0, 160)
    color = cue.get("color", "F2EFE7")
    if not isinstance(color, str) or not re.fullmatch(r"#?[0-9a-fA-F]{6}", color):
        raise ValueError("color must be a six-digit RGB hex string")
    color = color.lstrip("#")
    rgb = tuple(int(color[i:i + 2], 16) for i in (0, 2, 4))

    dependency_identity()
    face = _font(size, role)
    # FreeType returns the same .notdef glyph for missing characters. Catch
    # that common failure explicitly instead of silently rendering tofu.
    missing = face.getmask("\uffff")
    missing_signature = (missing.size, bytes(missing))
    for char in set("".join(lines)):
        if not char.isspace():
            glyph = face.getmask(char)
            if (glyph.size, bytes(glyph)) == missing_signature:
                raise ValueError(f"font has no glyph for U+{ord(char):04X}")
    masks = [_line_mask(line, face, tracking) for line in lines]
    rows = []
    top = round(y)
    gap = max(3, round(size * 0.20))
    for mask in masks:
        if align == "left":
            left = round(x)
        elif align == "right":
            left = round(x - mask.width)
        else:
            left = round(x - mask.width / 2)
        box = (left, top, left + mask.width, top + mask.height)
        max_drift = math.ceil(drift) if entrance else 0
        if left < 96 or top < 80 or box[2] > 1824 or box[3] + max_drift > 1000:
            raise ValueError(f"cue {identifier!r} visible ink or motion exceeds the title-safe area: {box}")
        rows.append((mask, box))
        top = box[3] + gap
    return {"id": identifier, "start": start, "end": end, "entrance": entrance,
            "exit": exit_, "drift": drift, "shadow": shadow, "color": rgb,
            "role": role, "rows": rows}


def validate_cue(cue):
    """Validate cue fields, asset identity, settled hold and safe ink bounds."""
    _prepare(cue)


def _smooth(value):
    p = min(1.0, max(0.0, value))
    return p * p * (3.0 - 2.0 * p)


class CinemaCue:
    """A pre-rasterized cue sampled by its global, not shot-local, frame."""

    def __init__(self, cue):
        self._data = _prepare(cue)
        d = self._data
        self.id = d["id"]
        self.in_frame, self.out_frame = d["start"], d["end"]
        self.ink_boxes = tuple(box for _, box in d["rows"])
        left = min(box[0] for box in self.ink_boxes)
        top = min(box[1] for box in self.ink_boxes)
        right = max(box[2] for box in self.ink_boxes)
        bottom = max(box[3] for box in self.ink_boxes)
        pad = 20
        self._origin = (left - pad, top - pad)
        mask = Image.new("L", (right - left + 2 * pad, bottom - top + 2 * pad))
        for line, box in d["rows"]:
            mask.paste(line, (box[0] - left + pad, box[1] - top + pad))
        layer = Image.new("RGBA", mask.size)
        if d["shadow"]:
            blur = mask.filter(ImageFilter.GaussianBlur(3 if d["role"] == "label" else 5))
            blur = blur.point(lambda a: a * d["shadow"] // 255)
            shadow = Image.new("RGBA", mask.size, (0, 0, 0, 0))
            shadow_alpha = Image.new("L", mask.size)
            shadow_alpha.paste(blur, (0, 2))
            shadow.putalpha(shadow_alpha)
            layer.alpha_composite(shadow)
        text = Image.new("RGBA", mask.size, d["color"] + (0,))
        text.putalpha(mask)
        layer.alpha_composite(text)
        self._layer = layer

    def _state(self, frame):
        d = self._data
        if frame < d["start"] or frame >= d["end"]:
            return 0, 0
        elapsed = frame - d["start"]
        entrance = _smooth(elapsed / d["entrance"]) if d["entrance"] else 1.0
        exit_ = _smooth((d["end"] - 1 - frame) / d["exit"]) if d["exit"] else 1.0
        opacity = round(255 * min(entrance, exit_))
        shift = round(d["drift"] * (1 - entrance)) if d["entrance"] else 0
        return opacity, shift

    def _composite(self, image, opacity, shift):
        if not opacity:
            return
        layer = self._layer
        if opacity < 255:
            layer = layer.copy()
            layer.putalpha(layer.getchannel("A").point(lambda a: (a * opacity + 127) // 255))
        image.alpha_composite(layer, (self._origin[0], self._origin[1] + shift))

    def frame(self, global_frame):
        """Return the cue at global_frame as a full-size RGBA image."""
        _integer(global_frame, "global_frame", -_MAX_FRAME, _MAX_FRAME)
        image = Image.new("RGBA", (W, H))
        self._composite(image, *self._state(global_frame))
        return image


def _intersects(a, b):
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def _shifted(box, shift):
    return box[0], box[1] + shift, box[2], box[3] + shift


def _check_collisions(cues):
    ids = [cue.id for cue in cues]
    if len(ids) != len(set(ids)):
        raise ValueError("cue ids must be unique")
    for i, first in enumerate(cues):
        for second in cues[i + 1:]:
            start = max(first.in_frame, second.in_frame)
            end = min(first.out_frame, second.out_frame)
            if start >= end:
                continue
            a_drift = math.ceil(first._data["drift"]) if first._data["entrance"] else 0
            b_drift = math.ceil(second._data["drift"]) if second._data["entrance"] else 0
            if not any(_intersects((a[0], a[1], a[2], a[3] + a_drift),
                                   (b[0], b[1], b[2], b[3] + b_drift))
                       for a in first.ink_boxes for b in second.ink_boxes):
                continue
            for frame in range(start, end):
                alpha_a, shift_a = first._state(frame)
                alpha_b, shift_b = second._state(frame)
                if alpha_a and alpha_b and any(
                        _intersects(_shifted(a, shift_a), _shifted(b, shift_b))
                        for a in first.ink_boxes for b in second.ink_boxes):
                    raise ValueError(f"cues {first.id!r} and {second.id!r} overlap at frame {frame}")


def validate_cues(cues):
    """Validate a complete global cue list, including IDs and collisions."""
    if not isinstance(cues, list):
        raise ValueError("cues must be a list")
    _check_collisions([CinemaCue(cue) for cue in cues])


def render_sequence(directory, cues, start_frame, frames):
    """Reserve a new directory and write local 00000.png onward at 60 fps.

    Cues are global and retain their phase across independent shot renders.
    Identical composite states are hard-linked to their first image, with an
    exclusive-create copy fallback for filesystems that do not allow links.
    """
    _integer(start_frame, "start_frame", 0, _MAX_FRAME)
    _integer(frames, "frames", 1, 100_000)
    if start_frame + frames > _MAX_FRAME:
        raise ValueError("sequence exceeds the supported global frame range")
    if not isinstance(cues, list):
        raise ValueError("cues must be a list")
    prepared = [CinemaCue(cue) for cue in cues]
    _check_collisions(prepared)
    target_dir = Path(directory)
    target_dir.mkdir(parents=True, exist_ok=False)
    saved = {}
    for local_frame in range(frames):
        global_frame = start_frame + local_frame
        state = tuple((i, *cue._state(global_frame)) for i, cue in enumerate(prepared)
                      if cue._state(global_frame)[0])
        target = target_dir / f"{local_frame:05d}.png"
        if state in saved:
            try:
                os.link(saved[state], target)
            except FileExistsError:
                raise
            except OSError:
                with saved[state].open("rb") as source, target.open("xb") as dest:
                    shutil.copyfileobj(source, dest)
            continue
        image = Image.new("RGBA", (W, H))
        for i, opacity, shift in state:
            prepared[i]._composite(image, opacity, shift)
        with target.open("xb") as handle:
            image.save(handle, format="PNG", compress_level=1)
        saved[state] = target
    return frames
