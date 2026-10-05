// Scripted Stage 0 motion in the world NED frame. No renderer imports.
import { CIRCLE, G } from '../spec';

export interface Pose {
  /** Position, NED, meters. */
  ned: [number, number, number];
  /** Yaw, pitch, roll in radians (aerospace ZYX order). */
  yaw: number;
  pitch: number;
  roll: number;
}

export function poseAt(t: number): Pose {
  const { centerNorth, centerEast, altitude, radius, speed } = CIRCLE;
  const omega = speed / radius;
  const a = omega * t;
  return {
    ned: [centerNorth + radius * Math.cos(a), centerEast + radius * Math.sin(a), -altitude],
    yaw: a + Math.PI / 2,
    pitch: 0,
    roll: Math.atan((speed * speed) / (G * radius)),
  };
}
