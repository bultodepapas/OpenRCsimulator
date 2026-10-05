// Does 32-bit float storage (the Float32Array default of gl-matrix and
// wgpu-matrix) lose small accelerations in a 240 Hz flight integrator?
// Node only, no dependencies: `node research/float32_vs_float64_integration.mjs`
//
// Scenario: 60 s of explicit Euler at 240 Hz, cruising at 20 m/s at x = 300 m,
// with a small steady acceleration (e.g. a slight thrust/drag imbalance).
// float32 is emulated by rounding every intermediate with Math.fround.
// This checks storage precision only; it says nothing about aerodynamics.

const f = Math.fround;
const dt = 1 / 240;
const steps = 240 * 60;

for (const a of [1e-1, 1e-2, 1e-3, 1e-4]) {
  let v64 = 20, x64 = 300;
  let v32 = f(20), x32 = f(300);
  for (let i = 0; i < steps; i++) {
    v64 += a * dt;
    x64 += v64 * dt;
    v32 = f(v32 + f(f(a) * f(dt)));
    x32 = f(x32 + f(v32 * f(dt)));
  }
  const exact = a * 60;
  console.log(
    `a=${a.toExponential(0)} m/s²  ` +
    `Δv float64=${(v64 - 20).toExponential(4)}  ` +
    `Δv float32=${(v32 - 20).toExponential(4)}  ` +
    `(exact ${exact.toExponential(4)})  ` +
    `position diff=${(x32 - x64).toFixed(4)} m`,
  );
}
