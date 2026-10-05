// The one place where world NED / body FRD meet the Y-up render frame.
// Render axes: x = east, y = -down, z = -north. M maps (N, E, D) to (x, y, z).
import { Matrix4, Vector3 } from 'three';

type M3 = number[][];

const M: M3 = [
  [0, 1, 0],
  [0, 0, -1],
  [-1, 0, 0],
];

const mul = (a: M3, b: M3): M3 =>
  a.map((row) => b[0].map((_, j) => row.reduce((s, v, k) => s + v * b[k][j], 0)));
const transpose = (a: M3): M3 => a[0].map((_, j) => a.map((row) => row[j]));

export function nedToRender([n, e, d]: [number, number, number]): Vector3 {
  return new Vector3(e, -d, -n);
}

/** Body-to-NED rotation from ZYX Euler angles, expressed in render axes. */
export function attitudeToRender(yaw: number, pitch: number, roll: number): Matrix4 {
  const [cy, sy, cp, sp, cr, sr] = [
    Math.cos(yaw), Math.sin(yaw), Math.cos(pitch), Math.sin(pitch), Math.cos(roll), Math.sin(roll),
  ];
  const rNed: M3 = [
    [cy * cp, cy * sp * sr - sy * cr, cy * sp * cr + sy * sr],
    [sy * cp, sy * sp * sr + cy * cr, sy * sp * cr - cy * sr],
    [-sp, cp * sr, cp * cr],
  ];
  const r = mul(mul(M, rNed), transpose(M));
  return new Matrix4().set(
    r[0][0], r[0][1], r[0][2], 0,
    r[1][0], r[1][1], r[1][2], 0,
    r[2][0], r[2][1], r[2][2], 0,
    0, 0, 0, 1,
  );
}
