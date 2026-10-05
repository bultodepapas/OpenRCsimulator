// Every number from ../../SPEC.md lives here, once.

export const G = 9.80665;

export const CIRCLE = {
  centerNorth: 60,
  centerEast: 0,
  altitude: 20,
  radius: 40,
  speed: 15,
  propRevPerSec: 10,
};

export const COLORS = {
  red: 0xc8102e,
  white: 0xf2f2f2,
  dark: 0x222222,
  darkGrey: 0x333333,
  black: 0x111111,
  grass: 0x4a7a32,
  runway: 0x6f9a4a,
  sky: 0x9cc9ef,
};

type Vec3 = [number, number, number];
export interface BoxPart { name: string; size: Vec3; center: Vec3; color: number }
export interface WingPart { name: string; size: Vec3; center: Vec3; top: number; bottom: number }
export interface WheelPart { name: string; diameter: number; width: number; center: Vec3; color: number }

// Das Ugly Stik 60. Model axes: +x right, +y up, -z forward. Origin near the CG.
export const BOXES: BoxPart[] = [
  { name: 'fuselage', size: [0.11, 0.15, 1.14], center: [0, 0, 0.13], color: COLORS.red },
  { name: 'cowl', size: [0.1, 0.13, 0.08], center: [0, 0, -0.48], color: COLORS.darkGrey },
  { name: 'stab', size: [0.56, 0.02, 0.13], center: [0, 0, 0.635], color: COLORS.red },
  { name: 'fin', size: [0.02, 0.17, 0.14], center: [0, 0.155, 0.63], color: COLORS.white },
  { name: 'propeller', size: [0.305, 0.025, 0.01], center: [0, 0, -0.54], color: COLORS.black },
];

// Wing panels have a dark underside, for orientation.
export const WINGS: WingPart[] = [
  { name: 'wing_center', size: [1.124, 0.035, 0.226], center: [0, 0.03, 0.023], top: COLORS.red, bottom: COLORS.dark },
  { name: 'wing_tip_left', size: [0.2, 0.035, 0.226], center: [-0.662, 0.03, 0.023], top: COLORS.white, bottom: COLORS.dark },
  { name: 'wing_tip_right', size: [0.2, 0.035, 0.226], center: [0.662, 0.03, 0.023], top: COLORS.white, bottom: COLORS.dark },
];

// Control surfaces pivot on their leading edge (hinge line).
export const SURFACES: BoxPart[] = [
  { name: 'aileron_left', size: [0.62, 0.02, 0.08], center: [-0.39, 0.03, 0.176], color: COLORS.red },
  { name: 'aileron_right', size: [0.62, 0.02, 0.08], center: [0.39, 0.03, 0.176], color: COLORS.red },
  { name: 'elevator', size: [0.56, 0.02, 0.07], center: [0, 0, 0.735], color: COLORS.red },
  { name: 'rudder', size: [0.02, 0.19, 0.07], center: [0, 0.165, 0.735], color: COLORS.white },
];

export const WHEELS: WheelPart[] = [
  { name: 'nosewheel', diameter: 0.07, width: 0.025, center: [0, -0.19, -0.4], color: COLORS.black },
  { name: 'gear_left', diameter: 0.076, width: 0.028, center: [-0.17, -0.19, 0.05], color: COLORS.black },
  { name: 'gear_right', diameter: 0.076, width: 0.028, center: [0.17, -0.19, 0.05], color: COLORS.black },
];

export const GROUND = { size: 2000 };
export const RUNWAY = { lengthEastWest: 100, widthNorthSouth: 12, centerNorth: 15 };

export const SUN = { azimuthFromNorthDeg: 225, elevationDeg: 45 }; // south-west

export const CAMERA = { eyeHeight: 1.7, fovDeg: 50, near: 0.1, far: 3000 };

export const CAPTURE = { time: 3.0, width: 1280, height: 720 };
