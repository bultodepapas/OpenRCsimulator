"""Reproduce the notebook's static APC Sport 11x6 comparison; Python stdlib only.

Factual coefficient extracts inspected 2026-10-05:
UIUC: https://m-selig.ae.illinois.edu/props/volume-1/data/apcsp_11x6_static_rd0488.txt
APC: https://www.apcprop.com/files/PER3_11x6.dat
APC header: v2022-0915, simulation date 09/22/2022.
UIUC raw-file SHA256: 911866f1c55bb115f3fef2202fb73a8e0ecf271746d71e7a0c773b7f11cd33f9
APC static rows were transcribed from the browser extraction; no raw-file hash.
Columns in each tuple: rpm, dimensionless thrust coefficient, power coefficient.
This compares historical data sources, not a tested nitro engine installation.
"""

from statistics import mean

MEASURED = [
    (1752, .0917, .0514), (2055, .0945, .0505),
    (2360, .0978, .0506), (2657, .0989, .0499),
    (2982, .1016, .0503), (3265, .1026, .0499),
    (3565, .1034, .0493), (3857, .1056, .0491),
    (4161, .1068, .0485), (4444, .1078, .0481),
    (4736, .1091, .0478), (5042, .1111, .0477),
    (5369, .1114, .0473), (5654, .1121, .0471),
    (5954, .1130, .0471), (6259, .1129, .0468),
]
PREDICTED = [
    (1000, .1045, .0549), (2000, .1051, .0473),
    (3000, .1054, .0441), (4000, .1057, .0424),
    (5000, .1060, .0413), (6000, .1064, .0405),
    (7000, .1068, .0400),
]


def interpolate(rpm):
    for lower, upper in zip(PREDICTED, PREDICTED[1:]):
        if lower[0] <= rpm <= upper[0]:
            fraction = (rpm - lower[0]) / (upper[0] - lower[0])
            return tuple(lower[i] + fraction * (upper[i] - lower[i])
                         for i in (1, 2))
    raise ValueError(f"RPM {rpm} outside prediction coverage; no extrapolation")


def main():
    errors = [[], []]
    print('| RPM | Measured Ct | Predicted Ct | Ct difference | Measured Cp | Predicted Cp | Cp difference |')
    print('| --- | --- | --- | --- | --- | --- | --- |')
    for rpm, ct, cp in MEASURED:
        pt, pp = interpolate(rpm)
        et, ep = 100 * (pt / ct - 1), 100 * (pp / cp - 1)
        errors[0].append(et)
        errors[1].append(ep)
        print(f'| {rpm} | {ct:.4f} | {pt:.5f} | {et:+.2f}% | {cp:.4f} | {pp:.5f} | {ep:+.2f}% |')
    for label, values in zip(('Ct', 'Cp'), errors):
        print(f'{label}: mean signed={mean(values):+.2f}%; '
              f'mean absolute={mean(map(abs, values)):.2f}%; '
              f'range={min(values):+.2f}% to {max(values):+.2f}%')


if __name__ == '__main__':
    main()
