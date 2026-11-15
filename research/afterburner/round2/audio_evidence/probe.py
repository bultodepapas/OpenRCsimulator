"""Analytical sanity checks, not application playback or measured recordings."""
from math import cos, log10, pi, sin, sqrt


def db_power(x):
    return '-infinity' if x <= 1e-15 else f'{10 * log10(x):+.3f} dB'


print('Crossfade midpoint; equal input mean-square power; rho = normalized correlation')
for name, g1, g2 in [('linear', 0.5, 0.5), ('equal_power', cos(pi / 4), sin(pi / 4))]:
    for rho in (-1.0, 0.0, 1.0):
        power = g1 * g1 + g2 * g2 + 2 * rho * g1 * g2
        print(f'{name:11s} rho={rho:+.1f}: power={power:.6f}, level={db_power(power)}')

c = 343.0
print('\nPropagation, stationary source-to-listener initial distance = 100 m, c = 343 m/s')
print(f'stationary listener delay = {100 / c:.6f} s')
print(f'listener approaches source at 10 m/s: arrival = {100 / (c + 10):.6f} s')
print(f'source approaches at 40 m/s, listener stationary: f_obs/f_source = {c / (c - 40):.6f}')
print(f'source approaches at 40 m/s, listener approaches at 10 m/s: ratio = {(c + 10) / (c - 40):.6f}')

print('\nTwo sampled AB values across an instantaneous onset: linear interpolation leak')
t_old, t_event = 0.0, 0.1
query = 0.05
alpha = (query - t_old) / (t_event - t_old)
print(f'event emission {t_event:.3f} s; queried emission {query:.3f} s; 0-to-1 interpolation = {alpha:.3f} (causal step must be 0)')

print('\nWAV storage, 48 kHz, mono, 16-bit PCM, 10 seconds')
print(f'{48000 * 1 * 2 * 10} data bytes ({48000 * 1 * 2 * 10 / 1e6:.2f} MB decimal), excluding headers and runtime copies')
