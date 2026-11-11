# Settings research — source audit and executed reference probe

**Date:** 11 November 2026. **Companion documents:** [07 — 34 investigations](07_BETAFLIGHT_INAV_SETTINGS_RESEARCH.md) and [08 — implementation/import contract](08_SETTINGS_SCHEMA_IMPORT_AND_TESTS.md). This dossier supplements the earlier OpenRC kernel/math evidence in [06](06_SOURCE_AUDIT_AND_EVIDENCE.md); those earlier tests were not rerun or reclassified for this follow-up.

## 1. What was investigated and checked

The follow-up contains **34 distinct settings investigations**, with **81 named proposed setting cases** and **18 additional proposed import/configuration cases**. Each investigation compares relevant Betaflight and INAV semantics, identifies source keys and version limits, explains racing relevance, selects an OpenRC disposition, and names state/schema/test implications. Investigation count is not a count of searches or test executions.

| Evidence ID | Work actually performed | Result and limit |
| --- | --- | --- |
| S-E01 | Queried official release metadata and obtained exact source checkouts | BF 2026.6.2 and INAV 9.1.0 were the current stable releases returned on the research date; checkout HEADs matched the named source commits. No board firmware was built or flashed. |
| S-E02 | Read implementation, reset/configuration declarations and relevant official documentation; audited document references | 34 cards, A/B coverage for every card, 81 distinct proposed setting cases, 177 current immutable source links with valid local paths/line anchors across 50 distinct primary source files; no structural/source-anchor errors. This audit checks reference structure, while claim interpretation required manual source review. |
| S-E03 | Compiled and executed narrowly extracted BF throttle functions and initializer | 14 host C evaluations, repeated with identical output; exact script, assumptions, toolchain, source hashes and observations below. Not full firmware, receiver, flight-controller or OpenRC parity. |
| S-E04 | Independent adversarial review of the integration proposal | Corrected profile apply/hold ordering, unknown-default reset invalidation, partial-import uncertainty, postcommit observer failures, sampling labels, and the faster-controller dependency path. These are specification corrections, not implemented fixes. |

The retained BF 4.5.2 references are historical baseline evidence. The current-source anchor audit explicitly excludes those old-line checks rather than pretending they were part of the new two-checkout audit.

### Exact release/source identities

| Firmware | Stable release metadata | Source commit |
| --- | --- | --- |
| Betaflight | [2026.6.2](https://github.com/betaflight/betaflight/releases/tag/2026.6.2), published 16 September 2026 | `e0b7bb01b17b21351057e9ead2d1ab39dd44fa16` |
| INAV | [9.1.0](https://github.com/iNavFlight/inav/releases/tag/9.1.0), published 9 July 2026 | `e519b69b02e27c8bdc03b4a0889f1baaae211a54` |

Release candidates/nightlies are separate products for this investigation. Runtime build flags, target overrides, persisted settings, configurator presets and effective validation remain required when qualifying a particular real configuration.

## 2. Documentation conflicts resolved by pinned source

| Topic | Conflict or trap | Resolution used in the plan |
| --- | --- | --- |
| BF launch control | A live guide labels NORMAL as default; the inspected reset source selects PITCHONLY. | Use the pin's initializer and record target/build qualifiers; see SET-12. |
| INAV RC smoothing | Settings description calls the filter biquad; inspected implementation uses PT3. | Version the executed algorithm and schedule, not the description; see SET-04. |
| INAV dynamic notch | A nearby comment describes a 32-sample FFT; the actual constant is 64. | Use the executable constant; see SET-16. |
| Failsafe duration | Similarly named fields and unversioned documentation can imply the wrong units. | BF 2026 landing time is seconds; INAV off delay is deciseconds and zero has special meaning; see SET-26. |
| INAV TPA range/terms | Documentation/schema ranges and descriptions do not fully agree. | Preserve schema domain and actual multicopter term mask; no guessed translation or universal gain advice; see SET-08. |
| Old rate compatibility versus current throttle | Same Actual expression does not imply the same throttle algorithm. | Preserve independent rate/throttle/quantization identities; see SET-01/03 and the probe below. |
| Compatible diff versus unchanged defaults | INAV 9.1 accepts 9.0.x diff syntax but changes some omitted GPS defaults. | Exact default provenance or unresolved fields; see SET-33. |

The exact source links for each finding are attached to its card in 07. Live official documentation is useful for terminology and use cases, but its location under a current guide path does not establish the version of every example. None of these discrepancies establishes a recommended real-aircraft tune.

## 3. Extracted throttle-path experiment

### Question

Does evaluating the continuous current BF throttle curve give the exact same output as its default lookup implementation? This matters because a simulator could correctly draw the curve and still import a different command response while claiming exact firmware behavior.

### Method and scope

The script below checks the checkout commit and byte-compares its three source files against the committed blobs. It extracts the pinned quadratic Bézier helper, throttle lookup, scaling/clamping helpers and the throttle-initialization portion of `initRcProcessing`. It retains the original source notice in the generated C file. It supplies a minimal rate structure and the explicitly declared 12-node/1000–2000 PWM constants, compiles a host executable, sets round-to-nearest, and runs 14 selected configurations/inputs twice.

This is an extraction experiment, not an independent implementation of the same formula. Its purpose is to retain observations from the pinned source path for later differential tests. It omits receiver normalization, input smoothing, other RC processing, PID, mixers, ESC protocols, target firmware flags beyond stated constants, physical hardware and OpenRC. Compiler/architecture and floating/integer rounding remain part of the result identity. Repetition establishes deterministic output on this host, not 14 separate acceptance-test passes or cross-target bitwise equivalence.

### Selected observations

| Mid / hover / expo | Input | Extracted output PWM | Normalized output | Why it matters |
| --- | --- | --- | --- | --- |
| 30 / 70 / 0 | 0.30 | 1663 | 0.663 | The continuous curve's defining point would be 0.70; the default coarse table/interpolation does not retain that point exactly. |
| 50 / 40 / 0 | 0.50 | 1409 | 0.409 | Even zero expo does not make an arbitrary mid/hover configuration the identity curve, and midpoint lookup interpolation differs from continuous 0.40. |
| 50 / 50 / 0 | 0.75 | 1749 | 0.749 | Integer table/interpolation introduces a one-PWM-unit difference from the ideal linear 0.75 in this case. |
| 50 / 50 / 50 | 0.25 | 1311 | 0.311 | Nonzero expo has its own quantized output; a curve plot is not sufficient validation. |

These are research inputs, not suggested racer settings. The full result records all 14 evaluations below.

### Reproduction

Use a local checkout of the exact BF commit and a C compiler. Save the complete Python block below as `run_throttle_source_probe.py`, then run:

```sh
python3 run_throttle_source_probe.py /absolute/path/to/betaflight /absolute/path/to/probe-output
```

The script refuses a different HEAD or edited input file. Generated C contains upstream GPL code with its notice; preserve the applicable license when redistributing that generated source. The handoff embeds only the extraction script and observations, not a source-code port into the simulator.

### Complete extraction script

```python
#!/usr/bin/env python3
"""Extract and execute a narrowly scoped, pinned Betaflight throttle path.

This is research infrastructure, not an OpenRC importer or firmware build.
Requires a local checkout at the exact pin, a C compiler, and Python 3.
Generated C contains upstream GPL code; keep its original notice.
"""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

PIN = "e0b7bb01b17b21351057e9ead2d1ab39dd44fa16"


def extract_function(source, signature):
    start = source.index(signature)
    body = source.index("{", start)
    depth = 0
    for pos in range(body, len(source)):
        if source[pos] == "{":
            depth += 1
        elif source[pos] == "}":
            depth -= 1
            if depth == 0:
                return source[start:pos + 1]
    raise ValueError("Unbalanced function: " + signature)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("checkout", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    root = args.checkout.resolve()
    commit = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True
    ).strip()
    if commit != PIN:
        raise SystemExit("Unexpected source commit: " + commit)
    paths = [
        "src/main/fc/rc.c", "src/main/common/maths.c",
        "src/main/common/maths.h",
    ]
    sources = {}
    for path in paths:
        committed = subprocess.check_output(
            ["git", "-C", str(root), "show", PIN + ":" + path]
        )
        local = (root / path).read_bytes()
        if local != committed:
            raise SystemExit("Modified source: " + path)
        sources[path] = local.decode()
    rc = sources[paths[0]]
    maths = sources[paths[1]]
    header = sources[paths[2]]
    init_start = rc.index("    float thrMid", rc.index("void initRcProcessing"))
    init_end = rc.index("    switch (currentControlRateProfile->rates_type)", init_start)
    init = rc[init_start:init_end]
    notice = rc[:rc.index("*/") + 2]
    preamble = """
#include <stdint.h>
#include <stdio.h>
#include <math.h>
#include <fenv.h>
#define PWM_RANGE_MIN 1000
#define PWM_RANGE_MAX 2000
#define PWM_RANGE 1000
#define THROTTLE_LOOKUP_LENGTH 12
typedef struct { uint8_t thrMid8, thrExpo8, thrHover8; } rate_t;
static rate_t configuration;
static const rate_t *currentControlRateProfile = &configuration;
static int16_t lookupThrottleRC[THROTTLE_LOOKUP_LENGTH];
"""
    functions = [
        extract_function(header, "static inline float constrainf("),
        extract_function(maths, "int scaleRange("),
        extract_function(maths, "float scaleRangef("),
        extract_function(rc, "static int16_t rcLookupThrottle("),
        extract_function(rc, "static float quadraticBezier("),
        "static void init_throttle(void) {\n" + init + "}\n",
    ]
    cases = [
        (50, 50, 0, 0), (50, 50, 0, 250), (50, 50, 0, 500),
        (50, 50, 0, 750), (50, 50, 0, 1000),
        (30, 70, 0, 0), (30, 70, 0, 300), (30, 70, 0, 1000),
        (50, 40, 0, 250), (50, 40, 0, 500), (50, 40, 0, 750),
        (50, 50, 50, 250), (50, 50, 50, 500), (50, 50, 50, 750),
    ]
    statements = ["int main(void) {", "fesetround(FE_TONEAREST);"]
    for mid, hover, expo, command in cases:
        statements.extend([
            f"configuration = (rate_t){{{mid}, {expo}, {hover}}};",
            "init_throttle();",
            f'printf("{mid},{hover},{expo},{command},%d\\n", rcLookupThrottle({command}));',
        ])
    statements.extend(["return 0;", "}"])
    c_source = notice + "\n" + preamble + "\n".join(functions + statements) + "\n"
    args.output.mkdir(parents=True, exist_ok=True)
    c_path = args.output / "throttle_source_probe.c"
    binary = args.output / "throttle_source_probe"
    c_path.write_text(c_source)
    flags = ["-std=c11", "-O0", "-fno-fast-math", "-ffp-contract=off"]
    subprocess.run(["cc", *flags, str(c_path), "-lm", "-o", str(binary)], check=True)
    raw = subprocess.check_output([str(binary)], text=True)
    repeat = subprocess.check_output([str(binary)], text=True)
    if raw != repeat:
        raise SystemExit("Non-reproducible probe output")
    rows = []
    for line in raw.splitlines():
        mid, hover, expo, command, pwm = map(int, line.split(","))
        rows.append({
            "thr_mid": mid, "thr_hover": hover, "thr_expo": expo,
            "normalized_input": command / 1000,
            "firmware_path_pwm": pwm, "normalized_output": (pwm - 1000) / 1000,
        })
    report = {
        "scope": "Pinned extracted throttle functions and initializer only; not full firmware, receiver path, OpenRC, or hardware",
        "firmware": "Betaflight 2026.6.2",
        "commit": commit,
        "compiler": subprocess.check_output(["cc", "--version"], text=True).splitlines()[0],
        "compiler_flags": flags,
        "rounding_mode": "FE_TONEAREST",
        "assumptions": {
            "THROTTLE_LOOKUP_LENGTH": 12, "PWM_RANGE_MIN": 1000,
            "PWM_RANGE_MAX": 2000, "input_to_lookup_range": [0, 1000],
        },
        "source_sha256": {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in paths},
        "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "generated_c_sha256": hashlib.sha256(c_source.encode()).hexdigest(),
        "repeat_identical": True,
        "evaluations": len(rows),
        "rows": rows,
    }
    report_path = args.output / "throttle_probe_results.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"report": str(report_path), "evaluations": len(rows),
                      "repeat_identical": True, "rows": rows}, indent=2))


if __name__ == "__main__":
    main()
```

### Complete observed result

```json
{
  "scope": "Pinned extracted throttle functions and initializer only; not full firmware, receiver path, OpenRC, or hardware",
  "firmware": "Betaflight 2026.6.2",
  "commit": "e0b7bb01b17b21351057e9ead2d1ab39dd44fa16",
  "compiler": "cc (Debian 14.2.0-19) 14.2.0",
  "compiler_flags": [
    "-std=c11",
    "-O0",
    "-fno-fast-math",
    "-ffp-contract=off"
  ],
  "rounding_mode": "FE_TONEAREST",
  "assumptions": {
    "THROTTLE_LOOKUP_LENGTH": 12,
    "PWM_RANGE_MIN": 1000,
    "PWM_RANGE_MAX": 2000,
    "input_to_lookup_range": [
      0,
      1000
    ]
  },
  "source_sha256": {
    "src/main/fc/rc.c": "2033b72105de21449f0389665cebd47486ab7a53d3174262bd56f52dd9a96dee",
    "src/main/common/maths.c": "c5439f80fde7510d900188d1cac8f78433120c2537211507ebfc4f94512cdfd8",
    "src/main/common/maths.h": "f36a91f29147747dc11aed4400ac6dde74e82a89447185961a35e205cec8fa0a"
  },
  "script_sha256": "0a6f96ba21eeb24e8237a7ae133a3abca1fddce846f24121f9e8e2761e6cf977",
  "generated_c_sha256": "dea24c15a94902d217804d5149e0916bcf69c28526267ee6bf0e8143b8abaaab",
  "repeat_identical": true,
  "evaluations": 14,
  "rows": [
    {
      "thr_mid": 50,
      "thr_hover": 50,
      "thr_expo": 0,
      "normalized_input": 0.0,
      "firmware_path_pwm": 1000,
      "normalized_output": 0.0
    },
    {
      "thr_mid": 50,
      "thr_hover": 50,
      "thr_expo": 0,
      "normalized_input": 0.25,
      "firmware_path_pwm": 1250,
      "normalized_output": 0.25
    },
    {
      "thr_mid": 50,
      "thr_hover": 50,
      "thr_expo": 0,
      "normalized_input": 0.5,
      "firmware_path_pwm": 1500,
      "normalized_output": 0.5
    },
    {
      "thr_mid": 50,
      "thr_hover": 50,
      "thr_expo": 0,
      "normalized_input": 0.75,
      "firmware_path_pwm": 1749,
      "normalized_output": 0.749
    },
    {
      "thr_mid": 50,
      "thr_hover": 50,
      "thr_expo": 0,
      "normalized_input": 1.0,
      "firmware_path_pwm": 2000,
      "normalized_output": 1.0
    },
    {
      "thr_mid": 30,
      "thr_hover": 70,
      "thr_expo": 0,
      "normalized_input": 0.0,
      "firmware_path_pwm": 1000,
      "normalized_output": 0.0
    },
    {
      "thr_mid": 30,
      "thr_hover": 70,
      "thr_expo": 0,
      "normalized_input": 0.3,
      "firmware_path_pwm": 1663,
      "normalized_output": 0.663
    },
    {
      "thr_mid": 30,
      "thr_hover": 70,
      "thr_expo": 0,
      "normalized_input": 1.0,
      "firmware_path_pwm": 2000,
      "normalized_output": 1.0
    },
    {
      "thr_mid": 50,
      "thr_hover": 40,
      "thr_expo": 0,
      "normalized_input": 0.25,
      "firmware_path_pwm": 1199,
      "normalized_output": 0.199
    },
    {
      "thr_mid": 50,
      "thr_hover": 40,
      "thr_expo": 0,
      "normalized_input": 0.5,
      "firmware_path_pwm": 1409,
      "normalized_output": 0.409
    },
    {
      "thr_mid": 50,
      "thr_hover": 40,
      "thr_expo": 0,
      "normalized_input": 0.75,
      "firmware_path_pwm": 1700,
      "normalized_output": 0.7
    },
    {
      "thr_mid": 50,
      "thr_hover": 50,
      "thr_expo": 50,
      "normalized_input": 0.25,
      "firmware_path_pwm": 1311,
      "normalized_output": 0.311
    },
    {
      "thr_mid": 50,
      "thr_hover": 50,
      "thr_expo": 50,
      "normalized_input": 0.5,
      "firmware_path_pwm": 1500,
      "normalized_output": 0.5
    },
    {
      "thr_mid": 50,
      "thr_hover": 50,
      "thr_expo": 50,
      "normalized_input": 0.75,
      "firmware_path_pwm": 1688,
      "normalized_output": 0.688
    }
  ]
}
```

## 4. Current source-file integrity ledger

These are the 50 distinct primary files referenced by current-commit blob links in 07. SHA-256 identifies the local source bytes read. Multiple anchored claims can refer to one file; 177 links do not mean 177 independent sources.

| Repository / file | SHA-256 |
| --- | --- |
| betaflight/betaflight/src/main/cli/cli.c | `0b924cff182fdc53df75cb9661bf3fe6b193c803e68d1efca663f5dd72a3048b` |
| betaflight/betaflight/src/main/cli/settings.c | `80e948f5e3d30234d6e1cd51bc1642a896791a509e6bdd7ae3133ac6e0644804` |
| betaflight/betaflight/src/main/config/config.c | `8b0dc5f6dd5ea8b094dac215209b1084d09cb941cd6e5e3e11767959bd91dbb7` |
| betaflight/betaflight/src/main/drivers/dshot.c | `df51bb3099640b80a6b6d519bd9fd6cc7c13f7e01137a1d5c4be50f2a8d6f838` |
| betaflight/betaflight/src/main/fc/controlrate_profile.c | `81885ec3ae55e5dbfc7f50bd27fec4b9e67ec63002dae34e7aba204dcb80174e` |
| betaflight/betaflight/src/main/fc/core.c | `4b01746691507f181007d6fefc26df1e26aeef62fd41ad402116f7f8651e60e9` |
| betaflight/betaflight/src/main/fc/rc.c | `2033b72105de21449f0389665cebd47486ab7a53d3174262bd56f52dd9a96dee` |
| betaflight/betaflight/src/main/fc/rc_controls.c | `895ebe495242cce81f5952166e4f23c9a0dc938045bf7de1f74b3fdda6582ae6` |
| betaflight/betaflight/src/main/fc/rc_controls.h | `0245d103e0ced0e05e6085bc0fad2dbe9bd116ceb97b8b8095f66cba15af46a1` |
| betaflight/betaflight/src/main/fc/rc_modes.c | `ceb3c9d32e86cc410974373957bc0765d457dea55dac4761cdf1419baed05e84` |
| betaflight/betaflight/src/main/flight/dyn_notch_filter.c | `ec9c5b0f5ecdec8bee32d6325ec3db20848c33bcfba58cf29fb720f85521e838` |
| betaflight/betaflight/src/main/flight/dyn_notch_filter.h | `c27e7c786879e4636e30177a0380175405f134c3487b14c53f6bf9f0ceed673e` |
| betaflight/betaflight/src/main/flight/failsafe.c | `bc0b937aca7525c2210b59915d15d25ac37878b1c8fecbc91a98e51bc1a8f375` |
| betaflight/betaflight/src/main/flight/mixer.c | `893fb2cfc032bb91caa2a60877e961befdb0a82546c462879f6a99e19a11b4bd` |
| betaflight/betaflight/src/main/flight/mixer_init.c | `0b080d762403ca067fc4c5728d9dd5651a68311bcc1407f2ade9a6cf278d8418` |
| betaflight/betaflight/src/main/flight/pid.c | `d1065b12de3936c8bbc0385e8fee81928bb7f08779f3d0f915ab99f69b75e013` |
| betaflight/betaflight/src/main/flight/pid.h | `89653c0f3cf9ec900f2367ec0ef0a46b1fc0b5b52d9551c0378c36590156980f` |
| betaflight/betaflight/src/main/flight/pid_init.c | `327b0744fcf60cbb9bd1b5ec192155272ada21030b0a3d3b1d2d8939ab02fc4d` |
| betaflight/betaflight/src/main/flight/rpm_filter.c | `0e6ffbd6af54916b7a3284c83e6c36ea6d71d15726310ba20023a6dc7d4a6bb3` |
| betaflight/betaflight/src/main/pg/dyn_notch.c | `a0278780dbf74ca6107bcba253d02e077c21ef3bca8a2002c139d5836fbeba79` |
| betaflight/betaflight/src/main/pg/motor.c | `4ef6a78004124a6da30dfff6640c294dab243ee353d6601228efa5cd23135f40` |
| betaflight/betaflight/src/main/pg/motor.h | `9c376f0c51efb9da682ebc7afa8ba3052936ea8dbf943c0063f5a5173ae7b4f1` |
| betaflight/betaflight/src/main/pg/rpm_filter.c | `59b2a155e02fe684ca0119746ff319279545838971582b0f8bac9a994d57f3d9` |
| betaflight/betaflight/src/main/pg/rx.c | `81cc6dcfc7da7d7b65fb968cf566f0ec91d8dd0c519dfaed90f1b33884d6b104` |
| betaflight/betaflight/src/main/rx/rx.c | `f87dcb30178daa98ae400ae62221fa690be6732b3710c99a8e2fb7fa2751199e` |
| betaflight/betaflight/src/main/sensors/battery.h | `0b732d1f443588796ab9fabf30f1a4ca4e20fcfa1bf89c664a21b0e018a2593c` |
| betaflight/betaflight/src/main/sensors/boardalignment.c | `5da2bc630bd078eed3635b16fb867ff5d671255d9d4f967045f6dbbe5d915fde` |
| betaflight/betaflight/src/main/sensors/gyro.c | `fc6e8f09db83fad0e324949ebe0be2ce048f3767326bcf37761a0d7841d1e7d5` |
| betaflight/betaflight/src/main/sensors/gyro.h | `5c21fd0b81f9811bef345645086b5acb8ff8041bec8052130ef4d5194f00795d` |
| betaflight/betaflight/src/main/sensors/gyro_init.c | `2014b0b41b197c37959bf347a1e5c43185a2f6c47502f11d136381c0a66cc7f6` |
| betaflight/betaflight/src/main/target/common_pre.h | `fd9c767c92ee317520ae64a0f1e2b1eb73dfa7b2e90bb9cf06e0465944e5d1ae` |
| iNavFlight/inav/src/main/fc/cli.c | `ac89f6fe9b4eae91a05c08c0ea924d869148ee0238723553169aa0096f6c3f6f` |
| iNavFlight/inav/src/main/fc/control_profile.c | `9c329d19c88fadfeef94b5aeaf93df2ea1b7cdfce7b13ea13f42eca272c4c2e1` |
| iNavFlight/inav/src/main/fc/fc_core.c | `8e8fbf83ccc0534e511e27068f94485cbf1306846f5b21bc73d1ff84613f556c` |
| iNavFlight/inav/src/main/fc/fc_tasks.c | `df8fd25a86bb3cb0a6b1861843fa6cb3f04265a268f55710e0bfe31432f3cb01` |
| iNavFlight/inav/src/main/fc/rc_curves.c | `915cc4c5c8d0ec6f0aa5968ce4ce4ce647e5f3179a12484fd77cd482d3fa3639` |
| iNavFlight/inav/src/main/fc/rc_modes.c | `9c8124b171ad97f122a390cde2e26504b6c5f9555a13b1da086204621136b605` |
| iNavFlight/inav/src/main/fc/rc_smoothing.c | `b0c2aebf69d3c7b1a4a440eaf031cb24832cc4d881e414b99d2d365b2c10430a` |
| iNavFlight/inav/src/main/fc/settings.yaml | `5094b7b39049160023345eeefcf17628a02a983b2edea6108d9858d31049d0ce` |
| iNavFlight/inav/src/main/flight/failsafe.c | `7b4996a2a04be35a99968ce860c7e3988b1ac5a688218f98179e2d8f1e589f33` |
| iNavFlight/inav/src/main/flight/gyroanalyse.c | `448d60e06eb5716921557130224d03e225d51c152c01c4291d8bb32a122e6a6d` |
| iNavFlight/inav/src/main/flight/gyroanalyse.h | `321c9310706d328030a4a382a13c0e0346aa8d63c8c33fe091847058ecf629bb` |
| iNavFlight/inav/src/main/flight/mixer.c | `f46cdfe5f1901413322cc1873c78e4eba9e2f1f5937a96e03b7a4891b000cd70` |
| iNavFlight/inav/src/main/flight/pid.c | `daac403afa3fdf2bf19b03163ad41cc56b2b95ae2c56076747ec3573fe2e3931` |
| iNavFlight/inav/src/main/flight/rpm_filter.c | `d6de6aa592784e90095cedcf7217470225c88c534bc1a3e5c446f80a0740d3cd` |
| iNavFlight/inav/src/main/rx/rx.c | `ba2a52ae37c383779e60e8296cda2afe91d229d008187fd27ed4ce40386caccc` |
| iNavFlight/inav/src/main/sensors/battery.c | `a4a7e927028bbd97c606abb7ddfba007073879f41f39b9b0f15a44747eb3e9c1` |
| iNavFlight/inav/src/main/sensors/boardalignment.c | `a411d2e6d4b83ffadeee85343011be0dccdd2fdcfe82432f0c51204e5062821c` |
| iNavFlight/inav/src/main/sensors/esc_sensor.c | `9baa5b77ff8c4c07ec58dbb5a0086480e69d9481dc7beecdc606e4acc741dd10` |
| iNavFlight/inav/src/main/sensors/gyro.c | `fc28ed2ea104aabbbffaf6380b5c816b647aa7560ac09385c57628ac9b1efb80` |

## 5. Review corrections and remaining qualification

The final contract in 08 addresses the reviewed counterexamples:

1. Opening settings while armed holds the old accepted state. It cannot accept a disarm merely by polling a switch. An explicitly labeled reset/apply action prepares and atomically commits a disarmed candidate; ordinary Apply cannot silently reset the flight.
2. A defaults marker with an unknown baseline invalidates affected previous values, selectors and links. Later explicit assignments resolve only their own fields; unknowns do not inherit stale data.
3. An unknown statement blocks even a partial import unless the versioned grammar establishes that its effect is outside the chosen scope.
4. Failure before commit preserves the old session; failure in a postcommit observer keeps the new accepted configuration, pauses it and marks an affected recording incomplete.
5. Every Nyquist statement identifies its sampled stream. A faster sensor path requires its own filtering/decimation evidence and does not arise from RK substeps.
6. If the 240 Hz controller screen fails, conditional P19a can deliver the generic faster-sampled-event protocol before P06 closes. It does not wait for P11, and it does not silently alter the once-per-tick baseline protocol.
7. Profiles initially change through the reset/apply transaction; live switching, extra filter state and advanced control modifiers require separate capability/layout admission.

No full BF/INAV build, hardware tuning, real radio, native OpenRC settings UI, new Godot controller/importer, or physical flight was qualified in this follow-up. The 81 setting cases and 18 integration cases are proposed implementation gates. The selected aircraft's physical calibration and supported flight envelope remain the original M4/DR-40 work.
