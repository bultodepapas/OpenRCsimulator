"""Read unambiguous flight-card evidence; null measurements remain unavailable."""
import json
import math


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON name: {key!r}")
        result[key] = value
    return result


def _finite_float(text):
    value = float(text)
    if not math.isfinite(value):
        raise ValueError(f"nonfinite JSON number: {text}")
    return value


def _finite_int(text):
    value = int(text)
    if not finite_number(value):
        raise ValueError("JSON integer exceeds the finite float64 evidence range")
    return value


def finite_number(value):
    if type(value) not in (int, float):
        return False
    try:
        return math.isfinite(value)
    except OverflowError:
        return False


def _invalid_constant(text):
    raise ValueError(f"nonfinite JSON constant: {text}")


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_unique_object,
                      parse_float=_finite_float, parse_int=_finite_int, parse_constant=_invalid_constant)


def validate_profile(profile, *, summary_metadata=False):
    if not isinstance(profile, dict) or not isinstance(profile.get("results"), dict):
        raise ValueError("profile must be an object with an object-valued results field")
    if "name" in profile and not isinstance(profile["name"], str):
        raise ValueError("profile name must be a string")
    for name, result in profile["results"].items():
        if not isinstance(name, str) or not name:
            raise ValueError("test names must be nonempty strings")
        if not isinstance(result, dict) or type(result.get("valid")) is not bool:
            raise ValueError(f"{name}: result must be an object with a boolean valid field")
        if "skipped" in result and type(result["skipped"]) is not bool:
            raise ValueError(f"{name}: skipped must be boolean")
        if not isinstance(result.get("metrics", {}), dict):
            raise ValueError(f"{name}: metrics must be an object")
        table = result.get("table", [])
        if not isinstance(table, list):
            raise ValueError(f"{name}: table must be an array")
        seen = set()
        for row in table:
            if not isinstance(row, dict) or not isinstance(row.get("case"), str) or not row["case"]:
                raise ValueError(f"{name}: each table row needs a nonempty string case")
            if row["case"] in seen:
                raise ValueError(f"{name}: duplicate case {row['case']!r}")
            seen.add(row["case"])
    if summary_metadata:
        for field in ("mass_kg", "start_speed_mps"):
            value = profile.get(field)
            if not finite_number(value):
                raise ValueError(f"profile needs finite numeric {field} for its summary")
    return profile


def read_profile(path, *, summary_metadata=False):
    return validate_profile(read_json(path), summary_metadata=summary_metadata)
