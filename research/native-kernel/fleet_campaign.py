#!/usr/bin/env python3
"""Run and validate the full native fleet as independently checked per-aircraft shards.

The campaign is software-equivalence evidence, not physical validation or a performance test.
It uses the installed verified library and fails if any source, binary or engine changes.
"""
from __future__ import annotations

import argparse
import asyncio
import fnmatch
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import plistlib
import re
import signal
import subprocess
import struct
import sys
from typing import Any

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RUNNER = HERE / "run.py"
FLEET = HERE / "fleet.gd"
CHECKED = ROOT / "tools/godot/run_checked.py"
DESCRIPTOR = ROOT / "app/native/kernel/openrc_native_kernel.gdextension"
RECEIPT = ROOT / "app/native/kernel/build-receipt.json"
MIN_WARMUP = 600
MIN_SAMPLES = 2400
MAX_JOBS = 4
KEY_FIELDS = ("aircraft", "vehicle", "battery", "case", "weather", "soft_hull")
HEX64 = re.compile(r"[0-9a-f]{64}\Z")
# Independently pin the named source observations. Runway live-configuration
# hashes reflect Linux beta2 observations after the v4 aero-law and collision-world
# changes, including the AV-17-R4 Avanti update; native-flight verification remains required.
RUNWAY_START_REASON = "reset failed: runway start: idle support pose unresolved: bounded line search found no feasible descent step"
# Historical Avanti v4 observation before AV-17-R4; not accepted for current data.
AVANTI_RUNWAY_V4_HISTORICAL = {
    "aircraft_sha256": "048305d4000829fbcf4b1854bd0a89e506b7b01a6ed4a64f1c758519716dbbbd",
    "config_sha256": {True: "41f3139037fdd2fd220bc67643467e31d2c75e9482d3aa18869573deeb783e5d",
                      False: "0f8bd1e3d440b1bb57cb084205d059093cc6ef53594c932f9a752cf6cea1428d"},
    "live_config_sha256": {True: "9b6bf87499957e5b3cab7b5f43ef04c660b324341c91ee3a15108a4234e61b03",
                           False: "f3aa4fbbf22f522341b09c77534f206bfc46ee32e8d354ac34a0edafb83a7632"},
}
RUNWAY_START_CASES = {
    "sebart-avanti-s-a200-p100rx": {
        "weather": "crosswind", "batteries": {"ideal": {"default_battery": True,
        "aircraft_sha256": "77674df18312f6235352a28a797c497013ef18451a41eb0141e3f16dffd220b9",
        "frame_sha256": "0de0b838cd3db1f12fa815852333a9204b7f2d8a0bf77ab98c3acf457f652014",
        "outcome_sha256": "6daae9ec4959442f88cac3cb61b87cf9595c2d5ea699f41eecbade6e467f1d06",
        "live_config_sha256": {True: "608ea5ba0dec238cda690638be83e4ca6171de957bd62c55392cd4916e407e12",
                               False: "15f9d0f9f73c36a3653a542dbfac293d445ec5ab5ad615361f533c73e57d303d"},
        "config_sha256": {True: "538382d692b329fbf227c0f54fcbb239ff8667880dea650b2395add0a16cf2bc",
                          False: "847a2023caa0b2ba18bbb43178ca786643e25b094884d0df971fc6439300d565"}}}},
    "p51d-mustang-120": {
        "weather": "crosswind", "batteries": {"ideal": {"default_battery": True,
        "aircraft_sha256": "45a9b854007e4ceed22f4c8ad8bcff166904ef3bb5c23c87f308174e6b31489c",
        "frame_sha256": "51cd43739d1a48e281f34c4d13caed9bd2f98a90129074db722b43bd037e94e7",
        "outcome_sha256": "81c03ca68d0e52dad256ff6106751c0c82edda7decc4047a74ba95c70ee59249",
        "live_config_sha256": {True: "59f263f57edd0b2ec2295c0516cc0bebda4aca1c92bed0ea9bcfb7c49d73ddf8",
                               False: "99bb750afd144ff53351cb1f385956b81ad19b43b7e74b8dad8f301fdbc4cfbb"},
        "config_sha256": {True: "ebca46e332e77ae231896e9e248845c0e885ddacc04e0f41e674bf6dc32a7695",
                          False: "a06be6a7cf1f178d6b2d2ae0b4cbe16994314c1a2c9d9b466283a78b1fbf54ef"}}}},
    "turbo-lumber-evolution": {"weather": "crosswind", "batteries": {
        "pack": {"default_battery": True,
                 "aircraft_sha256": "63c9fe2d2c89e88eb1d3248115716356a92994ae25e105db3709b364da0dcc53",
                 "frame_sha256": "027e61fc3c4084f20fa738c360d6f0df7e51c7bae8d7a946f982107dae5ae04c",
                 "outcome_sha256": "469d10021d52ed3a5e0b6cb57f3a22ec1a9e755dc53acd227cb4dbea0b5e92a9",
                 "live_config_sha256": {True: "0f9ad0647542f3f9ef12796d9fb37574fc4d81f6ef29b822bc1c5f8439d9d7c8",
                                        False: "24e28bc0b02491b597c3ab873bca4b25998434c0652a979833ceebc320bb4807"},
                 "config_sha256": {True: "8880fb3b68a8cf3b16db29341d7342775b1f084c118a958dee78f20a6151e1cf",
                                   False: "a09fd32a2840316885d8f7e88882f4d8e4eace8f0d02a992e01825af8e5affa9"}},
        "ideal": {"default_battery": False,
                  "aircraft_sha256": "3d47e8c4c40665a0b1e2123c8eb1c8919697ca5b2f931472b02e85897d8bc46c",
                  "frame_sha256": "81e991aaadd6862d2fe7ef06ccfe0aa398d48d8c2eff444b4784aa5cd06120cb",
                  "outcome_sha256": "b936ff0ac0487770f2cd26f4bb6c89facf55008a23d272647ecb9dded68f789e",
                  "live_config_sha256": {True: "9a8e7a58a156a46dd9280b7d7b441ed4fe16e77c5b5f8a8e88e488e7cb80d7cf",
                                         False: "3eef9a988d3c6e0c7718145e2527cceb186a6cf79d81c83470bee94c82a522c0"},
                  "config_sha256": {True: "6c91ea8e73d84b0a9a4386431dbd8b06f9bdf89fa15c016baf579f0e381b031d",
                                    False: "7504b456498aca6db0771141d1d8a2ec3cc145984c28ec9f723604d4fd1991e6"}}}},
}
TRIM_START_REASON = "reset failed: trim: reference-speed trim already requires more than the requested throttle"
TRIM_START_CASES = {
    "skywalker-x8": {"weather": "hot-high", "batteries": {"ideal": {"default_battery": False,
        "aircraft_sha256": "9aa8e517d49779314ef48940a7695296d8018c6e474748616e43dfa5e41ab830",
        "frame_sha256": "399481be84b4a9bafea653c486b13ab2437073dbb75248fa5f49d8623ed99d01",
        "outcome_sha256": "4d159113222bfeb85fbe717cc2393ee8a6a85b7ce5ac1791c4eade5e3dd6de41",
        "live_config_sha256": {True: "4a7fb3ea46ad3a01017b3c79b859bdc93e60968ab8a1f3abae59d8b367b84330",
                               False: "7ccb66b2850f8181fcab6a7f22da55c85f5cc518bf26b5cf19e1def685d46337"},
        "config_sha256": {True: "c80654d5981a9482218352d937839aceaccf32ae14f1e160817c46f20b624edb",
                          False: "b69b5948fbb8c78e32350796dd734b67cb6cdfe54af512b01790f2950a5bdcb5"}}}},
}
# Independent expectations for the observed source-domain boundaries. A report
# cannot choose its own RK phase, rejection ordinal, or four-stroke feed factor.
# FS64V hashes identify the real typed trial and context captured on 2026-10-29
# at tick 805 on both backends and hull settings for the stock ideal/gusty runway tape.
RUNTIME_CASES = {
    "stik-glow-61fx-2t": {"tick": 873, "stage_fraction": 1.0, "rejected_stage_calls": 4},
    "stik-glow-55ax-2t": {"tick": 801, "stage_fraction": 1.0, "rejected_stage_calls": 4},
    "stik-glow-fs64v-4t": {"tick": 805, "stage_fraction": 0.5, "rejected_stage_calls": 2, "feed_factor": 0.0,
                            "aircraft_sha256": "47c0972622f328dbeb62c64fcde0f13057414c18a026cd9c1e74499096b885d8",
                            "trial_sha256": "e064ab046fc2119231564b6b6c125fc256c752ebb2fb04d557d7ee7bef0e16c8",
                            "context_sha256": "e7cc667d8cf303f497701c1079db0c5936303c31da51e236791b13f238cc61b6",
                            "cause_bytes_hex": "00000000000000000000000000000000acf7f5a16f0d90bf442c89836c0a903f"
                                               "fb702e7c620d903fd22f068cdc4b333f85580189a0cd453f"},
}
RUNTIME_CODE = "glow_stopped_reverse_drive"
RUNTIME_FAULT = "step rejected: RK joint stage evaluation is nonfinite or malformed"
TERMINAL_TICK = 1640
TERMINAL_CODE = "scenery_terminal_impact"
TERMINAL_AIRCRAFT = "7e3bfa65db9c259133345469c8d4846c1716421b4e8d8b30ad66860549f74b82"
TERMINAL_WORLD = "ba184dbc8864dae651ca914ae14b0b1fd36f65d1cf5c52f80a08d0c188c84a6d"
TERMINAL_NATIVE_IDENTITY = {
    "backend": "native", "abi_version": 2, "backend_version": "openrc-native-kernel-stage-v2",
    "binary_sha256": "d023a8758404ad2b95949214af92e6f888f91fb32977b61e0db5ad4220178fc1",
    "source_sha256": "14c124bba22f72760de4deb3c69be5d21b64590c83b2adb4231a7608b4572f03",
    "lock_sha256": "850f6cf3ffb8cdad0312ddc4db12804c7b753a353132056c86934016e244fa34",
}
TERMINAL_PREFIX = "faeccb6864cda465389cdedc6de5301588b5fd61bebd7fc48a258d8378a0881e"
TERMINAL_VIEW_PREFIX = "133d124064efe08f10bc0ed6a9664a7541ba1c22a137ca673357a7a147365365"
# Canonical Python JSON of the pinned typed view decoded with the full-precision
# projection used by oracle.gd; reduced-precision diagnostic JSON is different.
TERMINAL_VIEW_JSON = "3defb1aa5afc96af1ddfa09c3b814d8fcbf94dcc1288d72986058867fd987d4d"
TERMINAL_IDENTITIES = {
    "initial_frame": "1be46da07149a21cecff884cdc0947b35f2db51fc952a5287b63df24317a8eb3",
    "preceding_frame": "8cff80befa31c0859e2f5e15921a5b066fbe4c8505a5fda89416e86c7e6e8e05",
    "terminal_frame": "8b2147bde207f4dc6614c8ee3e2642bcd6319d9cb9a9287da74689427ee3143f",
    "terminal_view": "8ea0476661dd1495bea9ab2de21d1677683d8f31644c7af79ac0849397e27d15",
    "impact": "664217d2be2b738472a430551fe6029b5b657ae1a8039f5d77f9ed889ddc00a9",
    "contact_state": "783b983537310e450a3a6a5306af8d1884aeea6604bd437b5eaa4888e5dfb472",
    "contact_event": "d5d5a83aa26c443750850f444486a58f9db4bacf237ed9f5de920ac5d99d0360",
}
TERMINAL_CONFIGS = {
    True: {"physical_configuration": "03d4d8e07c7143efdea227bf6ff52da300b75f3f9351d279870e4bdccc31beb4",
           "reference_live_configuration": "75cb2961cc260ebad73d99eed3addfa92e5affa5306a0b073db60c1724c947c3",
           "native_live_configuration": "1e0a64f3594d50f7a002efd857da0ae6df374098c1dd2faea2b6d46d4327f6ce"},
    False: {"physical_configuration": "bfd3a1ad0ab3bbe40fbe89cedf826e610158b3e0d87b157f5a3ec92befabf18e",
            "reference_live_configuration": "9acfe61176ca2bd2fb80fb941a564ad69a2c03150494e333e561d299c89690fa",
            "native_live_configuration": "04e7db73eac1164432118795ccd6cc75c7eaaade443a33f76c682317f68d61aa"},
}


class CampaignError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise CampaignError(message)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def load_runner() -> Any:
    spec = importlib.util.spec_from_file_location("nk3_campaign_runner", RUNNER)
    if spec is None or spec.loader is None:
        raise CampaignError("cannot load the native oracle runner")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_build() -> Any:
    spec = importlib.util.spec_from_file_location("nk3_campaign_build", HERE / "build.py")
    if spec is None or spec.loader is None:
        raise CampaignError("cannot load the native build identity")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_macos_builder() -> Any:
    spec = importlib.util.spec_from_file_location("nk3_campaign_macos_builder", HERE / "build_macos.py")
    require(spec is not None and spec.loader is not None, "cannot load Mac builder")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def macos_system_version() -> dict[str, Any]:
    with Path("/System/Library/CoreServices/SystemVersion.plist").open("rb") as stream:
        return plistlib.load(stream)


def snapshot(context: dict[str, Any] | None = None) -> dict[str, Any]:
    """Pin the installed binary, source roster and declaration before and after all work."""
    if context is not None:
        return macos_snapshot(context)
    runner = load_runner()
    build = load_build()
    receipt_data = json.loads(RECEIPT.read_text(encoding="utf-8"))
    receipt = receipt_data["platforms"]["linux"]
    binary = runner.selected_binary(DESCRIPTOR)
    require(binary.is_relative_to((ROOT / "app/native/kernel").resolve()), "installed binary path is invalid")
    references = {name: sha256(ROOT / name) for name in runner.reference_source_paths()}
    binary_hash = sha256(binary)
    require(receipt.get("mutant", False) is False and receipt.get("abi_version") == 2
            and receipt.get("backend") == "native" and receipt.get("platform") == "linux"
            and receipt.get("architecture") == "x86_64"
            and "-DNK_MUTATION=1" not in receipt.get("cxxflags_appended", []),
            "installed receipt is not a normal ABI 2 build")
    require(receipt.get("binary_sha256") == binary_hash, "installed binary differs from its receipt")
    require(receipt.get("reference_sources_sha256", receipt.get("mirrored_sources")) == references,
            "current reference sources differ from the installed receipt")
    require(receipt.get("builder_sha256") == sha256(HERE / "build.py"),
            "current builder differs from the installed receipt")
    engine_hash = sha256(runner.GODOT)
    require(receipt.get("engine_sha256") == engine_hash, "engine differs from the installed receipt")
    require(receipt.get("source_sha256") == build.source_digest()
            and receipt.get("lock_sha256") == sha256(build.locked.LOCK_PATH),
            "native source or toolchain lock differs from the installed receipt")
    return {
        "binary_sha256": binary_hash,
        "engine_sha256": engine_hash,
        "descriptor_sha256": sha256(DESCRIPTOR),
        "receipt_sha256": sha256(RECEIPT),
        "receipt": receipt,
        "reference_sources": references,
        "fleet_sha256": sha256(FLEET),
        "campaign_sha256": sha256(Path(__file__).resolve()),
    }


def macos_snapshot(context: dict[str, Any]) -> dict[str, Any]:
    """Bind the selected Mac source project and its exact experimental installation."""
    runner = load_runner()
    build = load_build()
    require(runner.host_platform_key() == "macos.arm64", "Mac fleet requires a native ARM64 process")
    project = Path(context["project"]).resolve()
    engine = Path(context["godot"]).resolve()
    tool_root = Path(context["tool_root"]).resolve()
    qualification_root = Path(context["qualification_root"]).resolve()
    require(project.is_dir() and (project / "project.godot").is_file(), "project is missing")
    require(tool_root.is_relative_to((ROOT / "tmp").resolve()) and tool_root != (ROOT / "tmp").resolve(),
            "Mac tool root must be inside tmp/")
    require(qualification_root.is_relative_to((ROOT / "tmp").resolve()) and qualification_root != (ROOT / "tmp").resolve()
            and qualification_root.is_dir(), "Mac qualification root must be an existing directory inside tmp/")
    proof = runner.validate_project(project)
    require(isinstance(proof, dict) and (project == (ROOT / "app").resolve() or bool(proof)),
            "prepared project inventory proof is missing")
    native = project / "native/kernel"
    require(not (project / "native").is_symlink() and not native.is_symlink()
            and native.resolve() == project / "native/kernel", "native project directory is symlinked")
    descriptor = native / "openrc_native_kernel_macos.gdextension"
    receipt_file = native / "build-receipt-macos.json"
    library = native / "libopenrc_native_kernel.dylib"
    for path in (descriptor, receipt_file, library, engine):
        require(not path.is_symlink() and path.is_file(), f"missing regular Mac artifact: {path}")
    mac_builder = load_macos_builder()
    require(descriptor.read_text(encoding="utf-8") == mac_builder.SOURCE_DESCRIPTOR,
            "Mac descriptor differs from the source loader contract")
    binary = runner.selected_binary(descriptor, project)
    require(binary == library.resolve(), "Mac descriptor does not select the project dylib")
    envelope = json.loads(receipt_file.read_text(encoding="utf-8"))
    require(isinstance(envelope, dict) and envelope.get("format") == build.RECEIPT_FORMAT
            and envelope.get("backend") == "native" and envelope.get("backend_version") == build.BACKEND_VERSION
            and envelope.get("abi_version") == build.ABI_VERSION and isinstance(envelope.get("platforms"), dict),
            "invalid Mac receipt envelope")
    receipt = envelope["platforms"].get("macos")
    require(isinstance(receipt, dict) and receipt.get("platform") == "macos" and receipt.get("architecture") == "arm64"
            and receipt.get("backend") == "native" and receipt.get("backend_version") == build.BACKEND_VERSION
            and receipt.get("abi_version") == build.ABI_VERSION
            and receipt.get("qualification_scope") == "macos-arm64-fixed-wing-experimental-v1"
            and receipt.get("mutant", False) is False
            and "-DNK_MUTATION=1" not in receipt.get("cxxflags_appended", []), "invalid experimental Mac receipt")
    references = {name: sha256(runner.project_file(ROOT / name, project)) for name in runner.reference_source_paths()}
    binary_hash, engine_hash = sha256(binary), sha256(engine)
    require(receipt.get("binary_sha256") == binary_hash and receipt.get("engine_sha256") == engine_hash
            and isinstance(receipt.get("engine"), dict) and receipt["engine"].get("sha256") == engine_hash
            and receipt["engine"].get("version") == receipt.get("engine_cli_version")
            and receipt.get("engine_version") == mac_builder._engine_display(receipt["engine"]["version"])
            and isinstance(receipt["engine"].get("architectures"), list)
            and "arm64" in receipt["engine"]["architectures"]
            and receipt.get("mirrored_sources") == references and receipt.get("source_sha256") == build.source_digest()
            and receipt.get("lock_sha256") == sha256(build.locked.LOCK_PATH)
            and receipt.get("builder_sha256") == sha256(HERE / "build_macos.py")
            and receipt.get("linux_builder_sha256") == sha256(HERE / "build.py")
            and receipt.get("shared_builder_sha256") == sha256(build.SHARED_BUILDER),
            "Mac engine, binary, sources or build identity differs from the selected project receipt")
    system = macos_system_version()
    require(isinstance(system, dict) and isinstance(receipt.get("toolchain"), dict)
            and receipt["toolchain"].get("os_version") == receipt.get("runtime_os_version")
            and receipt["toolchain"].get("os_build") == receipt.get("runtime_os_build")
            and receipt.get("runtime_os_version") == system.get("ProductVersion")
            and receipt.get("runtime_os_build") == system.get("ProductBuildVersion")
            and isinstance(system.get("ProductVersion"), str) and bool(system["ProductVersion"])
            and isinstance(system.get("ProductBuildVersion"), str) and bool(system["ProductBuildVersion"]),
            "Mac runtime qualification tuple differs from this host")
    harness_names = ["research/native-kernel/" + name for name in (
        "oracle.gd", "stage_oracle.gd", "stage_adapter.gd", "trajectory.gd", "fleet.gd", "propeller_oracle.gd",
        "build.py", "run.py", "build_macos.py")]
    harness_names += ["app/sim/native/" + name for name in (
        "stage_config.gd", "weather_adapter.gd", "native_weather.gd", "native_configuration.gd",
        "electric_stage_adapter.gd", "liquid_stage_adapter.gd", "glow_stage_adapter.gd", "helicopter_stage_adapter.gd",
        "prescribed_stage_adapter.gd")]
    harness_names += ["app/sim/native_stage.gd", "tools/godot/run_checked.py"]
    harness = {name: sha256(runner.project_file(ROOT / name, project)) for name in harness_names}
    return {"platform": "macos", "architecture": "arm64", "project": str(project), "project_inventory": proof,
            "godot": str(engine), "tool_root": str(tool_root), "qualification_root": str(qualification_root),
            "binary_sha256": binary_hash,
            "engine_sha256": engine_hash, "descriptor_sha256": sha256(descriptor), "receipt_sha256": sha256(receipt_file),
            "receipt": receipt, "reference_sources": references, "harness_sources": harness,
            "fleet_sha256": sha256(FLEET), "campaign_sha256": sha256(Path(__file__).resolve())}


def write_manifest_script(path: Path, output: Path) -> None:
    # Query the actual declaration, including its explicit expected-refusal rows.
    # Do not reconstruct the catalog or preset matrix in Python.
    source = '''extends SceneTree

func _initialize() -> void:
    var script: Script = load(FLEET_PATH)
    if script == null:
        printerr("fleet declaration could not be loaded")
        quit(1)
        return
    var fleet: SceneTree = script.new()
    var rows: Array = fleet._fleet_declared_rows()
    var ids: Array[String] = []
    for row: Dictionary in rows:
        if str(row.aircraft) not in ids:
            ids.append(str(row.aircraft))
        if row.get("expected", "flight") == "reference-refusal":
            var reason := ""
            if row.vehicle == "rotorcraft" and row.case == "airborne":
                reason = "reset failed: Helicopter start refused: " + script.HELICOPTER_TRIM_REFUSAL
            elif row.vehicle == "rotorcraft" and row.case == "ground":
                reason = "reset failed: Ground trainer control reference refused: " + script.HELICOPTER_TRIM_REFUSAL
            elif script._fleet_is_trim_boundary(row):
                reason = script.TRIM_START_REFUSAL
            elif row.vehicle == "fixed-wing":
                reason = script.STIK_RUNWAY_REFUSAL
            if reason.is_empty() or not script._fleet_expected_refusal(row,
                    {ok = false, phase = "reset", reason = reason}):
                printerr("refusal declaration lacks an exact source reason")
                fleet.free()
                quit(1)
                return
            row.expected_refusal_reason = reason
        elif row.get("expected", "flight") == "runtime-domain-refusal":
            if script._fleet_runtime_tick(row) < 0:
                printerr("runtime-domain declaration is not one of the bounded rows")
                fleet.free()
                quit(1)
                return
        elif row.get("expected", "flight") == "physical-terminal":
            if script._fleet_terminal_tick(row) < 0:
                printerr("physical-terminal declaration is not one of the observed rows")
                fleet.free()
                quit(1)
                return
    var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
    if file == null:
        printerr("cannot write fleet manifest")
        fleet.free()
        quit(1)
        return
    file.store_string(JSON.stringify({format = "openrc-nk3-fleet-manifest v1", aircraft = ids, rows = rows}))
    file.close()
    fleet.free()
    print("NK3_FLEET_MANIFEST verdict=pass rows=", rows.size())
    quit()
'''
    path.write_text(source.replace("FLEET_PATH", json.dumps(str(FLEET)))
                    .replace("OUTPUT_PATH", json.dumps(str(output))), encoding="utf-8")


def make_manifest(out: Path, context: dict[str, Any] | None = None) -> dict[str, Any]:
    script = out / "manifest.gd"
    output = out / "manifest.json"
    write_manifest_script(script, output)
    script_hash = sha256(script)
    runner = load_runner()
    project = Path(context["project"]) if context is not None else ROOT / "app"
    godot = Path(context["godot"]) if context is not None else runner.GODOT
    command = [sys.executable, str(CHECKED), "--out-dir", str(out / "manifest-checks"),
               "--label", "nk3-fleet-manifest", "--timeout", "120",
               "--require-text", "NK3_FLEET_MANIFEST verdict=pass", "--",
               str(godot), "--headless", "--path", str(project), "--script", str(script)]
    completed = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, check=False)
    (out / "manifest-run.log").write_text(completed.stdout, encoding="utf-8")
    reports = list((out / "manifest-checks").glob("*/report.json"))
    require(completed.returncode == 0 and output.is_file() and len(reports) == 1 and sha256(script) == script_hash,
            "checked fleet manifest generation failed or its script changed")
    checked = json.loads(reports[0].read_text(encoding="utf-8"))
    log = Path(checked.get("log", ""))
    require(checked.get("ok") is True and checked.get("complete") is True and checked.get("reason") == "passed"
            and type(checked.get("process_exit")) is int and checked["process_exit"] == 0
            and type(checked.get("counts", {}).get("error")) is int and checked["counts"]["error"] == 0
            and checked.get("missing_required_text") == [] and log.is_file()
            and sha256(log) == checked.get("log_sha256"), "manifest checked-run evidence is invalid")
    return json.loads(output.read_text(encoding="utf-8"))


def positive_int(value: Any, minimum: int = 1) -> bool:
    return type(value) is int and value >= minimum


def hash_string(value: Any) -> bool:
    return isinstance(value, str) and HEX64.fullmatch(value) is not None


def row_key(row: dict[str, Any]) -> tuple[Any, ...]:
    require(isinstance(row, dict), "fleet row is not a dictionary")
    for key in KEY_FIELDS[:-1]:
        require(isinstance(row.get(key), str) and bool(row[key]), f"invalid fleet row field {key}")
    require(row["vehicle"] in ("fixed-wing", "rotorcraft"), "invalid vehicle family")
    require((row["vehicle"] == "fixed-wing" and type(row.get("soft_hull")) is bool)
            or (row["vehicle"] == "rotorcraft" and "soft_hull" in row and row["soft_hull"] is None),
            "invalid contact selection")
    require(type(row.get("default_battery")) is bool, "missing default battery selection")
    return tuple(row[key] for key in KEY_FIELDS)


def runway_start_boundary(row: dict[str, Any]) -> bool:
    return observed_start_boundary(row, RUNWAY_START_CASES, "runway")


def trim_start_boundary(row: dict[str, Any]) -> bool:
    return observed_start_boundary(row, TRIM_START_CASES, "airborne_half_power")


MOONRUNNER_UNQUALIFIED_REASON = "MoonRunner requalification required: historical X8 evidence is not applicable"


def moonrunner_unqualified(row: dict[str, Any]) -> bool:
    if row.get("aircraft") != "moonrunner-x99" or row.get("vehicle") != "fixed-wing":
        return False
    return ((row.get("battery") == "ideal" and row.get("case") == "airborne_half_power"
             and row.get("weather") == "hot-high")
            or (row.get("battery") == "pack" and row.get("case") == "hand_launch"
                and row.get("weather") == "spatial-crosswind-v1"))


def physical_terminal_boundary(row: dict[str, Any]) -> bool:
    return (row.get("aircraft") == "skywalker-x8" and row.get("vehicle") == "fixed-wing"
            and row.get("battery") == "pack" and row.get("case") == "hand_launch"
            and row.get("weather") == "spatial-crosswind-v1"
            and type(row.get("default_battery")) is bool and row["default_battery"] is True
            and type(row.get("soft_hull")) is bool)


def observed_start_boundary(row: dict[str, Any], cases: dict[str, Any], start: str) -> bool:
    spec = cases.get(row.get("aircraft"))
    battery = spec["batteries"].get(row.get("battery")) if spec else None
    return bool(battery and row.get("vehicle") == "fixed-wing" and row.get("case") == start
                and row.get("weather") == spec["weather"] and type(row.get("soft_hull")) is bool
                and type(row.get("default_battery")) is bool
                and row["default_battery"] is battery["default_battery"])


def manifest_index(manifest: dict[str, Any]) -> tuple[dict[tuple[Any, ...], dict[str, Any]], list[str]]:
    require(isinstance(manifest, dict) and manifest.get("format") == "openrc-nk3-fleet-manifest v1",
            "invalid fleet manifest format")
    rows, aircraft = manifest.get("rows"), manifest.get("aircraft")
    require(isinstance(rows, list) and rows, "empty fleet manifest")
    require(isinstance(aircraft, list) and aircraft and all(isinstance(x, str) and x for x in aircraft)
            and len(set(aircraft)) == len(aircraft), "invalid manifest aircraft list")
    index: dict[tuple[Any, ...], dict[str, Any]] = {}
    encountered: list[str] = []
    for row in rows:
        key = row_key(row)
        require(key not in index, "duplicate manifest row")
        # Classify independently of supplied expectation, report, or horizon.
        require(not moonrunner_unqualified(row) and row.get("expected") != "unqualified",
                MOONRUNNER_UNQUALIFIED_REASON)
        expected = row.get("expected", "flight")
        require(expected in ("flight", "reference-refusal", "runtime-domain-refusal", "physical-terminal"),
                "invalid manifest expectation")
        if runway_start_boundary(row) or trim_start_boundary(row):
            require(expected == "reference-refusal", "observed bounded start row has the wrong expectation")
        if physical_terminal_boundary(row):
            require(expected == "physical-terminal", "observed physical-terminal row has the wrong expectation")
        if expected == "reference-refusal":
            require(isinstance(row.get("expected_refusal_reason"), str) and bool(row["expected_refusal_reason"]),
                    "expected refusal has no exact reason")
            if row["aircraft"] in RUNWAY_START_CASES:
                require(runway_start_boundary(row) and row["expected_refusal_reason"] == RUNWAY_START_REASON,
                        "invalid bounded runway-start declaration")
            if row["aircraft"] in TRIM_START_CASES:
                require(trim_start_boundary(row) and row["expected_refusal_reason"] == TRIM_START_REASON,
                        "invalid bounded trim-start declaration")
        elif expected == "runtime-domain-refusal":
            require(row["vehicle"] == "fixed-wing" and row["aircraft"] in RUNTIME_CASES
                    and row["battery"] == "ideal" and row["case"] == "runway" and row["weather"] == "gusty"
                    and type(row.get("expected_runtime_tick")) is int
                    and row["expected_runtime_tick"] == RUNTIME_CASES[row["aircraft"]]["tick"]
                    and "expected_refusal_reason" not in row, "invalid bounded runtime-domain declaration")
        elif expected == "physical-terminal":
            require(physical_terminal_boundary(row) and type(row.get("expected_terminal_tick")) is int
                    and row["expected_terminal_tick"] == TERMINAL_TICK
                    and "expected_refusal_reason" not in row and "expected_runtime_tick" not in row,
                    "invalid observed physical-terminal declaration")
        else:
            require("expected_refusal_reason" not in row, "flight row has a refusal reason")
        if expected != "physical-terminal":
            require("expected_terminal_tick" not in row, "non-terminal row carries a terminal tick")
        index[key] = row
        if row["aircraft"] not in encountered:
            encountered.append(row["aircraft"])
    require(aircraft == encountered, "manifest aircraft list does not match rows")
    return index, aircraft


def macos_manifest_index(manifest: dict[str, Any]) -> tuple[dict[tuple[Any, ...], dict[str, Any]], list[str]]:
    """Retain the complete declaration, without promoting historical Linux observations."""
    require(isinstance(manifest, dict) and manifest.get("format") == "openrc-nk3-fleet-manifest v1",
            "invalid fleet manifest format")
    rows, aircraft = manifest.get("rows"), manifest.get("aircraft")
    require(isinstance(rows, list) and rows and isinstance(aircraft, list) and aircraft
            and all(isinstance(name, str) and re.fullmatch(r"[a-z0-9][a-z0-9-]*", name) for name in aircraft)
            and len(set(aircraft)) == len(aircraft),
            "invalid or empty fleet declaration")
    index: dict[tuple[Any, ...], dict[str, Any]] = {}
    seen_aircraft: list[str] = []
    for row in rows:
        key = row_key(row)
        require(key not in index, "duplicate manifest row")
        require(row.get("expected", "flight") in
                ("flight", "unqualified", "reference-refusal", "runtime-domain-refusal", "physical-terminal"),
                "invalid manifest expectation")
        if row.get("expected") == "reference-refusal":
            require(isinstance(row.get("expected_refusal_reason"), str) and bool(row["expected_refusal_reason"]),
                    "expected refusal has no declared reason")
        index[key] = row
        if row["aircraft"] not in seen_aircraft:
            seen_aircraft.append(row["aircraft"])
    require(aircraft == seen_aircraft, "manifest aircraft list does not match rows")
    return index, aircraft


def macos_pending_reason(row: dict[str, Any]) -> str:
    """No Linux-pinned observation or previously unqualified row establishes a Mac boundary."""
    if moonrunner_unqualified(row) or row.get("expected") == "unqualified":
        return MOONRUNNER_UNQUALIFIED_REASON
    runtime = (row.get("aircraft") in RUNTIME_CASES and row.get("vehicle") == "fixed-wing"
               and row.get("battery") == "ideal" and row.get("case") == "runway" and row.get("weather") == "gusty")
    if (row.get("expected", "flight") != "flight" or runway_start_boundary(row) or trim_start_boundary(row)
            or physical_terminal_boundary(row) or runtime):
        return "host-specific boundary requires separate Mac qualification"
    return ""


def validate_components(report: dict[str, Any], flights: int, refusals: int, runtime_refusals: int = 0,
                        terminals: int = 0) -> None:
    components = report.get("components")
    require(isinstance(components, dict) and components, "missing oracle comparisons")
    count = 0
    for name, component in components.items():
        require(isinstance(component, dict) and positive_int(component.get("count"))
                and type(component.get("identical")) is int and component["identical"] == component["count"],
                f"non-identical or incomplete oracle comparison {name}")
        count += component["count"]
    require(report.get("total") == {"compared": count, "identical": count, "mismatched": 0},
            "oracle comparison totals differ")
    for name, expected in (("fleet_pair", flights), ("fleet_reference_refusal", refusals),
                           ("fleet_runtime_domain_refusal", runtime_refusals),
                           ("fleet_physical_terminal", terminals)):
        require(components.get(name, {}).get("count", 0) == expected, f"wrong {name} comparison count")


def validate_flight(row: dict[str, Any], warmup: int, samples: int, guard: dict[str, Any]) -> None:
    ticks = warmup + samples
    require(row.get("status") == "pass" and row.get("reason") == ""
            and row.get("fingerprint_equal") is True, "flight row did not pass")
    reference, native = row.get("reference"), row.get("native")
    require(isinstance(reference, dict) and isinstance(native, dict), "missing flight backend results")
    for run, requested in ((reference, "gdscript_reference"), (native, "native")):
        identity, end = run.get("identity"), run.get("end")
        require(run.get("complete") is True and run.get("requested") == requested
                and run.get("actual") == requested and isinstance(identity, dict)
                and identity.get("backend") == requested and run.get("error") == ""
                and run.get("reason") == "", f"{requested} did not complete using its requested backend")
        require(type(run.get("warmup_completed")) is int and run["warmup_completed"] == warmup
                and type(run.get("samples_completed")) is int and run["samples_completed"] == samples
                and type(run.get("fingerprint_boundaries")) is int and run["fingerprint_boundaries"] == ticks + 1,
                f"{requested} has incomplete ticks")
        require(isinstance(end, dict) and type(end.get("tick")) is int and end["tick"] == ticks
                and end.get("fault") == "" and end.get("crashed") is False and end.get("paused") is False
                and end.get("held") is False, f"{requested} ended unhealthy")
        require(hash_string(run.get("fingerprint")) and hash_string(run.get("aircraft_sha256")),
                f"{requested} lacks typed-state or aircraft identity")
    require(reference["fingerprint"] == native["fingerprint"]
            and reference["aircraft_sha256"] == native["aircraft_sha256"], "backend flight identities differ")
    require(native["identity"].get("abi_version") == 2
            and native["identity"].get("binary_sha256") == guard["binary_sha256"]
            and native["identity"].get("source_sha256") == guard["receipt"].get("source_sha256")
            and native["identity"].get("lock_sha256") == guard["receipt"].get("lock_sha256"),
            "native flight identity differs from the installed receipt")
    require(native.get("native_covered_every_tick") is True
            and positive_int(native.get("context_calls"), ticks)
            and positive_int(native.get("stage_calls"), 4 * ticks)
            and native.get("stage_in_use") in ("stage", "body_loads"), "native tick coverage is incomplete")
    replay = min(8, ticks) if row["vehicle"] == "rotorcraft" else 0
    for run in (reference, native):
        require(type(run.get("replay_requested")) is int and run["replay_requested"] == replay,
                "wrong checkpoint replay length")
        if replay:
            require(run.get("replay_ok") is True and type(run.get("replay_completed")) is int
                    and run["replay_completed"] == replay, "checkpoint replay was incomplete")
    if replay:
        require(native.get("replay_native_covered") is True, "native checkpoint replay lacks coverage")


def validate_refusal(row: dict[str, Any], expected: dict[str, Any]) -> None:
    require(row.get("status") == "reference-refused" and row.get("fingerprint_equal") is False
            and row.get("reason") == expected["expected_refusal_reason"], "unexpected refusal status or reason")
    for name, requested in (("reference", "gdscript_reference"), ("native", "native")):
        run = row.get(name)
        require(isinstance(run, dict) and run.get("complete") is False and run.get("requested") == requested
                and run.get("phase") == "reset" and run.get("error") == expected["expected_refusal_reason"],
                f"{requested} did not produce the exact expected reset refusal")
    if runway_start_boundary(expected) or trim_start_boundary(expected):
        validate_observed_start_proof(row, expected)
    else:
        require("startup_proof" not in row, "runway-start proof attached to an undeclared row")


def validate_observed_start_proof(row: dict[str, Any], expected: dict[str, Any]) -> None:
    runway = runway_start_boundary(expected)
    require((runway or trim_start_boundary(expected)) and row_key(row) == row_key(expected)
            and expected.get("expected_refusal_reason") == (RUNWAY_START_REASON if runway else TRIM_START_REASON),
            "start proof is outside its observed row")
    cases = RUNWAY_START_CASES if runway else TRIM_START_CASES
    spec = cases[expected["aircraft"]]["batteries"][expected["battery"]]
    proofs = row.get("startup_proof")
    require(isinstance(proofs, dict) and set(proofs) == {"reference", "native"}, "missing paired startup proof")
    for name, requested in (("reference", "gdscript_reference"), ("native", "native")):
        proof = proofs[name]
        status = {"requested": requested, "identity": {"backend": "gdscript_reference"},
                  "reason": "" if requested == "gdscript_reference" else "pending configuration requires reset"}
        require(isinstance(proof, dict) and proof.get("requested") == requested
                and proof.get("before_status") == status and proof.get("after_status") == status
                and all(proof.get(field) is True for field in ("before_helper_absent", "after_helper_absent",
                    "model_retained", "callbacks_retained", "reference_callbacks_before", "reference_callbacks_after",
                    "kernel_guard_retained", "owner_guard_retained", "selection_valid_before", "selection_valid_after",
                    "input_configuration_retained",
                    "live_configuration_retained", "outcome_empty"))
                and proof.get("aircraft_sha256") == spec["aircraft_sha256"]
                and proof.get("before_frame_bytes_hex") == proof.get("frame_bytes_hex")
                and proof.get("before_live_config_bytes_hex") == proof.get("live_config_bytes_hex"),
                f"{requested} did not retain the reference owner and failed-start outcome")
        live = proof.get("live_config_bytes_hex")
        require(isinstance(live, str) and 0 < len(live) <= 1048576 and len(live) % 2 == 0,
                f"{requested} has malformed live configuration bytes")
        try:
            live_bytes = bytes.fromhex(live)
        except ValueError as error:
            raise CampaignError(f"{requested} has malformed live configuration bytes") from error
        require(live_bytes.hex() == live and proof.get("live_config_sha256") == spec["live_config_sha256"][expected["soft_hull"]]
                and hashlib.sha256(live_bytes).hexdigest() == proof["live_config_sha256"],
                f"{requested} live configuration digest differs")
        if runway:
            require(proof.get("outcome_dictionary_empty") is False
                    and proof.get("outcome_status") == "numerical_unresolved" and proof.get("outcome_ok") is False
                    and proof.get("outcome_message") == RUNWAY_START_REASON.removeprefix("reset failed: "),
                    f"{requested} did not retain the numerical runway outcome")
        else:
            require(proof.get("outcome_dictionary_empty") is True and proof.get("outcome_status") == ""
                    and "outcome_ok" in proof and proof["outcome_ok"] is None and proof.get("outcome_message") == "",
                    f"{requested} did not retain the empty runway outcome for the trim refusal")
        hashes = {"frame": spec["frame_sha256"], "config": spec["config_sha256"][expected["soft_hull"]],
                  "outcome": spec["outcome_sha256"]}
        for field, wanted in hashes.items():
            encoded = proof.get(field + "_bytes_hex")
            require(isinstance(encoded, str) and 0 < len(encoded) <= 262144 and len(encoded) % 2 == 0,
                    f"{requested} has malformed {field} bytes")
            try:
                payload = bytes.fromhex(encoded)
            except ValueError as error:
                raise CampaignError(f"{requested} has malformed {field} bytes") from error
            require(payload.hex() == encoded and proof.get(field + "_sha256") == wanted
                    and hashlib.sha256(payload).hexdigest() == wanted,
                    f"{requested} {field} identity differs from the source observation")
    require(all(proofs["reference"][field + "_bytes_hex"] == proofs["native"][field + "_bytes_hex"]
                for field in ("frame", "config", "outcome", "live_config")), "paired startup identities differ")


def decode_runtime_payload(encoded: str, shapes: tuple[int | str, ...]) -> list[Any]:
    """Decode only the finite Godot Variant types used by the bounded trial evidence."""
    require(len(encoded) <= 4096, "runtime-domain typed payload exceeds its bound")
    data = bytes.fromhex(encoded)
    offset = 0

    def take(fmt: str) -> Any:
        nonlocal offset
        size = struct.calcsize(fmt)
        require(offset + size <= len(data), "runtime-domain typed payload is truncated")
        value = struct.unpack_from(fmt, data, offset)
        offset += size
        return value[0] if len(value) == 1 else value

    require(take("<I") == 28 and take("<I") == len(shapes), "runtime-domain typed array shape differs")
    values: list[Any] = []
    for shape in shapes:
        header = take("<I")
        if type(shape) is int:
            require(header == 33 and take("<I") == shape, "runtime-domain packed array shape differs")
            vector = [take("<d") for _ in range(shape)]
            require(all(math.isfinite(value) for value in vector), "runtime-domain packed array is nonfinite")
            values.append(vector)
        elif shape == "float":
            require(header in (3, 3 | (1 << 16)), "runtime-domain scalar type differs")
            value = take("<d" if header & (1 << 16) else "<f")
            require(math.isfinite(value), "runtime-domain scalar is nonfinite")
            values.append(value)
        else:
            require(shape == "bool" and header == 1, "runtime-domain flag type differs")
            value = take("<I")
            require(value in (0, 1), "runtime-domain flag value differs")
            values.append(bool(value))
    require(offset == len(data), "runtime-domain typed payload has trailing bytes")
    return values


def validate_runtime_payload(trial_hex: str, context_hex: str, tick: int, stage_fraction: float) -> None:
    trial = decode_runtime_payload(trial_hex, (13, 22, "float"))
    context = decode_runtime_payload(context_hex, (14, 4, 5, "float", "float", "float", "bool", "bool"))
    body, continuous, stage_time = trial
    norm_sq = body[6] * body[6] + body[7] * body[7] + body[8] * body[8] + body[9] * body[9]
    tick_time = float(tick) * (1.0 / 240.0)
    require(math.isfinite(norm_sq) and norm_sq > 1e-24 and continuous[0] == 0.0
            and continuous[7] == 0.0 and continuous[8] == 2.0 and continuous[18] == 1.0
            and context[3] == tick_time and stage_time == tick_time + (1.0 / 240.0) * stage_fraction
            and context[4] == 0.0 and context[5] == 0.0 and context[6] is False and context[7] is False,
            "runtime-domain typed trial or context differs from the stopped-rotor attempt")


def validate_runtime_refusal(row: dict[str, Any], expected: dict[str, Any], guard: dict[str, Any],
                             warmup: int, samples: int) -> None:
    tick = expected["expected_runtime_tick"]
    spec = RUNTIME_CASES[expected["aircraft"]]
    require(warmup + samples > tick and row.get("status") == "runtime-domain-refused"
            and row.get("reason") == RUNTIME_CODE and row.get("fingerprint_equal") is False,
            "unexpected runtime-domain status")
    for name, requested in (("reference", "gdscript_reference"), ("native", "native")):
        run = row.get(name)
        require(isinstance(run, dict) and run.get("complete") is False and run.get("requested") == requested,
                f"{requested} was incorrectly credited with a complete flight")
    proof = row.get("runtime_domain")
    require(isinstance(proof, dict) and proof.get("code") == RUNTIME_CODE and proof.get("origin") == "feed_endpoint",
            "missing exact runtime-domain branch")
    for name, value in (("accepted_ticks", tick), ("attempted_tick", tick + 1),
                        ("requested_ticks", warmup + samples), ("warmup_completed", min(warmup, tick)),
                        ("samples_completed", max(0, tick - warmup)), ("prefix_boundaries", tick + 1),
                        ("reference_input_reads", tick + 1), ("native_input_reads", tick + 1)):
        require(type(proof.get(name)) is int and proof[name] == value, f"runtime-domain {name} differs")
    for name in ("prefix_equal_every_tick", "terminal_equal", "reference_rollback", "native_rollback",
                 "reference_owner_retained", "native_owner_retained", "native_covered_every_tick", "trial_equal",
                 "context_equal", "reference_result_empty"):
        require(proof.get(name) is True, f"runtime-domain {name} missing")
    require(hash_string(proof.get("reference_prefix_sha256"))
            and proof.get("native_prefix_sha256") == proof["reference_prefix_sha256"],
            "runtime-domain prefix fingerprints differ")
    reference_end, native_end = proof.get("reference_end"), proof.get("native_end")
    require(isinstance(reference_end, dict) and reference_end == native_end
            and type(reference_end.get("tick")) is int and reference_end["tick"] == tick
            and reference_end.get("fault") == RUNTIME_FAULT and reference_end.get("paused") is True
            and reference_end.get("crashed") is False and reference_end.get("held") is False,
            "runtime-domain terminal state differs")
    identity = proof.get("native_identity")
    reference_identity = proof.get("reference_identity")
    require(isinstance(reference_identity, dict) and reference_identity.get("backend") == "gdscript_reference"
            and hash_string(proof.get("reference_aircraft_sha256"))
            and proof.get("native_aircraft_sha256") == proof["reference_aircraft_sha256"],
            "runtime-domain reference owner or aircraft identity differs")
    require("aircraft_sha256" not in spec or proof["reference_aircraft_sha256"] == spec["aircraft_sha256"],
            "runtime-domain aircraft differs from the observed fixture")
    require(isinstance(identity, dict) and identity.get("backend") == "native" and identity.get("abi_version") == 2
            and identity.get("binary_sha256") == guard["binary_sha256"]
            and identity.get("source_sha256") == guard["receipt"].get("source_sha256")
            and identity.get("lock_sha256") == guard["receipt"].get("lock_sha256"),
            "runtime-domain native identity differs")
    require(positive_int(proof.get("native_stage_calls"), 4 * tick + spec["rejected_stage_calls"])
            and positive_int(proof.get("native_context_calls"), tick + 1)
            and type(proof.get("rejected_stage_calls")) is int
            and proof["rejected_stage_calls"] == spec["rejected_stage_calls"]
            and type(proof.get("rejected_context_calls")) is int and proof["rejected_context_calls"] == 1
            and proof["rejected_stage_calls"] <= proof["native_stage_calls"]
            and proof["rejected_context_calls"] <= proof["native_context_calls"]
            and type(proof.get("native_diagnostic_stage_call")) is int
            and proof.get("native_diagnostic_stage_call") == proof["native_stage_calls"]
            and type(proof.get("native_diagnostic_context_call")) is int
            and proof.get("native_diagnostic_context_call") == proof["native_context_calls"],
            "runtime-domain native coverage or rejecting call is incomplete")
    for name in ("trial", "context"):
        encoded, digest = proof.get(name + "_bytes_hex"), proof.get(name + "_sha256")
        native_encoded, native_digest = proof.get("native_" + name + "_bytes_hex"), proof.get("native_" + name + "_sha256")
        require(isinstance(encoded, str) and bool(encoded) and len(encoded) <= 4096 and len(encoded) % 2 == 0
                and re.fullmatch(r"[0-9a-f]+", encoded) is not None and hash_string(digest)
                and native_encoded == encoded and native_digest == digest
                and hashlib.sha256(bytes.fromhex(encoded)).hexdigest() == digest,
                f"runtime-domain typed {name} evidence is malformed")
        require(name + "_sha256" not in spec or digest == spec[name + "_sha256"],
                f"runtime-domain typed {name} differs from the observed fixture")
    validate_runtime_payload(proof["trial_bytes_hex"], proof["context_bytes_hex"], tick, spec["stage_fraction"])
    reference_cause, native_cause = proof.get("reference_cause"), proof.get("native_cause")
    require(isinstance(reference_cause, dict) and isinstance(native_cause, dict)
            and reference_cause.get("code") == native_cause.get("code") == RUNTIME_CODE
            and reference_cause.get("origin") == native_cause.get("origin") == "feed_endpoint"
            and type(native_cause.get("feed_factor")) in (int, float)
            and native_cause["feed_factor"] in (0.0, 2.0),
            "runtime-domain branch evidence differs")
    require("feed_factor" not in spec or native_cause["feed_factor"] == spec["feed_factor"],
            "runtime-domain feed factor differs from the observed branch")
    fields = ("feed_factor", "rpm", "demand_nm", "friction_nm", "prop_load_torque_nm", "axial_acceleration_rad_s2",
              "rotor_inertia_kg_m2")
    for field in fields:
        left, right = reference_cause.get(field), native_cause.get(field)
        require(type(left) in (int, float) and type(right) in (int, float)
                and math.isfinite(left) and math.isfinite(right)
                and struct.pack("<d", float(left)) == struct.pack("<d", float(right)),
                f"runtime-domain {field} differs")
    if "cause_bytes_hex" in spec:
        require(b"".join(struct.pack("<d", float(reference_cause[field])) for field in fields).hex()
                == spec["cause_bytes_hex"], "runtime-domain cause differs from the observed fixture")
    require(reference_cause["rpm"] == 0.0 and reference_cause["friction_nm"] > 0.0
            and reference_cause["rotor_inertia_kg_m2"] > 0.0
            and reference_cause["demand_nm"] == -reference_cause["prop_load_torque_nm"]
                - reference_cause["rotor_inertia_kg_m2"] * reference_cause["axial_acceleration_rad_s2"]
            and reference_cause["demand_nm"] < -reference_cause["friction_nm"],
            "runtime-domain finite reverse-demand condition is absent")


def validate_physical_terminal(row: dict[str, Any], expected: dict[str, Any], guard: dict[str, Any],
                               warmup: int, samples: int) -> None:
    require(physical_terminal_boundary(expected) and physical_terminal_boundary(row)
            and row_key(row) == row_key(expected) and expected.get("expected_terminal_tick") == TERMINAL_TICK
            and type(expected.get("expected_terminal_tick")) is int
            and type(row.get("expected_terminal_tick")) is int and row["expected_terminal_tick"] == TERMINAL_TICK
            and expected.get("expected") == "physical-terminal" and row.get("expected") == "physical-terminal"
            and warmup + samples >= TERMINAL_TICK
            and row.get("status") == "physical-terminal" and row.get("reason") == TERMINAL_CODE
            and row.get("fingerprint_equal") is False, "unexpected physical-terminal row or horizon")
    for name, requested in (("reference", "gdscript_reference"), ("native", "native")):
        run = row.get(name)
        require(isinstance(run, dict) and run.get("complete") is False and run.get("requested") == requested,
                f"{requested} was incorrectly credited with a completed flight")
    proof = row.get("physical_terminal")
    require(isinstance(proof, dict) and proof.get("code") == TERMINAL_CODE,
            "missing physical-terminal proof")
    for name, value in (("accepted_ticks", TERMINAL_TICK), ("requested_ticks", warmup + samples),
                        ("warmup_completed", min(warmup, TERMINAL_TICK)),
                        ("samples_completed", max(0, TERMINAL_TICK - warmup)),
                        ("prefix_boundaries", TERMINAL_TICK + 1), ("terminal_tick", TERMINAL_TICK),
                        ("stopped_attempts", 2), ("reference_input_reads", TERMINAL_TICK),
                        ("native_input_reads", TERMINAL_TICK), ("native_context_calls", TERMINAL_TICK),
                        ("native_stage_calls", 4 * TERMINAL_TICK)):
        require(type(proof.get(name)) is int and proof[name] == value, f"physical-terminal {name} differs")
    for name in ("prefix_equal_every_tick", "view_equal_every_tick", "native_owner_every_tick",
                 "reference_owner_every_tick", "model_contract_retained", "native_covered_every_tick",
                 "physical_configuration_retained", "live_configuration_retained", "no_holds",
                 "one_input_each_every_tick", "terminal_accepted", "previous_state_retained", "stopped_unchanged"):
        require(proof.get(name) is True, f"physical-terminal {name} missing")
    require(proof.get("aircraft_sha256") == TERMINAL_AIRCRAFT and proof.get("world_identity") == TERMINAL_WORLD
            and proof.get("reference_prefix_sha256") == proof.get("native_prefix_sha256") == TERMINAL_PREFIX
            and proof.get("reference_view_prefix_sha256") == proof.get("native_view_prefix_sha256")
            == TERMINAL_VIEW_PREFIX, "physical-terminal aircraft, world or prefix differs")
    identities = {**TERMINAL_IDENTITIES, **TERMINAL_CONFIGS[expected["soft_hull"]]}
    for name, expected_hash in identities.items():
        raw = proof.get(name + "_bytes_hex")
        require(isinstance(raw, str) and bool(raw) and len(raw) % 2 == 0
                and re.fullmatch(r"[0-9a-f]+", raw) is not None, f"malformed physical-terminal {name} bytes")
        require(proof.get(name + "_sha256") == expected_hash
                and hashlib.sha256(bytes.fromhex(raw)).hexdigest() == expected_hash,
                f"physical-terminal {name} differs from the observed typed bytes")
    require(proof.get("stopped_frame_bytes_hex") == proof["terminal_frame_bytes_hex"]
            and proof.get("stopped_view_bytes_hex") == proof["terminal_view_bytes_hex"],
            "physical-terminal changed after a stopped advance")
    reference_identity, native_identity = proof.get("reference_identity"), proof.get("native_identity")
    require(reference_identity == {"backend": "gdscript_reference"}
            and isinstance(native_identity, dict) and native_identity == TERMINAL_NATIVE_IDENTITY
            and type(native_identity.get("abi_version")) is int and native_identity["abi_version"] == 2
            and native_identity.get("binary_sha256") == guard["binary_sha256"]
            and native_identity.get("source_sha256") == guard["receipt"].get("source_sha256")
            and native_identity.get("lock_sha256") == guard["receipt"].get("lock_sha256"),
            "physical-terminal backend owner differs")
    view = proof.get("terminal_view")
    require(isinstance(view, dict), "physical-terminal view is missing")
    try:
        encoded = json.dumps(view, sort_keys=True, separators=(",", ":"), ensure_ascii=True,
                             allow_nan=False).encode("utf-8")
    except (TypeError, ValueError) as error:
        raise CampaignError("physical-terminal view is malformed") from error
    require(hashlib.sha256(encoded).hexdigest() == TERMINAL_VIEW_JSON,
            "physical-terminal JSON metadata differs from the observed event")


def validate_reports(manifest: dict[str, Any], reports: dict[str, dict[str, Any]], guard: dict[str, Any],
                     warmup: int, samples: int) -> dict[str, int]:
    """Reject incomplete or inconsistent shards; callers must also verify files and snapshots."""
    require(positive_int(warmup) and positive_int(samples), "durations must be positive integers")
    expected, aircraft = manifest_index(manifest)
    require(isinstance(reports, dict) and set(reports) == set(aircraft), "missing or unexpected aircraft shard")
    seen: set[tuple[Any, ...]] = set()
    totals = {"declared": len(expected), "flight_passed": 0, "reference_refused": 0,
              "runtime_refused": 0, "physical_terminal": 0}
    baseline: dict[str, Any] | None = None
    for aircraft_id in aircraft:
        report = reports[aircraft_id]
        require(isinstance(report, dict) and report.get("format") == "openrc-nk3-fleet v2"
                and report.get("run_valid") is True and report.get("verdict") == "pass"
                and report.get("failures") == [] and report.get("self_test", {}).get("passed") is True,
                f"{aircraft_id}: oracle did not pass")
        checked = report.get("checked_run")
        require(isinstance(checked, dict) and checked.get("ok") is True and checked.get("complete") is True
                and checked.get("reason") == "passed" and type(checked.get("process_exit")) is int
                and checked["process_exit"] == 0 and type(checked.get("counts", {}).get("error")) is int
                and checked["counts"]["error"] == 0
                and checked.get("missing_required_text") == []
                and "NK3_ORACLE verdict=pass" in checked.get("required_text", []),
                f"{aircraft_id}: checked execution is incomplete")
        command = checked.get("command")
        require(isinstance(command, list) and all(isinstance(arg, str) for arg in command)
                and command.count("--extension=res://native/kernel/openrc_native_kernel.gdextension") == 1
                and command.count(f"--aircraft={aircraft_id}") == 1
                and command.count(f"--warmup={warmup}") == 1 and command.count(f"--samples={samples}") == 1
                and not any(arg.startswith("--weather=") or arg.startswith("--soft-hull=") for arg in command),
                f"{aircraft_id}: checked command was not the expected full shard")
        require(report.get("library", {}).get("ok") is True and report["library"].get("reason") == ""
                and report.get("identity", {}).get("backend") == "native"
                and report["identity"].get("abi_version") == 2, f"{aircraft_id}: native ABI 2 unavailable")
        require(report.get("build_receipt") == guard["receipt"]
                and report.get("binary_sha256_before") == guard["binary_sha256"]
                and report.get("binary_sha256_after") == guard["binary_sha256"]
                and report.get("engine_sha256_before") == guard["engine_sha256"]
                and report.get("engine_sha256_after") == guard["engine_sha256"]
                and report.get("reference_sources_before") == guard["reference_sources"]
                and report.get("reference_sources_after") == guard["reference_sources"],
                f"{aircraft_id}: source, binary or engine identity differs")
        sources, harness = report.get("sources"), report.get("harness_sources")
        required_harness = {"research/native-kernel/fleet.gd", "research/native-kernel/oracle.gd",
                            "research/native-kernel/trajectory.gd", "research/native-kernel/run.py",
                            "research/native-kernel/build.py", "tools/godot/run_checked.py",
                            "app/sim/native_stage.gd"}
        require(isinstance(sources, dict) and sources and report.get("sources_after") == sources
                and isinstance(harness, dict) and harness
                and required_harness.issubset(harness)
                and harness.get("research/native-kernel/fleet.gd") == guard["fleet_sha256"],
                f"{aircraft_id}: harness or source identity differs")
        current = {name: report.get(name) for name in ("engine", "seed", "identity", "law_identity", "sources", "harness_sources")}
        if baseline is None:
            baseline = current
        else:
            require(current == baseline, f"{aircraft_id}: shard identities differ")
        scope, rows = report.get("fleet_scope"), report.get("fleet")
        shard_keys = {key for key in expected if key[0] == aircraft_id}
        require(isinstance(scope, dict) and scope.get("scope") == "scoped"
                and scope.get("filters") in ({"aircraft": aircraft_id, "weather": "", "soft_hull": ""},
                                             {"aircraft": aircraft_id, "weather": "", "soft_hull": "", "vehicle": ""})
                and scope.get("declared_aircraft") == aircraft and type(scope.get("declared_rows")) is int
                and scope["declared_rows"] == len(expected) and type(scope.get("selected_rows")) is int
                and scope["selected_rows"] == len(shard_keys) and scope.get("matrix_complete") is False
                and type(scope.get("warmup_requested")) is int and scope["warmup_requested"] == warmup
                and type(scope.get("samples_requested")) is int and scope["samples_requested"] == samples
                and type(scope.get("failed")) is int and scope["failed"] == 0
                and isinstance(rows, list) and len(rows) == len(shard_keys),
                f"{aircraft_id}: shard scope is incomplete or incorrect")
        flights = refusals = runtime_refusals = terminals = 0
        local: set[tuple[Any, ...]] = set()
        for row in rows:
            key = row_key(row)
            require(key in shard_keys and key not in local and key not in seen,
                    f"{aircraft_id}: duplicate or unexpected fleet row")
            declared = expected[key]
            require(row["default_battery"] == declared["default_battery"]
                    and row.get("expected", "flight") == declared.get("expected", "flight")
                    and row.get("expected_runtime_tick") == declared.get("expected_runtime_tick")
                    and row.get("expected_terminal_tick") == declared.get("expected_terminal_tick"),
                    f"{aircraft_id}: declared row metadata differs")
            if declared.get("expected", "flight") == "reference-refusal":
                validate_refusal(row, declared)
                refusals += 1
            elif declared.get("expected", "flight") == "runtime-domain-refusal" \
                    and warmup + samples > declared["expected_runtime_tick"]:
                validate_runtime_refusal(row, declared, guard, warmup, samples)
                runtime_refusals += 1
            elif declared.get("expected", "flight") == "physical-terminal" \
                    and warmup + samples >= declared["expected_terminal_tick"]:
                validate_physical_terminal(row, declared, guard, warmup, samples)
                terminals += 1
            else:
                validate_flight(row, warmup, samples, guard)
                flights += 1
            local.add(key)
            seen.add(key)
        require(local == shard_keys and type(scope.get("flight_passed")) is int and scope["flight_passed"] == flights
                and type(scope.get("reference_refused")) is int and scope["reference_refused"] == refusals
                and type(scope.get("runtime_refused")) is int and scope["runtime_refused"] == runtime_refusals
                and type(scope.get("physical_terminal")) is int and scope["physical_terminal"] == terminals,
                f"{aircraft_id}: incomplete row totals")
        validate_components(report, flights, refusals, runtime_refusals, terminals)
        totals["flight_passed"] += flights
        totals["reference_refused"] += refusals
        totals["runtime_refused"] += runtime_refusals
        totals["physical_terminal"] += terminals
    require(seen == set(expected), "aggregate does not cover the exact declared fleet")
    return totals


def validate_live_sources(report: dict[str, Any]) -> None:
    """Check every captured source path, not just agreement between report files."""
    for prefix, mapping in (("res://", report["sources"]), ("", report["harness_sources"])):
        for name, expected in mapping.items():
            require(isinstance(name, str) and name.startswith(prefix) and hash_string(expected), "invalid source entry")
            base = ROOT / "app" if prefix else ROOT
            path = (base / name.removeprefix(prefix)).resolve()
            require(path.is_relative_to(base.resolve()) and path.is_file() and sha256(path) == expected,
                    f"captured source no longer matches: {name}")


def validate_macos_live_sources(report: dict[str, Any], project: Path) -> None:
    runner = load_runner()
    for prefix, mapping in (("res://", report["sources"]), ("", report["harness_sources"])):
        require(isinstance(mapping, dict) and mapping, "missing source inventory")
        for name, expected in mapping.items():
            require(isinstance(name, str) and name.startswith(prefix) and hash_string(expected), "invalid source entry")
            base = ROOT / "app" if prefix else ROOT
            relative = name.removeprefix(prefix)
            require("\\" not in relative and all(part not in ("", ".", "..") for part in relative.split("/")),
                    "invalid source path")
            canonical = (base / relative).resolve()
            require(canonical.is_relative_to(base.resolve()), "source path escapes its repository")
            actual = runner.project_file(canonical, project)
            require(actual.is_file() and sha256(actual) == expected, f"captured source no longer matches: {name}")


def validate_macos_base_boundary(guard: dict[str, Any]) -> dict[str, Any]:
    """Bind the installed receipt's exact base oracle; it observed FPCR in its own process."""
    mac = load_macos_builder()
    root = Path(guard["qualification_root"]).resolve()
    require(root.is_relative_to((ROOT / "tmp").resolve()) and root != (ROOT / "tmp").resolve() and root.is_dir(),
            "Mac qualification root must be an existing directory inside tmp/")
    installed = guard["receipt"]
    record = installed.get("verification", {}).get("base_oracle")
    require(isinstance(record, dict) and set(record) == {"results", "results_sha256", "verdict", "compared"},
            "missing or malformed installed Mac base-oracle citation")
    name, expected_hash = record["results"], record["results_sha256"]
    require(isinstance(name, str) and bool(name) and "/" not in name and "\\" not in name
            and not any(ord(char) < 32 or ord(char) == 127 for char in name)
            and Path(name).name == name and fnmatch.fnmatchcase(name, mac.verification_roster()["base_oracle"])
            and "_mutant" not in name and hash_string(expected_hash) and record["verdict"] == "pass"
            and positive_int(record["compared"]), "invalid installed Mac base-oracle citation")
    path = root / name
    candidate_path = root / "build-receipt.json"
    for artifact in (path, candidate_path):
        require(not artifact.is_symlink() and artifact.is_file() and artifact.resolve().parent == root,
                f"missing or redirected Mac base evidence: {artifact}")
    report_hash, candidate_hash = sha256(path), sha256(candidate_path)
    require(report_hash == expected_hash, "installed Mac base-oracle report changed")
    lock = mac.locked.load_lock()
    toolchain = mac.host_toolchain()
    engine = mac.godot_identity(Path(guard["godot"]), lock)
    candidate = mac.validate_build(root, False, mac._identity(), toolchain, engine, lock)
    require(isinstance(candidate, dict) and json.loads(candidate_path.read_text(encoding="utf-8")) == candidate
            and candidate.get("binary_sha256") == guard["binary_sha256"]
            and candidate.get("engine") == installed.get("engine") == engine
            and candidate.get("engine_sha256") == guard["engine_sha256"]
            and candidate.get("toolchain") == installed.get("toolchain") == toolchain
            and candidate.get("reference_sources_sha256") == guard["reference_sources"] == installed.get("mirrored_sources")
            and all(key in candidate and key in installed and candidate[key] == installed[key] for key in
                    ("source_sha256", "lock_sha256", "builder_sha256", "linux_builder_sha256",
                     "shared_builder_sha256", "godot_cpp_commit", "extension_api_sha256",
                     "binding_precision", "cxxflags_appended", "repository_head")),
            "Mac base-oracle build differs from the installed fleet identity")
    data = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(data, dict), "installed Mac base-oracle report is not an object")
    mac._check_oracle_identity(data, path, "base_oracle", candidate, {}, load_runner())
    require(data.get("total", {}).get("compared") == record["compared"],
            "installed Mac base-oracle comparison count differs")
    checked = data["checked_run"]
    checked_path, log_path = Path(checked["report"]), Path(checked["log"])
    checked_hash, log_hash = sha256(checked_path), sha256(log_path)
    require(log_hash == checked["log_sha256"] and json.loads(checked_path.read_text(encoding="utf-8")) == checked
            and sha256(path) == report_hash and sha256(candidate_path) == candidate_hash
            and sha256(checked_path) == checked_hash and sha256(log_path) == log_hash,
            "Mac base-oracle evidence changed during verification")
    return {"scope": "separate-base-oracle-process", "report": str(path), "report_sha256": report_hash,
            "candidate_receipt": str(candidate_path), "candidate_receipt_sha256": candidate_hash,
            "checked_report": str(checked_path), "checked_report_sha256": checked_hash,
            "checked_log": str(log_path), "checked_log_sha256": log_hash,
            "binary_sha256": guard["binary_sha256"], "engine_sha256": guard["engine_sha256"],
            "compared": record["compared"]}


def _validate_macos_shard(aircraft_id: str, report: dict[str, Any], path: Path,
                           expected: dict[tuple[Any, ...], dict[str, Any]], catalog: list[str],
                           guard: dict[str, Any], warmup: int, samples: int) -> dict[tuple[Any, ...], dict[str, Any]]:
    """Check a finished passing or failing shard before crediting any individual flight."""
    require(isinstance(report, dict) and report.get("format") == "openrc-nk3-fleet v2"
            and report.get("verdict") in ("pass", "fail") and report.get("self_test", {}).get("passed") is True
            and report.get("experimental_native_macos") is True, f"{aircraft_id}: invalid Mac oracle report")
    law = report.get("law_identity")
    require(isinstance(law, dict) and all(isinstance(law.get(name), str) and bool(law[name]) for name in
            ("aero_reference", "aero_native", "rolling_reference", "rolling_native"))
            and law["aero_reference"] == law["aero_native"] and law["rolling_reference"] == law["rolling_native"],
            f"{aircraft_id}: reference/native law identity differs")
    # Real fleet.gd shards do not run the base-only boundary probe. If a future
    # shard reports such evidence, do not accept a partial or invalid probe.
    if "macos_boundary" in report:
        boundary_error = load_macos_builder()._macos_boundary_error(report)
        require(not boundary_error, f"{aircraft_id}: {boundary_error}")
    passed = report["verdict"] == "pass"
    checked = report.get("checked_run")
    require(isinstance(checked, dict) and checked.get("format") == "openrc-godot-check v1"
            and checked.get("complete") is True and checked.get("ok") is passed
            and checked.get("reason") == ("passed" if passed else "process_exit")
            and type(checked.get("process_exit")) is int and checked["process_exit"] == (0 if passed else 1)
            and type(checked.get("counts", {}).get("error")) is int and checked["counts"]["error"] == 0
            and checked.get("required_text") == ["NK3_ORACLE verdict=pass"]
            and checked.get("missing_required_text") == ([] if passed else ["NK3_ORACLE verdict=pass"])
            and report.get("run_valid") is passed, f"{aircraft_id}: checked shard did not finish cleanly")
    log, checked_path = Path(checked.get("log", "")), Path(checked.get("report", ""))
    check_root = Path(guard["tool_root"]) / "checks"
    require(log.is_file() and checked_path.is_file() and not log.is_symlink() and not checked_path.is_symlink()
            and checked_path.resolve().is_relative_to(check_root.resolve()) and log.resolve().parent == checked_path.resolve().parent
            and json.loads(checked_path.read_text(encoding="utf-8")) == checked and sha256(log) == checked.get("log_sha256")
            and f"NK3_ORACLE verdict={'pass' if passed else 'fail'}" in log.read_text(encoding="utf-8", errors="replace"),
            f"{aircraft_id}: checked shard log or report differs")
    command = checked.get("command")
    require(isinstance(command, list) and all(isinstance(arg, str) for arg in command) and command
            and Path(command[0]).resolve() == Path(guard["godot"]).resolve()
            and command.count("--path") == 1 and Path(command[command.index("--path") + 1]).resolve() == Path(guard["project"])
            and command.count("--script") == 1 and Path(command[command.index("--script") + 1]).resolve() == FLEET.resolve()
            and command.count("--extension=res://native/kernel/openrc_native_kernel_macos.gdextension") == 1
            and command.count("--experimental-native-macos=true") == 1 and command.count("--vehicle=fixed-wing") == 1
            and command.count("--seed=20261027") == 1 and report.get("seed") == 20261027
            and command.count(f"--aircraft={aircraft_id}") == 1 and command.count(f"--warmup={warmup}") == 1
            and command.count(f"--samples={samples}") == 1 and command.count(f"--output={path}") == 1
            and not any(arg.startswith("--weather=") or arg.startswith("--soft-hull=") for arg in command),
            f"{aircraft_id}: checked command differs from the Mac fixed-wing shard")
    require(report.get("library", {}).get("ok") is True and report["library"].get("reason") == ""
            and report.get("identity", {}).get("backend") == "native"
            and report["identity"].get("abi_version") == 2 and report["identity"].get("backend_version") == guard["receipt"]["backend_version"]
            and report.get("build_receipt") == guard["receipt"]
            and report.get("engine") == guard["receipt"]["engine_version"]
            and all(report.get(name) == guard["engine_sha256"] for name in
                    ("engine_sha256_before", "engine_sha256_after", "engine_executable_sha256_before", "engine_executable_sha256_after"))
            and all(report.get(name) == guard["binary_sha256"] for name in ("binary_sha256_before", "binary_sha256_after"))
            and report.get("reference_sources_before") == guard["reference_sources"]
            and report.get("reference_sources_after") == guard["reference_sources"]
            and report.get("harness_sources") == guard["harness_sources"]
            and isinstance(report.get("sources"), dict) and report["sources"] and report.get("sources_after") == report["sources"]
            and report.get("project") == guard["project"]
            and report.get("project_inventory_before") == guard["project_inventory"]
            and report.get("project_inventory_after") == guard["project_inventory"],
            f"{aircraft_id}: Mac source, engine, binary, harness or project identity differs")
    validate_macos_live_sources(report, Path(guard["project"]))
    selected = {key for key in expected if key[0] == aircraft_id and key[1] == "fixed-wing"}
    scope, rows = report.get("fleet_scope"), report.get("fleet")
    require(selected and isinstance(scope, dict) and scope.get("scope") == "scoped"
            and scope.get("filters") == {"aircraft": aircraft_id, "weather": "", "soft_hull": "", "vehicle": "fixed-wing"}
            and scope.get("declared_aircraft") == catalog and type(scope.get("declared_rows")) is int
            and scope["declared_rows"] == len(expected) and type(scope.get("selected_rows")) is int
            and scope["selected_rows"] == len(selected) and scope.get("matrix_complete") is False
            and type(scope.get("warmup_requested")) is int and scope["warmup_requested"] == warmup
            and type(scope.get("samples_requested")) is int and scope["samples_requested"] == samples
            and isinstance(rows, list) and len(rows) == len(selected), f"{aircraft_id}: incomplete Mac shard scope")
    indexed: dict[tuple[Any, ...], dict[str, Any]] = {}
    counts = {"flight_passed": 0, "reference_refused": 0, "runtime_refused": 0, "physical_terminal": 0, "failed": 0}
    status_fields = {"pass": "flight_passed", "reference-refused": "reference_refused",
                     "runtime-domain-refused": "runtime_refused", "physical-terminal": "physical_terminal", "fail": "failed"}
    for row in rows:
        key = row_key(row)
        require(key in selected and key not in indexed and row.get("status") in status_fields,
                f"{aircraft_id}: duplicate or unexpected Mac row")
        declared = expected[key]
        require(row["default_battery"] == declared["default_battery"]
                and row.get("expected", "flight") == declared.get("expected", "flight")
                and row.get("expected_runtime_tick") == declared.get("expected_runtime_tick")
                and row.get("expected_terminal_tick") == declared.get("expected_terminal_tick"),
                f"{aircraft_id}: declared row metadata differs")
        counts[status_fields[row["status"]]] += 1
        indexed[key] = row
    require(set(indexed) == selected and all(type(scope.get(name)) is int and scope[name] == value
                                             for name, value in counts.items()), f"{aircraft_id}: row totals differ")
    components = report.get("components")
    require(isinstance(components, dict) and components, f"{aircraft_id}: oracle comparisons missing")
    require(positive_int(components.get("literals", {}).get("count")), f"{aircraft_id}: literal probe is missing")
    count = identical = 0
    fleet_components = {"fleet_pair", "fleet_reference_refusal", "fleet_runtime_domain_refusal", "fleet_physical_terminal"}
    for name, component in components.items():
        require(isinstance(component, dict) and positive_int(component.get("count"))
                and type(component.get("identical")) is int and 0 <= component["identical"] <= component["count"]
                and (name in fleet_components or component["identical"] == component["count"]),
                f"{aircraft_id}: non-fleet comparison failed")
        count += component["count"]
        identical += component["identical"]
    if counts["flight_passed"]:
        require(components.get("fleet_pair", {}).get("count", 0) >= counts["flight_passed"]
                and components.get("fleet_pair", {}).get("identical", 0) >= counts["flight_passed"],
                f"{aircraft_id}: passing flights lack paired comparisons")
    require(report.get("total") == {"compared": count, "identical": identical, "mismatched": count - identical}
            and isinstance(report.get("failures"), list)
            and all(isinstance(message, str) and (message.startswith("fleet ") or message == MOONRUNNER_UNQUALIFIED_REASON)
                    for message in report["failures"])
            and ((passed and report["failures"] == [] and count == identical and counts["failed"] == 0)
                 or (not passed and bool(report["failures"]) and counts["failed"] > 0)),
            f"{aircraft_id}: shard verdict or comparison totals differ")
    return indexed


def validate_macos_reports(manifest: dict[str, Any], reports: dict[str, dict[str, Any]],
                            paths: dict[str, Path], selected_aircraft: list[str], errors: dict[str, str],
                            guard: dict[str, Any], warmup: int, samples: int) -> dict[str, Any]:
    require(positive_int(warmup) and positive_int(samples), "durations must be positive integers")
    base_boundary = validate_macos_base_boundary(guard)
    expected, catalog = macos_manifest_index(manifest)
    fixed = {key: row for key, row in expected.items() if key[1] == "fixed-wing"}
    names = list(dict.fromkeys(key[0] for key in fixed))
    require(fixed and len(set(selected_aircraft)) == len(selected_aircraft)
            and set(selected_aircraft).issubset(names) and set(reports).issubset(selected_aircraft)
            and set(paths) == set(reports) and set(errors).issubset(selected_aircraft)
            and not (set(errors) & set(reports)), "invalid Mac fixed-wing shard set")
    rows: list[dict[str, Any]] = []
    checked_rows: dict[str, dict[tuple[Any, ...], dict[str, Any]]] = {}
    shard_errors = dict(errors)
    for name in selected_aircraft:
        if name not in reports:
            shard_errors.setdefault(name, "selected shard produced no report")
            continue
        try:
            checked_rows[name] = _validate_macos_shard(name, reports[name], paths[name], expected, catalog,
                                                       guard, warmup, samples)
        except (CampaignError, OSError, ValueError, KeyError, TypeError, IndexError, AttributeError) as error:
            shard_errors[name] = str(error)
    verified = 0
    for key, declared in fixed.items():
        name = key[0]
        pending = macos_pending_reason(declared)
        item = {field: declared[field] for field in KEY_FIELDS}
        item.update(default_battery=declared["default_battery"], declared_expectation=declared.get("expected", "flight"),
                    status="open", reason="")
        if pending:
            item["reason"] = pending
        elif name not in selected_aircraft:
            item["reason"] = "aircraft was not selected"
        elif name not in checked_rows:
            item["reason"] = "shard unavailable or invalid: " + shard_errors[name]
        else:
            row = checked_rows[name][key]
            try:
                validate_flight(row, warmup, samples, guard)
            except (CampaignError, KeyError, TypeError) as error:
                item["reason"] = "flight failed: " + str(error)
            else:
                item.update(status="verified-flight", reason="", shard_verdict=reports[name]["verdict"])
                verified += 1
        rows.append(item)
    complete = verified == len(fixed) and not shard_errors and set(selected_aircraft) == set(names)
    return {"scope": "macos-arm64-fixed-wing-experimental", "full_catalog": False,
            "base_oracle_boundary": base_boundary,
            "catalog_declared_rows": len(expected), "catalog_aircraft": catalog, "fixed_wing_aircraft": names,
            "selected_aircraft": selected_aircraft, "fixed_wing_declared_rows": len(fixed),
            "verified_flight_rows": verified, "open_rows": len(fixed) - verified,
            "fixed_wing_complete": complete, "shard_errors": shard_errors, "rows": rows}


async def run_shard(aircraft: str, out: Path, semaphore: asyncio.Semaphore, warmup: int, samples: int,
                    timeout: int, context: dict[str, Any] | None = None) -> tuple[str, Path]:
    async with semaphore:
        log_path = out / f"{aircraft}.log"
        command = [sys.executable, str(RUNNER), "--app-library", "--script", "fleet.gd",
                   "--option", f"aircraft={aircraft}", "--option", f"warmup={warmup}",
                   "--option", f"samples={samples}", "--timeout", str(timeout)]
        env = None
        if context is not None:
            command += ["--project", context["project"], "--godot", context["godot"],
                        "--experimental-native-macos", "--option", "vehicle=fixed-wing"]
            env = dict(os.environ, OPENRC_NK_TOOL_ROOT=context["tool_root"])
        print(f"Starting fleet shard: {aircraft}", flush=True)
        with log_path.open("wb") as log:
            proc = await asyncio.create_subprocess_exec(*command, cwd=ROOT, stdout=log,
                                                        stderr=subprocess.STDOUT, start_new_session=True, env=env)
            try:
                code = await proc.wait()
            except asyncio.CancelledError:
                try:
                    # run_checked catches SIGINT and cleans its separately grouped Godot child.
                    os.killpg(proc.pid, signal.SIGINT)
                except ProcessLookupError:
                    pass
                try:
                    await asyncio.wait_for(proc.wait(), timeout=15)
                except asyncio.TimeoutError:
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    await proc.wait()
                raise
        text = log_path.read_text(encoding="utf-8", errors="replace")
        matches = re.findall(r"^verdict=(?:pass|fail) .* results=(.+)$", text, flags=re.MULTILINE)
        require((code == 0 or (context is not None and code == 1)) and len(matches) == 1,
                f"{aircraft}: shard failed; see {log_path}")
        result_path = (ROOT / matches[0]).resolve()
        result_root = Path(context["tool_root"]).resolve() if context is not None else (ROOT / "tmp/native-kernel").resolve()
        require(result_path.is_relative_to(result_root) and result_path.is_file(),
                f"{aircraft}: result path is invalid")
        print(f"Completed fleet shard: {aircraft}", flush=True)
        return aircraft, result_path


async def wait_reused_report(aircraft: str, path: Path, timeout: int, allow_failed: bool = False) -> tuple[str, Path]:
    """Wait for run.py's final checked metadata; the Godot report is written before it."""
    deadline = asyncio.get_running_loop().time() + timeout
    print(f"Waiting for reused fleet shard: {aircraft}", flush=True)
    while asyncio.get_running_loop().time() < deadline:
        if path.is_file():
            try:
                result = json.loads(path.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, OSError):
                result = None  # run.py may be writing its final enriched report
            if isinstance(result, dict) and "run_valid" in result:
                require((result.get("run_valid") is True and result.get("verdict") == "pass")
                        or (allow_failed and result.get("run_valid") is False and result.get("verdict") == "fail"),
                        f"{aircraft}: reused shard did not complete successfully: {path}")
                print(f"Collected reused fleet shard: {aircraft}", flush=True)
                return aircraft, path
        await asyncio.sleep(2)
    raise CampaignError(f"{aircraft}: timed out waiting for reused shard: {path}")


def drift_reason(guard: dict[str, Any], context: dict[str, Any] | None = None) -> str:
    """Explain changes even when snapshot rejects an installed receipt as stale."""
    try:
        current = snapshot(context) if context is not None else snapshot()
    except (CampaignError, OSError, ValueError, KeyError, TypeError) as error:
        changed = []
        for name, digest in guard.get("reference_sources", {}).items():
            path = load_runner().project_file(ROOT / name, Path(context["project"])) if context is not None else ROOT / name
            try:
                if not path.is_file() or sha256(path) != digest:
                    changed.append(name)
            except OSError:
                changed.append(name)
        detail = f"; changed mirrored sources: {', '.join(changed[:8])}" if changed else ""
        return f"frozen source/binary/engine snapshot is invalid: {error}{detail}"
    changed_fields = [name for name in guard if current.get(name) != guard[name]]
    if set(current) != set(guard):
        changed_fields.append("snapshot fields")
    return "frozen source/binary/engine snapshot changed: " + ", ".join(changed_fields) if changed_fields else ""


async def monitor_snapshot(guard: dict[str, Any], interval: float = 5.0, context: dict[str, Any] | None = None) -> None:
    while True:
        await asyncio.sleep(interval)
        reason = drift_reason(guard, context) if context is not None else drift_reason(guard)
        if reason:
            raise CampaignError(reason)


async def run_shards(aircraft: list[str], out: Path, jobs: int, warmup: int, samples: int,
                     timeout: int, reused: dict[str, Path] | None = None,
                     guard: dict[str, Any] | None = None, monitor_interval: float = 5.0,
                     keep_going: bool = False, context: dict[str, Any] | None = None,
                     partial: bool = False) -> dict[str, Any]:
    semaphore = asyncio.Semaphore(jobs)
    reused = reused or {}
    def shard(name: str):
        if name in reused:
            return wait_reused_report(name, reused[name], timeout, allow_failed=True) if context else wait_reused_report(name, reused[name], timeout)
        return (run_shard(name, out, semaphore, warmup, samples, timeout, context=context) if context
                else run_shard(name, out, semaphore, warmup, samples, timeout))
    tasks = [asyncio.create_task(shard(name)) for name in aircraft]
    collected = asyncio.gather(*tasks, return_exceptions=keep_going)
    monitor = (asyncio.create_task(monitor_snapshot(guard, monitor_interval, context)) if context else
               asyncio.create_task(monitor_snapshot(guard, monitor_interval))) if guard is not None else None
    try:
        if monitor is not None:
            finished, _pending = await asyncio.wait((collected, monitor), return_when=asyncio.FIRST_COMPLETED)
            if monitor in finished:
                await monitor
        results = await collected
        failures = [(name, result) for name, result in zip(aircraft, results) if isinstance(result, BaseException)]
        if failures and not partial:
            raise CampaignError("fleet shards failed after independent work finished: "
                                + "; ".join(f"{name}: {error}" for name, error in failures))
        if partial:
            return {"paths": dict(result for result in results if not isinstance(result, BaseException)),
                    "errors": {name: str(error) for name, error in failures}}
        return dict(results)
    except BaseException:
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        await asyncio.gather(collected, return_exceptions=True)
        raise
    finally:
        if monitor is not None:
            monitor.cancel()
            await asyncio.gather(monitor, return_exceptions=True)


def macos_context(args: argparse.Namespace, out: Path) -> dict[str, str]:
    context = {"project": str(args.project.expanduser().resolve()), "godot": str(args.godot.expanduser().resolve()),
               "tool_root": str(args.tool_root.expanduser().resolve()),
               "qualification_root": str(args.qualification_root.expanduser().resolve())}
    project, tool_root, qualification_root = (Path(context[key]) for key in ("project", "tool_root", "qualification_root"))
    require(qualification_root.is_relative_to((ROOT / "tmp").resolve()) and qualification_root != (ROOT / "tmp").resolve()
            and qualification_root.is_dir(), "Mac qualification root must be an existing directory inside tmp/")
    require(not out.is_relative_to(project) and not tool_root.is_relative_to(project)
            and not project.is_relative_to(tool_root) and not out.is_relative_to(tool_root)
            and not tool_root.is_relative_to(out) and not qualification_root.is_relative_to(project)
            and not project.is_relative_to(qualification_root) and not out.is_relative_to(qualification_root)
            and not qualification_root.is_relative_to(out),
            "project, campaign output and evidence roots must be separate")
    return context


def run_macos_campaign(args: argparse.Namespace, out: Path) -> int:
    context = macos_context(args, out)
    tool_root = Path(context["tool_root"])
    guard = snapshot(context)
    base_boundary = validate_macos_base_boundary(guard)
    manifest = make_manifest(out, context)
    expected, _catalog = macos_manifest_index(manifest)
    fixed = [row for row in expected.values() if row["vehicle"] == "fixed-wing"]
    all_aircraft = list(dict.fromkeys(row["aircraft"] for row in fixed))
    selected = args.aircraft or all_aircraft
    require(fixed and len(set(selected)) == len(selected) and set(selected).issubset(all_aircraft),
            "selected aircraft must be distinct declared fixed-wing aircraft")
    reused: dict[str, Path] = {}
    for item in args.reuse_report:
        name, separator, value = item.partition("=")
        require(bool(separator) and name in selected and name not in reused and bool(value),
                "invalid or duplicate reused aircraft report")
        path = Path(value).expanduser().resolve()
        require(path.is_relative_to(tool_root) and path.name.startswith("fleet-") and path.suffix == ".json",
                "reused report must be a fleet JSON in the selected tool root")
        reused[name] = path
    manifest_hash, manifest_script_hash = sha256(out / "manifest.json"), sha256(out / "manifest.gd")
    require(snapshot(context) == guard, "source, binary or engine changed during manifest generation")
    print(f"Declared fleet: {len(expected)} total rows, {len(fixed)} fixed-wing rows across "
          f"{len(all_aircraft)} aircraft; selected {len(selected)}", flush=True)
    pending = any(macos_pending_reason(row) for row in fixed)
    paths: dict[str, Path] = {}
    reports: dict[str, dict[str, Any]] = {}
    report_hashes: dict[str, str] = {}
    errors: dict[str, str] = {}
    if pending and not args.keep_going:
        errors = {name: "known unqualified rows require --keep-going to collect partial evidence" for name in selected}
    else:
        collected = asyncio.run(run_shards(selected, out, args.jobs, args.warmup, args.samples, args.timeout,
                                           reused, guard, monitor_interval=60.0, keep_going=args.keep_going,
                                           context=context, partial=True))
        paths, errors = collected["paths"], collected["errors"]
        for name, path in list(paths.items()):
            try:
                raw = path.read_bytes()
                report = json.loads(raw)
                require(isinstance(report, dict), "shard report is not an object")
                reports[name] = report
                report_hashes[name] = hashlib.sha256(raw).hexdigest()
            except (CampaignError, OSError, ValueError) as error:
                errors[name] = f"cannot read shard report: {error}"
                del paths[name]
    result = validate_macos_reports(manifest, reports, paths, selected, errors, guard, args.warmup, args.samples)
    require(result["base_oracle_boundary"] == base_boundary, "Mac base-oracle evidence changed during the campaign")
    require(sha256(out / "manifest.json") == manifest_hash and sha256(out / "manifest.gd") == manifest_script_hash
            and all(sha256(path) == report_hashes[name] for name, path in paths.items()),
            "manifest or report changed during validation")
    require(snapshot(context) == guard, "source, binary or engine changed during the campaign")
    failed = bool(result["shard_errors"]) or any(row["reason"].startswith("flight failed:") for row in result["rows"])
    verdict = "pass" if result["fixed_wing_complete"] else "fail" if failed and not (pending and not args.keep_going) else "open"
    result.update(format="openrc-nk3-fleet-campaign-macos-experimental v1", verdict=verdict,
                  warmup=args.warmup, samples=args.samples, keep_going=args.keep_going,
                  manifest_sha256=manifest_hash, manifest_script_sha256=manifest_script_hash,
                  guard={**guard, "base_oracle_boundary": base_boundary},
                  reports={name: {"path": str(path), "sha256": report_hashes[name]} for name, path in paths.items()})
    evidence = out / "campaign.json"
    evidence.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"NK3_FLEET_CAMPAIGN verdict={verdict} scope=macos-arm64-fixed-wing-experimental "
          f"verified_flights={result['verified_flight_rows']} open_rows={result['open_rows']} evidence={evidence}",
          flush=True)
    return 0 if verdict == "pass" else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True, help="new evidence directory")
    parser.add_argument("--jobs", type=int, default=3, help="concurrent aircraft processes (1–4)")
    parser.add_argument("--warmup", type=int, default=MIN_WARMUP)
    parser.add_argument("--samples", type=int, default=MIN_SAMPLES)
    parser.add_argument("--timeout", type=int, default=21600, help="per-shard checked timeout in seconds")
    parser.add_argument("--reuse-report", action="append", default=[], metavar="AIRCRAFT=REPORT",
                        help="reuse a current full-aircraft run.py report, waiting if it is still running")
    parser.add_argument("--keep-going", action="store_true",
                        help="finish independent shards after a shard failure; the campaign still fails")
    parser.add_argument("--experimental-native-macos", action="store_true",
                        help="run the scoped experimental Mac ARM64 fixed-wing campaign")
    parser.add_argument("--project", type=Path, help="verified prepared Mac project")
    parser.add_argument("--godot", type=Path, help="Mac engine bound to the project receipt")
    parser.add_argument("--tool-root", type=Path, help="Mac runner's evidence and checks directory under tmp/")
    parser.add_argument("--qualification-root", type=Path, help="exact Mac build and cited oracle evidence under tmp/")
    parser.add_argument("--aircraft", action="append", default=[], metavar="ID",
                        help="select one fixed-wing Mac aircraft (repeatable); omitted aircraft remain open")
    args = parser.parse_args()
    if not 1 <= args.jobs <= MAX_JOBS or args.warmup < MIN_WARMUP or args.samples < MIN_SAMPLES or args.timeout <= 0:
        parser.error("jobs must be 1–4, warmup >= 600, samples >= 2400, and timeout positive")
    if args.experimental_native_macos:
        if args.project is None or args.godot is None or args.tool_root is None or args.qualification_root is None:
            parser.error("--experimental-native-macos requires --project, --godot, --tool-root and --qualification-root")
    elif args.project is not None or args.godot is not None or args.tool_root is not None \
            or args.qualification_root is not None or args.aircraft:
        parser.error("--project, --godot, --tool-root, --qualification-root and --aircraft require --experimental-native-macos")
    out = args.out.resolve()
    try:
        require(out.is_relative_to((ROOT / "tmp").resolve()), "evidence directory must be under tmp/")
        if args.experimental_native_macos:
            macos_context(args, out)
        out.mkdir(parents=True, exist_ok=False)
        if args.experimental_native_macos:
            return run_macos_campaign(args, out)
        guard = snapshot()
        manifest = make_manifest(out)
        expected, aircraft = manifest_index(manifest)
        reused: dict[str, Path] = {}
        for item in args.reuse_report:
            name, separator, value = item.partition("=")
            require(bool(separator) and name in aircraft and name not in reused and bool(value),
                    "invalid or duplicate reused aircraft report")
            path = Path(value).resolve()
            require(path.is_relative_to((ROOT / "tmp/native-kernel").resolve()) and path.name.startswith("fleet-")
                    and path.suffix == ".json", "reused report must be a native-kernel fleet JSON")
            reused[name] = path
        manifest_hash = sha256(out / "manifest.json")
        manifest_script_hash = sha256(out / "manifest.gd")
        require(snapshot() == guard, "source, binary or engine changed during manifest generation")
        print(f"Declared fleet: {len(expected)} rows across {len(aircraft)} aircraft", flush=True)
        paths = asyncio.run(run_shards(aircraft, out, args.jobs, args.warmup, args.samples, args.timeout,
                                       reused, guard, keep_going=args.keep_going))
        report_hashes = {name: sha256(path) for name, path in paths.items()}
        reports = {name: json.loads(path.read_text(encoding="utf-8")) for name, path in paths.items()}
        totals = validate_reports(manifest, reports, guard, args.warmup, args.samples)
        for report in reports.values():
            validate_live_sources(report)
            checked = report["checked_run"]
            log = Path(checked["log"])
            require(log.is_file() and hash_string(checked.get("log_sha256"))
                    and sha256(log) == checked["log_sha256"]
                    and "NK3_ORACLE verdict=pass" in log.read_text(encoding="utf-8", errors="replace"),
                    "checked engine log is missing or changed")
        require(sha256(out / "manifest.json") == manifest_hash and sha256(out / "manifest.gd") == manifest_script_hash
                and all(sha256(paths[name]) == report_hashes[name] for name in aircraft),
                "manifest or report changed during validation")
        require(snapshot() == guard, "source, binary or engine changed during the campaign")
        result = {"format": "openrc-nk3-fleet-campaign v1", "verdict": "pass",
                  "scope": "full-declared-matrix", "warmup": args.warmup, "samples": args.samples,
                  "keep_going": args.keep_going,
                  "manifest_sha256": manifest_hash,
                  "manifest_script_sha256": manifest_script_hash, "guard": guard, "totals": totals,
                  "reports": {name: {"path": str(paths[name]), "sha256": report_hashes[name]}
                              for name in aircraft}}
        (out / "campaign.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"NK3_FLEET_CAMPAIGN verdict=pass rows={totals['declared']} flights={totals['flight_passed']} "
              f"reference_refused={totals['reference_refused']} runtime_refused={totals['runtime_refused']} "
              f"physical_terminal={totals['physical_terminal']} "
              f"evidence={out / 'campaign.json'}", flush=True)
        return 0
    except (CampaignError, OSError, ValueError, KeyError, TypeError) as error:
        print(f"NK3_FLEET_CAMPAIGN verdict=fail reason={error}", file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
