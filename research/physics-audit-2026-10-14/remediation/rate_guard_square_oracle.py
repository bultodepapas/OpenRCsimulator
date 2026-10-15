"""Check the captured H4 square using exact rational arithmetic, not libm pow.

The captured JSON's decimal values are display values. Decode its float64 bytes
for this proof. The component is a point velocity (omega cross r), in m/s.
"""
from __future__ import annotations

import argparse
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import struct


def decode(bits: str) -> float:
    return struct.unpack("<d", bytes.fromhex(bits))[0]


def encode(value: float) -> str:
    return struct.pack("<d", value).hex()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def verify(case_path: Path) -> dict:
    captured = case_path.read_bytes()
    case = json.loads(captured)
    direct = next(row for row in case["independent_guard_multiplication"]["rows"]
                  if row["arm"] == "tail_vertical")
    powered = next(row for row in case["independent_guard_pow"]["rows"]
                   if row["arm"] == "tail_vertical")
    require(direct["component_float64_hex"] == powered["component_float64_hex"],
            "The two evaluations must use identical point-velocity components")
    component_bits = direct["component_float64_hex"][2]
    component = decode(component_bits)
    exact_square = Fraction.from_float(component) ** 2
    correctly_rounded = float(exact_square)
    direct_square_bits = direct["component_square_float64_hex"][2]
    power_square_bits = powered["component_square_float64_hex"][2]
    require(encode(correctly_rounded) == direct_square_bits,
            "Direct square is not the nearest float64 to the exact rational square")

    # Independently compare the exact errors at both neighbors of that float.
    rounded_bits = int.from_bytes(bytes.fromhex(direct_square_bits), "little")
    neighbors = [struct.unpack("<d", (rounded_bits + offset).to_bytes(8, "little"))[0]
                 for offset in (-1, 1)]
    rounding_error = abs(Fraction.from_float(correctly_rounded) - exact_square)
    require(all(rounding_error < abs(Fraction.from_float(value) - exact_square)
                for value in neighbors), "Nearest float64 is not uniquely established")
    power_error = abs(Fraction.from_float(decode(power_square_bits)) - exact_square)
    require(power_error > rounding_error, "Captured pow result is not less accurate")

    actual_bits = case["actual_float64_hex"]
    expected_bits = case["expected_float64_hex"]
    require(powered["weight_float64_hex"] == actual_bits,
            "Power reconstruction does not reproduce the production selector")
    require(direct["weight_float64_hex"] == expected_bits,
            "Product reconstruction does not reproduce the independent selector")
    ulps = int.from_bytes(bytes.fromhex(actual_bits), "little") - int.from_bytes(
        bytes.fromhex(expected_bits), "little")
    require(ulps == 12, "Unexpected positive-selector ULP separation")
    return {
        "ok": True,
        "case_sha256": hashlib.sha256(captured).hexdigest(),
        "oracle_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "case": case["case"],
        "component_unit": "m/s",
        "component_float64_hex": component_bits,
        "exact_square_numerator": str(exact_square.numerator),
        "exact_square_denominator": str(exact_square.denominator),
        "correctly_rounded_square_float64_hex": direct_square_bits,
        "captured_pow_square_float64_hex": power_square_bits,
        "direct_absolute_rounding_error": float(rounding_error),
        "pow_absolute_rounding_error": float(power_error),
        "direct_is_unique_nearest_float64": True,
        "selector_difference_ulps": ulps,
        "selector_difference": decode(actual_bits) - decode(expected_bits),
        "scope": "exact arithmetic at one captured input; not a universal libm or physical validation",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    report = verify(args.case)
    args.out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
