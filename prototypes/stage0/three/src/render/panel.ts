// On-screen input panel: raw -> command -> surface angle, for every channel.
import { surfaceDeflectionsDeg, type Commands, type Raw } from '../input/commands';

const el = document.createElement('pre');
el.style.cssText =
  'position:fixed;top:8px;left:8px;margin:0;padding:8px 10px;background:rgba(0,0,0,.6);color:#fff;' +
  'font:13px/1.35 ui-monospace,monospace;border-radius:4px;pointer-events:none';
document.body.appendChild(el);

const f = (v: number, d = 2) => (v >= 0 ? '+' : '') + v.toFixed(d);

export function updatePanel(raw: Raw, c: Commands, view: string) {
  const s = surfaceDeflectionsDeg(c);
  el.textContent = [
    'channel   raw   command  surface',
    `roll     ${f(raw.roll, 0)}    ${f(c.roll)}   R ail ${f(s.aileron_right, 1)}°`,
    `pitch    ${f(raw.pitch, 0)}    ${f(c.pitch)}   elev  ${f(s.elevator, 1)}°`,
    `yaw      ${f(raw.yaw, 0)}    ${f(c.yaw)}   rud   ${f(s.rudder, 1)}°`,
    `throttle ${f(raw.throttle, 0)}    ${(c.throttle * 100).toFixed(0).padStart(4)}%`,
    `view: ${view}   [C] view  [R] reset`,
  ].join('\n');
}
