"""BAT-03 independent Python reference for the BAT-04 `pack_ecm` law.

Implements, from the text of docs/research/battery/BAT-04/specification.md and independently of
app/physics/battery/:
  §1–§2  template/pack checks and normalization        -> normalize()
  §4     one stage evaluation and rates                -> stage(), rates()
  §5     reset state and continuous-block order        -> layout(), reset()
  §6     ESC supervisor and cell detection             -> detect_cells(), supervisor_step()
plus a classical RK4 integrator with a located exhaustion event and simulation helpers for a
prescribed current or a prescribed (motor duty, rpm) profile.

Everything is float64 (Python float); functions are pure and there is no module state.
Run the tests with:  python3 -I research/battery/test_ecm_reference.py
"""

from __future__ import annotations

import bisect
import math
from dataclasses import dataclass, replace
from typing import Callable, Optional, Sequence

CELL_FORMAT = "openrc-cell-template v1"
PACK_FORMAT = "openrc-battery v1"
CHEMISTRIES = ("lipo", "lihv", "liion", "lifepo4", "nimh")
EVIDENCE_KINDS = ("manual", "measured", "borrowed", "estimated", "derived")
TIMER_TOLERANCE_S = 1e-9          # §6 timer comparisons
DETECTION_TOLERANCE = 1e-9        # §6 ceil(V/v_detect - 1e-9)
EVENT_TIME_TOLERANCE_S = 1e-12    # exhaustion event localisation


# ---------------------------------------------------------------------------------------------
# Tables (§1, §4 bilinear interpolation)
# ---------------------------------------------------------------------------------------------

@dataclass(frozen=True)
class Table:
    """A [nT][nSOC] table on strictly increasing knots."""

    soc_knots: tuple
    temperature_knots: tuple
    rows: tuple  # tuple of tuples, one per temperature knot


def _segment(knots: Sequence[float], x: float) -> tuple:
    """Index i of the segment [k_i, k_i+1] containing x (clamped) and the weight in [0, 1]."""
    n = len(knots)
    if n == 1 or x <= knots[0]:
        return 0, 0.0
    if x >= knots[-1]:
        return n - 2, 1.0
    i = bisect.bisect_right(knots, x) - 1
    i = min(max(i, 0), n - 2)
    return i, (x - knots[i]) / (knots[i + 1] - knots[i])


def _row_value(row: Sequence[float], i: int, w: float) -> float:
    return row[i] + (row[i + 1] - row[i]) * w


def lookup(table: Table, z: float, temperature_k: float) -> float:
    """§4: clamp z to [0, 1]; interpolate in z on both bounding T rows, then in T (clamped)."""
    zc = min(max(z, 0.0), 1.0)
    i, wz = _segment(table.soc_knots, zc)
    if len(table.temperature_knots) == 1:
        return _row_value(table.rows[0], i, wz)
    j, wt = _segment(table.temperature_knots, temperature_k)
    lower = _row_value(table.rows[j], i, wz)
    upper = _row_value(table.rows[j + 1], i, wz)
    return lower + (upper - lower) * wt


# ---------------------------------------------------------------------------------------------
# Data checks and normalization (§1, §2)
# ---------------------------------------------------------------------------------------------

class BatteryDataError(ValueError):
    """Raised when pack or template data violate BAT-04 §1–§2 (invalid data cannot fly)."""


def _quantity(node, unit: str, where: str) -> object:
    if not isinstance(node, dict) or set(node) != {"value", "unit", "kind", "source"}:
        raise BatteryDataError(f"{where}: expected exactly {{value, unit, kind, source}}")
    if node["unit"] != unit:
        raise BatteryDataError(f"{where}.unit: expected {unit!r}, found {node['unit']!r}")
    if node["kind"] not in EVIDENCE_KINDS:
        raise BatteryDataError(f"{where}.kind: unsupported {node['kind']!r}")
    if not isinstance(node["source"], str) or not node["source"].strip():
        raise BatteryDataError(f"{where}.source: must be a nonblank string")
    return node["value"]


def _finite(x, where: str) -> float:
    if isinstance(x, bool) or not isinstance(x, (int, float)) or not math.isfinite(float(x)):
        raise BatteryDataError(f"{where}: not a finite number")
    return float(x)


def _scalar(node, unit: str, where: str, positive: bool = True) -> float:
    value = _finite(_quantity(node, unit, where), where + ".value")
    if positive and value <= 0.0:
        raise BatteryDataError(f"{where}.value: must be positive")
    return value


def _vector(node, unit: str, where: str) -> tuple:
    raw = _quantity(node, unit, where)
    if not isinstance(raw, list) or not raw:
        raise BatteryDataError(f"{where}.value: expected a nonempty list")
    return tuple(_finite(x, f"{where}.value[{k}]") for k, x in enumerate(raw))


def _strictly_increasing(values: Sequence[float], where: str) -> None:
    for a, b in zip(values, values[1:]):
        if not b > a:
            raise BatteryDataError(f"{where}: must be strictly increasing")


def _matrix(node, unit: str, where: str, n_t: int, n_z: int, positive: bool) -> tuple:
    raw = _quantity(node, unit, where)
    if not isinstance(raw, list) or len(raw) != n_t:
        raise BatteryDataError(f"{where}.value: expected {n_t} temperature rows")
    rows = []
    for r, row in enumerate(raw):
        if not isinstance(row, list) or len(row) != n_z:
            raise BatteryDataError(f"{where}.value[{r}]: expected {n_z} SOC values")
        values = tuple(_finite(x, f"{where}.value[{r}][{c}]") for c, x in enumerate(row))
        if positive and min(values) <= 0.0:
            raise BatteryDataError(f"{where}.value[{r}]: entries must be positive")
        rows.append(values)
    return tuple(rows)


@dataclass(frozen=True)
class Pack:
    """A pack after §2 normalization. Resistances are template values; s_r is applied in stage()."""

    pack_id: str
    template_id: str
    chemistry: str
    series: int
    parallel: int
    group_capacity_c: float       # Q_g = 3600 · rated_capacity_ah
    resistance_factor: float      # s_R = (reference / rated) · resistance_scale
    interconnect_ohm: float       # R_w
    thermal_capacity_j_per_k: float  # C_th = mass · c_p
    still_air_w_per_k: float
    forced_w_per_k_per_sqrt_mps: float
    ocv: Table
    r0: Table
    rc_r: tuple                   # one Table per RC branch
    rc_tau: tuple
    v_max: float
    v_cutoff: float
    v_damage_floor: float
    t_min_k: float
    t_max_k: float

    @property
    def branches(self) -> int:
        return len(self.rc_r)

    def hA(self, cooling_speed_mps: float) -> float:
        """§2: hA(v) = still + forced · sqrt(max(v, 0))."""
        return self.still_air_w_per_k + self.forced_w_per_k_per_sqrt_mps * math.sqrt(max(cooling_speed_mps, 0.0))


def normalize(pack: dict, template: dict) -> Pack:
    """Check a pack and its cell template against §1–§2 and return the normalized pack."""
    if template.get("format") != CELL_FORMAT:
        raise BatteryDataError("template.format: expected " + CELL_FORMAT)
    if pack.get("format") != PACK_FORMAT:
        raise BatteryDataError("pack.format: expected " + PACK_FORMAT)
    if template.get("chemistry") not in CHEMISTRIES or pack.get("chemistry") != template.get("chemistry"):
        raise BatteryDataError("chemistry: must be supported and equal in pack and template")
    if template.get("tier") not in ("A", "B", "C"):
        raise BatteryDataError("template.tier: must be A, B or C")
    ref = pack.get("cell_template")
    if not isinstance(ref, dict) or ref.get("id") != template.get("id"):
        raise BatteryDataError("pack.cell_template.id: does not name this template")
    series, parallel = pack.get("series"), pack.get("parallel")
    if isinstance(series, bool) or not isinstance(series, int) or not 1 <= series <= 24:
        raise BatteryDataError("pack.series: integer in 1..24")
    if isinstance(parallel, bool) or not isinstance(parallel, int) or not 1 <= parallel <= 8:
        raise BatteryDataError("pack.parallel: integer in 1..8")

    soc = _vector(template.get("soc_knots"), "1", "template.soc_knots")
    temps = _vector(template.get("temperature_knots_k"), "K", "template.temperature_knots_k")
    if len(soc) < 2 or soc[0] != 0.0 or soc[-1] != 1.0:
        raise BatteryDataError("template.soc_knots: at least 2 knots, first 0, last 1")
    _strictly_increasing(soc, "template.soc_knots")
    _strictly_increasing(temps, "template.temperature_knots_k")
    n_t, n_z = len(temps), len(soc)
    ocv = _matrix(template.get("ocv_v"), "V", "template.ocv_v", n_t, n_z, True)
    for r, row in enumerate(ocv):
        if any(b < a for a, b in zip(row, row[1:])):
            raise BatteryDataError(f"template.ocv_v.value[{r}]: OCV must be nondecreasing in SOC")
    r0 = _matrix(template.get("r0_ohm"), "ohm", "template.r0_ohm", n_t, n_z, True)
    branches = template.get("rc_branches")
    if not isinstance(branches, list) or len(branches) > 2:
        raise BatteryDataError("template.rc_branches: array of 0..2 branches")
    rc_r, rc_tau = [], []
    for k, branch in enumerate(branches):
        if not isinstance(branch, dict) or set(branch) != {"r_ohm", "tau_s"}:
            raise BatteryDataError(f"template.rc_branches[{k}]: expected {{r_ohm, tau_s}}")
        rc_r.append(_matrix(branch["r_ohm"], "ohm", f"template.rc_branches[{k}].r_ohm", n_t, n_z, True))
        rc_tau.append(_matrix(branch["tau_s"], "s", f"template.rc_branches[{k}].tau_s", n_t, n_z, True))
    medians = [sorted(x for row in tau for x in row)[(n_t * n_z) // 2] for tau in rc_tau]
    if any(b < a for a, b in zip(medians, medians[1:])):
        raise BatteryDataError("template.rc_branches: branches must be ordered by increasing median tau")

    reference = _scalar(template.get("reference_capacity_ah"), "Ah", "template.reference_capacity_ah")
    cp = _scalar(template.get("specific_heat_j_per_kg_k"), "J/(kg·K)", "template.specific_heat_j_per_kg_k")
    limits = template.get("limits")
    if not isinstance(limits, dict) or set(limits) != {"v_max", "v_cutoff", "v_damage_floor", "t_min_k", "t_max_k"}:
        raise BatteryDataError("template.limits: expected v_max, v_cutoff, v_damage_floor, t_min_k, t_max_k")
    v_max = _scalar(limits["v_max"], "V", "template.limits.v_max")
    v_cut = _scalar(limits["v_cutoff"], "V", "template.limits.v_cutoff")
    v_floor = _scalar(limits["v_damage_floor"], "V", "template.limits.v_damage_floor")
    t_min = _scalar(limits["t_min_k"], "K", "template.limits.t_min_k")
    t_max = _scalar(limits["t_max_k"], "K", "template.limits.t_max_k")
    if not (v_floor < v_cut < v_max) or not t_min < t_max:
        raise BatteryDataError("template.limits: need v_damage_floor < v_cutoff < v_max and t_min_k < t_max_k")

    rated = _scalar(pack.get("rated_capacity_ah"), "Ah", "pack.rated_capacity_ah")
    scale = _scalar(pack.get("resistance_scale"), "1", "pack.resistance_scale")
    wiring = _scalar(pack.get("interconnect_resistance_ohm"), "ohm", "pack.interconnect_resistance_ohm", positive=False)
    if wiring < 0.0:
        raise BatteryDataError("pack.interconnect_resistance_ohm: must be >= 0")
    mass = _scalar(pack.get("mass_kg"), "kg", "pack.mass_kg")
    dims = _vector(pack.get("dimensions_m"), "m", "pack.dimensions_m")
    if len(dims) != 3 or min(dims) <= 0.0:
        raise BatteryDataError("pack.dimensions_m: three positive lengths")
    heat = pack.get("heat_transfer")
    if not isinstance(heat, dict) or set(heat) != {"still_air_w_per_k", "forced_w_per_k_per_sqrt_mps"}:
        raise BatteryDataError("pack.heat_transfer: expected still_air_w_per_k and forced_w_per_k_per_sqrt_mps")
    still = _scalar(heat["still_air_w_per_k"], "W/K", "pack.heat_transfer.still_air_w_per_k", positive=False)
    forced = _scalar(heat["forced_w_per_k_per_sqrt_mps"], "W/(K·(m/s)^0.5)",
                     "pack.heat_transfer.forced_w_per_k_per_sqrt_mps", positive=False)
    if still < 0.0 or forced < 0.0:
        raise BatteryDataError("pack.heat_transfer: coefficients must be >= 0")

    def table(rows: tuple) -> Table:
        return Table(soc, temps, rows)

    return Pack(
        pack_id=str(pack.get("id")), template_id=str(template.get("id")), chemistry=str(template["chemistry"]),
        series=series, parallel=parallel,
        group_capacity_c=3600.0 * rated,
        resistance_factor=(reference / rated) * scale,
        interconnect_ohm=wiring,
        thermal_capacity_j_per_k=mass * cp,
        still_air_w_per_k=still, forced_w_per_k_per_sqrt_mps=forced,
        ocv=table(ocv), r0=table(r0),
        rc_r=tuple(table(t) for t in rc_r), rc_tau=tuple(table(t) for t in rc_tau),
        v_max=v_max, v_cutoff=v_cut, v_damage_floor=v_floor, t_min_k=t_min, t_max_k=t_max,
    )


# ---------------------------------------------------------------------------------------------
# Session, motor and ESC configuration (§3)
# ---------------------------------------------------------------------------------------------

@dataclass(frozen=True)
class Session:
    """§3 `propulsion.battery` session inputs plus the ESC voltage filter used by §4 dv_s/dt."""

    initial_soc: float = 1.0
    auxiliary_current_a: float = 0.0
    cooling_airflow_fraction: float = 0.0
    capacity_factor: float = 1.0
    resistance_factor: float = 1.0
    soc_offset: float = 0.0
    voltage_filter_s: float = 0.05

    def __post_init__(self) -> None:
        checks = (
            (0.0 < self.initial_soc <= 1.0, "initial_soc in (0, 1]"),
            (self.auxiliary_current_a >= 0.0, "auxiliary_current_a >= 0"),
            (0.0 <= self.cooling_airflow_fraction <= 1.0, "cooling_airflow_fraction in [0, 1]"),
            (0.0 < self.capacity_factor <= 1.0, "weak_cell.capacity_factor in (0, 1]"),
            (1.0 <= self.resistance_factor <= 10.0, "weak_cell.resistance_factor in [1, 10]"),
            (0.0 <= self.soc_offset < 0.5, "weak_cell.soc_offset in [0, 0.5)"),
            (self.initial_soc - self.soc_offset > 0.0, "initial_soc - soc_offset > 0"),
            (self.voltage_filter_s >= 0.02, "voltage_filter_s >= 0.02"),
        )
        for ok, text in checks:
            if not ok:
                raise BatteryDataError("session: " + text)


@dataclass(frozen=True)
class Motor:
    """EL1a DC-equivalent motor: back EMF E_m = rpm / Kv [V], winding resistance Rm [ohm]."""

    kv_rpm_per_v: float
    resistance_ohm: float


@dataclass(frozen=True)
class LowVoltageCutoff:
    """§3 `propulsion.esc.low_voltage_cutoff`."""

    mode: str = "soft"                 # soft | hard | off
    cell_detection: str = "auto"       # auto | fixed
    cutoff_per_cell_v: float = 3.2
    soft_limit: float = 0.5
    soft_ramp_s: float = 3.0
    debounce_s: float = 0.5
    recovery: str = "throttle_reset"   # throttle_reset | latched
    reset_throttle_max: float = 0.05
    voltage_filter_s: float = 0.05
    fixed_cells: Optional[int] = None
    detection_max_cell_v: Optional[float] = 4.35

    def __post_init__(self) -> None:
        checks = (
            (self.mode in ("soft", "hard", "off"), "mode"),
            (self.cell_detection in ("auto", "fixed"), "cell_detection"),
            (self.cell_detection != "fixed" or (isinstance(self.fixed_cells, int) and self.fixed_cells >= 1), "fixed_cells"),
            (self.cell_detection != "auto" or (self.detection_max_cell_v is not None and self.detection_max_cell_v > 0.0),
             "detection_max_cell_v"),
            (self.cutoff_per_cell_v > 0.0, "cutoff_per_cell_v"),
            (0.0 <= self.soft_limit < 1.0, "soft_limit in [0, 1)"),
            (self.soft_ramp_s > 0.0, "soft_ramp_s > 0"),
            (self.debounce_s >= 0.0, "debounce_s >= 0"),
            (self.recovery in ("throttle_reset", "latched"), "recovery"),
            (0.0 <= self.reset_throttle_max <= 0.2, "reset_throttle_max in [0, 0.2]"),
            (self.voltage_filter_s >= 0.02, "voltage_filter_s >= 0.02"),
        )
        for ok, text in checks:
            if not ok:
                raise BatteryDataError("low_voltage_cutoff: " + text)


def session_from_json(battery: dict, low_voltage_cutoff: dict) -> tuple:
    """Parse §3 `propulsion.battery` (kind pack_ecm) and `low_voltage_cutoff` into (Session, LowVoltageCutoff)."""
    if battery.get("kind") != "pack_ecm":
        raise BatteryDataError("battery.kind: expected pack_ecm")
    weak = battery.get("weak_cell", {})
    lvc_json = low_voltage_cutoff
    cfg = LowVoltageCutoff(
        mode=lvc_json["mode"], cell_detection=lvc_json["cell_detection"],
        cutoff_per_cell_v=_scalar(lvc_json["cutoff_per_cell_v"], "V", "lvc.cutoff_per_cell_v"),
        soft_limit=_scalar(lvc_json["soft_limit"], "1", "lvc.soft_limit", positive=False),
        soft_ramp_s=_scalar(lvc_json["soft_ramp_s"], "s", "lvc.soft_ramp_s"),
        debounce_s=_scalar(lvc_json["debounce_s"], "s", "lvc.debounce_s", positive=False),
        recovery=lvc_json["recovery"],
        reset_throttle_max=_scalar(lvc_json["reset_throttle_max"], "1", "lvc.reset_throttle_max", positive=False),
        voltage_filter_s=_scalar(lvc_json["voltage_filter_s"], "s", "lvc.voltage_filter_s"),
        fixed_cells=lvc_json.get("fixed_cells") if lvc_json["cell_detection"] == "fixed" else None,
        detection_max_cell_v=(_scalar(lvc_json["detection_max_cell_v"], "V", "lvc.detection_max_cell_v")
                              if lvc_json["cell_detection"] == "auto" else None),
    )
    session = Session(
        initial_soc=_scalar(battery["initial_soc"], "1", "battery.initial_soc"),
        auxiliary_current_a=_scalar(battery["auxiliary_current_a"], "A", "battery.auxiliary_current_a", positive=False),
        cooling_airflow_fraction=_scalar(battery["cooling_airflow_fraction"], "1", "battery.cooling_airflow_fraction",
                                         positive=False),
        capacity_factor=_scalar(weak["capacity_factor"], "1", "weak_cell.capacity_factor") if weak else 1.0,
        resistance_factor=_scalar(weak["resistance_factor"], "1", "weak_cell.resistance_factor") if weak else 1.0,
        soc_offset=_scalar(weak["soc_offset"], "1", "weak_cell.soc_offset", positive=False) if weak else 0.0,
        voltage_filter_s=cfg.voltage_filter_s,
    )
    return session, cfg


# ---------------------------------------------------------------------------------------------
# Continuous block (§5) and one stage evaluation (§4)
# ---------------------------------------------------------------------------------------------

@dataclass(frozen=True)
class Layout:
    """Offsets inside the battery part of the continuous block (§5 offsets minus s+1)."""

    branches: int

    @property
    def charge(self) -> int:
        return 0

    @property
    def energy(self) -> int:
        return 1

    @property
    def loss(self) -> int:
        return 2

    def v_average(self, k: int) -> int:
        return 3 + k

    def v_weak(self, k: int) -> int:
        return 3 + self.branches + k

    @property
    def temperature(self) -> int:
        return 3 + 2 * self.branches

    @property
    def sensed_voltage(self) -> int:
        return 4 + 2 * self.branches

    @property
    def size(self) -> int:
        return 5 + 2 * self.branches


def layout(pack: Pack) -> Layout:
    return Layout(pack.branches)


@dataclass(frozen=True)
class Inputs:
    """Stage inputs; aux_current_a None means the session's auxiliary current."""

    rpm: float = 0.0
    duty: float = 0.0
    enabled: bool = True
    limit: float = 1.0
    ambient_k: float = 298.15
    airspeed_mps: float = 0.0
    aux_current_a: Optional[float] = None


@dataclass(frozen=True)
class StageResult:
    current_a: float
    voltage_v: float
    motor_current_a: float
    duty: float
    open_circuit_v: float      # E_oc
    path_resistance_ohm: float  # R_p
    z_average: float
    z_weak: float
    ocv_average: float
    ocv_weak: float
    heat_w: float              # pack heat into C_th (excludes R_w)
    loss_w: float              # dH/dt
    stored_energy_rate_w: float  # d/dt of the RC capacitor energy (C·v·dv/dt)
    rates: tuple


def initial_charge_c(pack: Pack, session: Session) -> float:
    """q_w0 = (z0 − Δz) · Q_w."""
    return (session.initial_soc - session.soc_offset) * session.capacity_factor * pack.group_capacity_c


def stage(pack: Pack, session: Session, y: Sequence[float], inputs: Inputs,
          motor: Optional[Motor] = None, exhausted: bool = False) -> StageResult:
    """Evaluate §4 at state y (battery part, order of Layout) and return currents, voltages and rates."""
    lay = layout(pack)
    k_count = pack.branches
    n = pack.series
    q_g = pack.group_capacity_c
    q_w_cap = session.capacity_factor * q_g
    z0 = session.initial_soc
    f_r = session.resistance_factor
    s_r = pack.resistance_factor

    q_w = y[lay.charge]
    q_used = initial_charge_c(pack, session) - q_w
    z_w = q_w / q_w_cap
    z_a = z0 - q_used / q_g
    temp = y[lay.temperature]
    v_a = [y[lay.v_average(k)] for k in range(k_count)]
    v_w = [y[lay.v_weak(k)] for k in range(k_count)]

    ocv_a = lookup(pack.ocv, z_a, temp)
    ocv_w = lookup(pack.ocv, z_w, temp)
    r0_a = s_r * lookup(pack.r0, z_a, temp)
    r0_w = f_r * s_r * lookup(pack.r0, z_w, temp)
    r_a = [s_r * lookup(pack.rc_r[k], z_a, temp) for k in range(k_count)]
    r_w = [f_r * s_r * lookup(pack.rc_r[k], z_w, temp) for k in range(k_count)]
    tau_a = [lookup(pack.rc_tau[k], z_a, temp) for k in range(k_count)]
    tau_w = [lookup(pack.rc_tau[k], z_w, temp) for k in range(k_count)]

    e_oc = (n - 1) * (ocv_a - sum(v_a)) + (ocv_w - sum(v_w))
    r_p = (n - 1) * r0_a + r0_w + pack.interconnect_ohm
    i_aux = session.auxiliary_current_a if inputs.aux_current_a is None else inputs.aux_current_a
    duty = min(inputs.duty, inputs.limit) if inputs.enabled else 0.0

    if exhausted:
        current, motor_current, voltage, duty = 0.0, 0.0, e_oc, 0.0
    else:
        v0 = e_oc - r_p * i_aux
        if not v0 > 0.0:
            raise ArithmeticError(f"§4 connected law needs V0 > 0 (V0 = {v0})")
        motor_current = 0.0
        if duty > 0.0:
            if motor is None:
                raise ValueError("a positive duty needs a motor")
            back_emf = inputs.rpm / motor.kv_rpm_per_v
            motor_current = max((duty * v0 - back_emf) / (motor.resistance_ohm + duty * duty * r_p), 0.0)
        current = duty * motor_current + i_aux
        voltage = e_oc - r_p * current
        if not voltage > 0.0:
            raise ArithmeticError(f"§4 connected law needs V > 0 (V = {voltage})")

    rc_heat = (n - 1) * sum(v * v / r for v, r in zip(v_a, r_a)) + sum(v * v / r for v, r in zip(v_w, r_w))
    loss = current * current * r_p + rc_heat
    heat = current * current * ((n - 1) * r0_a + r0_w) + rc_heat
    cooling = session.cooling_airflow_fraction * abs(inputs.airspeed_mps)
    d_temp = (heat - pack.hA(cooling) * (temp - inputs.ambient_k)) / pack.thermal_capacity_j_per_k
    dv_a = [(r * current - v) / t for v, r, t in zip(v_a, r_a, tau_a)]
    dv_w = [(r * current - v) / t for v, r, t in zip(v_w, r_w, tau_w)]
    d_sense = (voltage - y[lay.sensed_voltage]) / session.voltage_filter_s
    stored = (n - 1) * sum((t / r) * v * dv for v, r, t, dv in zip(v_a, r_a, tau_a, dv_a)) \
        + sum((t / r) * v * dv for v, r, t, dv in zip(v_w, r_w, tau_w, dv_w))

    rates = [0.0] * lay.size
    rates[lay.charge] = -current
    rates[lay.energy] = voltage * current
    rates[lay.loss] = loss
    for k in range(k_count):
        rates[lay.v_average(k)] = dv_a[k]
        rates[lay.v_weak(k)] = dv_w[k]
    rates[lay.temperature] = d_temp
    rates[lay.sensed_voltage] = d_sense
    return StageResult(current, voltage, motor_current, duty, e_oc, r_p, z_a, z_w, ocv_a, ocv_w,
                       heat, loss, stored, tuple(rates))


def rates(pack: Pack, session: Session, y: Sequence[float], inputs: Inputs,
          motor: Optional[Motor] = None, exhausted: bool = False) -> tuple:
    return stage(pack, session, y, inputs, motor, exhausted).rates


def reset(pack: Pack, session: Session, ambient_k: float, aux_current_a: Optional[float] = None) -> list:
    """§5 reset: q_w0, zero energy/loss/RC, T = T_amb, v_s = E_oc − R_p·I_aux."""
    lay = layout(pack)
    y = [0.0] * lay.size
    y[lay.charge] = initial_charge_c(pack, session)
    y[lay.temperature] = ambient_k
    y[lay.sensed_voltage] = rest_voltage(pack, session, y, aux_current_a)
    return y


def rest_voltage(pack: Pack, session: Session, y: Sequence[float], aux_current_a: Optional[float] = None) -> float:
    """V_rest = E_oc − R_p·I_aux at the given state (used for reset and cell detection)."""
    i_aux = session.auxiliary_current_a if aux_current_a is None else aux_current_a
    probe = stage(pack, session, y, Inputs(duty=0.0, aux_current_a=i_aux, ambient_k=y[layout(pack).temperature]))
    return probe.open_circuit_v - probe.path_resistance_ohm * i_aux


# ---------------------------------------------------------------------------------------------
# ESC supervisor (§6)
# ---------------------------------------------------------------------------------------------

@dataclass(frozen=True)
class SupervisorState:
    limit: float = 1.0
    phase: int = 0       # 0 normal, 1 debounce, 2 soft cut, 3 hard cut
    timer: float = 0.0
    cells: int = 1


def detect_cells(cfg: LowVoltageCutoff, rest_voltage_v: float) -> int:
    """§6 cell detection at connection."""
    if cfg.cell_detection == "fixed":
        return int(cfg.fixed_cells)
    return max(1, int(math.ceil(rest_voltage_v / cfg.detection_max_cell_v - DETECTION_TOLERANCE)))


def supervisor_reset(cfg: LowVoltageCutoff, rest_voltage_v: float) -> SupervisorState:
    return SupervisorState(1.0, 0, 0.0, detect_cells(cfg, rest_voltage_v))


def supervisor_step(cfg: LowVoltageCutoff, state: SupervisorState, sensed_v: float, throttle: float,
                    dt: float) -> SupervisorState:
    """§6 sampled update after an accepted tick. The returned limit applies to the next tick."""
    cells = state.cells
    if cfg.mode == "off":
        return SupervisorState(1.0, 0, 0.0, cells)
    threshold = cells * cfg.cutoff_per_cell_v
    phase, timer = state.phase, state.timer

    if phase in (2, 3):
        if cfg.recovery == "throttle_reset" and throttle <= cfg.reset_throttle_max and sensed_v >= threshold:
            return SupervisorState(1.0, 0, 0.0, cells)
        if phase == 2:
            timer += dt
            fraction = 1.0 if timer >= cfg.soft_ramp_s - TIMER_TOLERANCE_S else timer / cfg.soft_ramp_s
            limit = max(cfg.soft_limit, 1.0 - (1.0 - cfg.soft_limit) * fraction)
            return SupervisorState(limit, 2, timer, cells)
        return SupervisorState(0.0, 3, timer, cells)  # hard cut: timer not advanced

    if phase == 0:
        if sensed_v < threshold:
            phase, timer = 1, dt
        else:
            timer = 0.0
    else:
        if sensed_v >= threshold:
            phase, timer = 0, 0.0
        else:
            timer += dt
    if phase == 1 and timer >= cfg.debounce_s - TIMER_TOLERANCE_S:
        if cfg.mode == "soft":
            return SupervisorState(1.0, 2, 0.0, cells)  # ramp starts on the next sample
        return SupervisorState(0.0, 3, 0.0, cells)
    return SupervisorState(1.0, phase, timer, cells)


# ---------------------------------------------------------------------------------------------
# Integration
# ---------------------------------------------------------------------------------------------

def rk4_step(f: Callable[[float, Sequence[float]], Sequence[float]], t: float, y: Sequence[float], h: float) -> list:
    """One classical fourth-order Runge–Kutta step."""
    k1 = f(t, y)
    y2 = [a + 0.5 * h * b for a, b in zip(y, k1)]
    k2 = f(t + 0.5 * h, y2)
    y3 = [a + 0.5 * h * b for a, b in zip(y, k2)]
    k3 = f(t + 0.5 * h, y3)
    y4 = [a + h * b for a, b in zip(y, k3)]
    k4 = f(t + h, y4)
    return [a + h / 6.0 * (b1 + 2.0 * b2 + 2.0 * b3 + b4) for a, b1, b2, b3, b4 in zip(y, k1, k2, k3, k4)]


def _locate_zero(f, t: float, y: Sequence[float], h: float, index: int) -> float:
    """Smallest step h* in (0, h] with the RK4 polynomial component `index` reaching 0 (bisection)."""
    lo, hi = 0.0, h
    while hi - lo > EVENT_TIME_TOLERANCE_S:
        mid = 0.5 * (lo + hi)
        if rk4_step(f, t, y, mid)[index] > 0.0:
            lo = mid
        else:
            hi = mid
    return hi


@dataclass(frozen=True)
class TickInputs:
    """Inputs held over one tick (zero-order hold)."""

    duty: float = 0.0
    rpm: float = 0.0
    enabled: bool = True
    aux_current_a: Optional[float] = None
    ambient_k: float = 298.15
    airspeed_mps: float = 0.0


@dataclass(frozen=True)
class Sample:
    t: float
    current_a: float
    voltage_v: float
    sensed_v: float
    z_average: float
    z_weak: float
    temperature_k: float
    state: tuple
    limit: float
    phase: int
    cells: int
    exhausted: bool


def simulate(pack: Pack, session: Session, tick_inputs: Callable[[float], TickInputs], t_end: float, dt: float,
             motor: Optional[Motor] = None, lvc: Optional[LowVoltageCutoff] = None, substeps: int = 1,
             ambient_k: Optional[float] = None,
             prescribed_temperature: Optional[Callable[[float], float]] = None) -> dict:
    """Integrate the battery block with RK4 ticks of length dt (each split into `substeps` RK4 steps).

    tick_inputs(t) gives the zero-order-hold inputs of the tick starting at t. The ESC supervisor (if lvc is
    given) is sampled after every tick and its limit applies to the next tick. The exhaustion of the weak
    cell (q_w = 0) is located to 1e-12 s; afterwards the pack is disconnected (I = 0, V = E_oc).
    prescribed_temperature(t), if given, replaces the thermal state at every tick start and freezes dT/dt
    (a validation helper for replaying measured cell temperatures; not part of the runtime law).
    Returns {"samples": [...], "exhausted_at": t or None}.
    """
    lay = layout(pack)
    first = tick_inputs(0.0)
    t_amb0 = first.ambient_k if ambient_k is None else ambient_k
    y = reset(pack, session, t_amb0 if prescribed_temperature is None else prescribed_temperature(0.0),
              first.aux_current_a)
    sup = supervisor_reset(lvc, y[lay.sensed_voltage]) if lvc is not None else SupervisorState()
    exhausted = False
    exhausted_at = None
    n_ticks = int(round(t_end / dt))
    samples = []

    def evaluate(inp: TickInputs):
        return stage(pack, session, y, Inputs(inp.rpm, inp.duty, inp.enabled, sup.limit, inp.ambient_k,
                                              inp.airspeed_mps, inp.aux_current_a), motor, exhausted)

    def record(t: float, res: StageResult) -> None:
        samples.append(Sample(t, res.current_a, res.voltage_v, y[lay.sensed_voltage], res.z_average, res.z_weak,
                              y[lay.temperature], tuple(y), sup.limit, sup.phase, sup.cells, exhausted))

    record(0.0, evaluate(first))
    t = 0.0
    for tick in range(n_ticks):
        inp = tick_inputs(t)
        if prescribed_temperature is not None:
            y[lay.temperature] = prescribed_temperature(t)
        h = dt / substeps
        for _ in range(substeps):
            def f(_t: float, state: Sequence[float], _ex: bool = exhausted) -> list:
                r = list(rates(pack, session, state, Inputs(inp.rpm, inp.duty, inp.enabled, sup.limit, inp.ambient_k,
                                                            inp.airspeed_mps, inp.aux_current_a), motor, _ex))
                if prescribed_temperature is not None:
                    r[lay.temperature] = 0.0
                return r

            y_next = rk4_step(f, t, y, h)
            if not exhausted and y_next[lay.charge] <= 0.0:
                h_star = _locate_zero(f, t, y, h, lay.charge)
                y = rk4_step(f, t, y, h_star)
                y[lay.charge] = 0.0
                exhausted = True
                exhausted_at = t + h_star
                t += h_star
                rest = h - h_star
                if rest > 0.0:
                    def g(_t: float, state: Sequence[float]) -> list:
                        r = list(rates(pack, session, state, Inputs(inp.rpm, inp.duty, inp.enabled, sup.limit,
                                                                    inp.ambient_k, inp.airspeed_mps,
                                                                    inp.aux_current_a), motor, True))
                        if prescribed_temperature is not None:
                            r[lay.temperature] = 0.0
                        return r
                    y = rk4_step(g, t, y, rest)
                    t += rest
            else:
                y = y_next
                t += h
        t = (tick + 1) * dt
        left_limit = evaluate(inp)  # endpoint values with this tick's inputs (left limit)
        if lvc is not None:
            sup = supervisor_step(lvc, sup, y[lay.sensed_voltage], inp.duty, dt)
        record(t, left_limit)
    return {"samples": samples, "exhausted_at": exhausted_at}


def simulate_current(pack: Pack, session: Session, current_a: Callable[[float], float], t_end: float, dt: float,
                     ambient_k: float = 298.15, airspeed_mps: float = 0.0,
                     prescribed_temperature: Optional[Callable[[float], float]] = None, substeps: int = 1) -> dict:
    """Prescribed pack current (discharge positive), carried as the §4 auxiliary current with the motor off."""
    def inputs(t: float) -> TickInputs:
        return TickInputs(duty=0.0, rpm=0.0, enabled=False, aux_current_a=max(current_a(t), 0.0),
                          ambient_k=ambient_k, airspeed_mps=airspeed_mps)
    return simulate(pack, replace(session, auxiliary_current_a=0.0), inputs, t_end, dt, substeps=substeps,
                    prescribed_temperature=prescribed_temperature)


def simulate_motor(pack: Pack, session: Session, motor: Motor, duty: Callable[[float], float],
                   rpm: Callable[[float], float], t_end: float, dt: float, lvc: Optional[LowVoltageCutoff] = None,
                   ambient_k: float = 298.15, airspeed_mps: float = 0.0, substeps: int = 1) -> dict:
    """Prescribed (motor duty, rpm) profile with the session auxiliary current and an optional ESC supervisor."""
    def inputs(t: float) -> TickInputs:
        return TickInputs(duty=duty(t), rpm=rpm(t), enabled=True, aux_current_a=None, ambient_k=ambient_k,
                          airspeed_mps=airspeed_mps)
    return simulate(pack, session, inputs, t_end, dt, motor=motor, lvc=lvc, substeps=substeps)


def single_cell_pack(template: dict, cell_mass_kg: float = 0.05, still_air_w_per_k: float = 0.1,
                     forced: float = 0.0, interconnect_ohm: float = 0.0) -> dict:
    """A 1S1P pack file on a template at its reference capacity (s_R = 1), for replaying cell data."""
    def q(value, unit):
        return {"value": value, "unit": unit, "kind": "derived", "source": "ecm_reference.single_cell_pack"}
    return {
        "format": PACK_FORMAT, "id": "single-cell-" + template["id"], "display_name": "single cell",
        "class_note": "test pack", "chemistry": template["chemistry"],
        "cell_template": {"id": template["id"], "sha256": "0" * 64}, "series": 1, "parallel": 1,
        "rated_capacity_ah": q(template["reference_capacity_ah"]["value"], "Ah"),
        "resistance_scale": q(1.0, "1"), "interconnect_resistance_ohm": q(interconnect_ohm, "ohm"),
        "mass_kg": q(cell_mass_kg, "kg"), "dimensions_m": q([0.065, 0.0185, 0.0185], "m"),
        "heat_transfer": {"still_air_w_per_k": q(still_air_w_per_k, "W/K"),
                          "forced_w_per_k_per_sqrt_mps": q(forced, "W/(K·(m/s)^0.5)")},
        "label": {"c_rating_continuous": None, "c_rating_burst": None, "source": "test"},
    }
