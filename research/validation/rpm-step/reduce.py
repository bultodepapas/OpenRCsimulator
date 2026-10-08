#!/usr/bin/env python3
"""VAL-7b: sampled RPM step diagnostics; never writes aircraft parameters."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys


LIMITATIONS = [
    "Endpoints must come from identified steady windows; the last sample is not assumed to be steady.",
    "First directional crossings use linear interpolation, without smoothing or sorting samples.",
    "Sampling-support intervals are not confidence intervals; measurement and endpoint uncertainties are retained but not propagated.",
    "Lag and delay are a two-crossing first-order diagnostic, not an engine/servo identification or held-out validation.",
    "RMSE uses equal sample weights on this same record; dense sampling can overweight one part of a transient.",
    "Command timing, sensor filtering, synchronization and RPM harmonic selection must be established externally.",
    "No acceptance tolerance or physical-validation decision is inferred from these results.",
]


def fields(obj, names, where):
    if not isinstance(obj, dict) or set(obj) != set(names):
        raise ValueError(f"{where}: expected exactly {sorted(names)}")


def text(value, where):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{where}: expected nonempty text")


def number(value, where, nonnegative=False):
    if type(value) not in (int, float) or not math.isfinite(value):
        raise ValueError(f"{where}: expected finite number, not boolean/string")
    if nonnegative and value < 0:
        raise ValueError(f"{where}: expected nonnegative number")
    return float(value)


def finite(value):
    if not math.isfinite(value):
        raise ValueError("derived result outside finite range")
    return value


def unique_object(pairs):
    out = {}
    for key, value in pairs:
        if key in out:
            raise ValueError(f"duplicate JSON key: {key}")
        out[key] = value
    return out


def load(raw):
    def bad_constant(value):
        raise ValueError(f"nonfinite JSON constant: {value}")
    return json.loads(raw, object_pairs_hook=unique_object, parse_constant=bad_constant)


def provenance(obj, evidence, where):
    if obj['kind'] not in ('synthetic', 'measured', 'derived'):
        raise ValueError(f"{where}: expected synthetic/measured/derived kind")
    if evidence == 'measured' and obj['kind'] == 'synthetic':
        raise ValueError(f"{where}: synthetic input in measured campaign")
    text(obj['source'], f"{where}.source")


def quantity(obj, unit, evidence, where):
    fields(obj, ('value', 'unit', 'u', 'kind', 'source'), where)
    if obj['unit'] != unit:
        raise ValueError(f"{where}: expected {unit}")
    provenance(obj, evidence, where)
    number(obj['u'], f"{where}.u", nonnegative=True)
    return number(obj['value'], where, nonnegative=(unit == 'rpm'))


def crossing(times, values, level, command):
    hits = []
    for i in range(1, len(times)):
        if values[i-1] < level <= values[i]:
            fraction = (level-values[i-1])/(values[i]-values[i-1])
            at = finite(times[i-1] + fraction*(times[i]-times[i-1]))
            hits.append((at, i))
    if not hits:
        raise ValueError(f"response never brackets {level:.6g} crossing")
    at, i = hits[0]
    if at < command:
        raise ValueError(f"first {level:.6g} crossing precedes command; check synchronization")
    return {'time_s': at, 'after_command_s': finite(at-command),
            'sample_indices': [i-1, i], 'sampling_support_s': [times[i-1], times[i]],
            'forward_crossing_count': len(hits)}


def reduce(document):
    fields(document, ('format', 'evidence', 'configuration', 'notes', 'command_time',
                      'initial_rpm', 'final_rpm', 'series'), 'input')
    if document['format'] != 'openrc-rpm-step v1':
        raise ValueError('unsupported input format')
    evidence = document['evidence']
    if evidence not in ('synthetic', 'measured'):
        raise ValueError('evidence: expected synthetic or measured')
    for name in ('configuration', 'notes'):
        text(document[name], name)
    command = quantity(document['command_time'], 's', evidence, 'command_time')
    initial = quantity(document['initial_rpm'], 'rpm', evidence, 'initial_rpm')
    final = quantity(document['final_rpm'], 'rpm', evidence, 'final_rpm')
    amplitude = finite(final-initial)
    if amplitude == 0:
        raise ValueError('steady RPM endpoints must differ')
    series = document['series']
    fields(series, ('kind', 'source', 'time_u_s', 'rpm_u', 'samples'), 'series')
    provenance(series, evidence, 'series')
    number(series['time_u_s'], 'series.time_u_s', nonnegative=True)
    number(series['rpm_u'], 'series.rpm_u', nonnegative=True)
    samples = series['samples']
    if not isinstance(samples, list) or len(samples) < 3:
        raise ValueError('series.samples: need at least three [time_s, rpm] pairs')
    times, values = [], []
    for i, pair in enumerate(samples):
        if not isinstance(pair, list) or len(pair) != 2:
            raise ValueError(f'sample {i}: expected [time_s, rpm]')
        t = number(pair[0], f'sample {i} time')
        rpm = number(pair[1], f'sample {i} rpm', nonnegative=True)
        if times and t <= times[-1]:
            raise ValueError('sample times must be strictly increasing')
        times.append(t)
        values.append(finite((rpm-initial)/amplitude))
    if not times[0] <= command < times[-1]:
        raise ValueError('record must include command time and subsequent response')
    if values[0] >= 0.1:
        raise ValueError('record starts above 10% response; onset is missing')
    span = finite(times[-1]-times[0])
    crossings = {name: crossing(times, values, level, command) for name, level in
                 (('10', .1), ('63', -math.expm1(-1)), ('90', .9))}
    t10, t90 = crossings['10']['time_s'], crossings['90']['time_s']
    rise = finite(t90-t10)
    tau = finite(rise/math.log(9))
    if tau <= 0:
        raise ValueError('response times cannot resolve a positive lag')
    delay = finite(t10-command + tau*math.log(.9))
    lo10, hi10 = crossings['10']['sampling_support_s']
    lo90, hi90 = crossings['90']['sampling_support_s']
    a = -math.log(.9)/math.log(9)
    tau_support = [max(0., (lo90-hi10)/math.log(9)), (hi90-lo10)/math.log(9)]
    delay_support = [finite((lo10-command)+a*(lo10-hi90)),
                     finite((hi10-command)+a*(hi10-lo90))]
    residuals = []
    for t, z in zip(times, values):
        elapsed = finite(t-command-delay)
        predicted = -math.expm1(-elapsed/tau) if elapsed > 0 else 0.
        residuals.append(finite(z-predicted))
    rmse = finite(math.hypot(*residuals)/math.sqrt(len(residuals)))
    backstep = max([0.] + [values[i-1]-values[i] for i in range(1, len(values))])
    warnings = []
    if delay < 0:
        warnings.append('Negative inferred delay: no causal delayed first-order interpretation at this command time.')
    if backstep > 0:
        warnings.append('Response reverses between samples; first crossings may be noise-sensitive.')
    if any(c['forward_crossing_count'] > 1 for c in crossings.values()):
        warnings.append('Repeated threshold crossings: inspect raw data before interpreting response times.')
    if max(values) > 1:
        warnings.append('Samples exceed the supplied final endpoint (overshoot or endpoint/noise mismatch).')
    if crossings['10']['sample_indices'] == crossings['90']['sample_indices']:
        warnings.append('10% and 90% fall in one sample interval: the transient is under-resolved.')
    return {'format': 'openrc-rpm-step-result v1', 'kind': 'derived', 'input': document,
            'direction': 'increasing' if amplitude > 0 else 'decreasing',
            'sample_count': len(times), 'record_span_s': span, 'endpoint_span_rpm': amplitude,
            'crossings': crossings, 'normalized_residuals': residuals,
            'first_order_diagnostic': {
                'rise_10_90_s': rise, 'tau_s': tau, 'delay_s': delay,
                'tau_sampling_support_s': [finite(v) for v in tau_support],
                'delay_sampling_support_s': delay_support,
                'causal_delay': delay >= 0,
                't63_consistency_error_s': finite(crossings['63']['after_command_s']-delay-tau),
                'normalized_rmse': rmse,
                'rpm_rmse': finite(rmse*abs(amplitude)),
                'max_abs_normalized_residual': max(abs(r) for r in residuals)},
            'observed': {'max_backward_fraction_step': finite(backstep),
                         'overshoot_fraction': finite(max(0., max(values)-1)),
                         'minimum_fraction': min(values), 'final_sample_fraction': values[-1]},
            'warnings': warnings, 'limitations': LIMITATIONS}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    args = parser.parse_args()
    try:
        raw = args.input.read_bytes()
        result = reduce(load(raw))
        result['input_sha256'] = hashlib.sha256(raw).hexdigest()
        result['reducer_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        rendered = json.dumps(result, indent=2, allow_nan=False) + '\n'
    except (OSError, ValueError, TypeError, OverflowError, ZeroDivisionError, RecursionError) as exc:
        print(f'RPM step reduction failed: {exc}', file=sys.stderr)
        return 1
    sys.stdout.write(rendered)
    return 0


if __name__ == '__main__':
    sys.exit(main())
