// End-to-end input check in a real browser: key -> raw -> limiter -> panel.
import { build, preview } from 'vite';
import { chromium } from 'playwright';

await build({ logLevel: 'warn' });
const server = await preview({ preview: { port: 4318, strictPort: true } });
const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
await page.goto('http://localhost:4318/');
const panel = () => page.locator('pre').textContent();
const row = async (name) => (await panel()).split('\n').find((l) => l.startsWith(name));
let failures = 0;
const check = (label, ok, detail) => { if (!ok) { failures++; console.error('FAIL', label, detail); } else console.log('ok  ', label); };

await page.keyboard.down('ArrowRight');
await page.waitForTimeout(500); // limiter needs 0.25 s
let r = await row('roll');
check('hold → roll +1, aileron +20°', r.includes('+1') && r.includes('+1.00') && r.includes('+20.0°'), r);
await page.keyboard.up('ArrowRight');
await page.waitForTimeout(500);
r = await row('roll');
check('release → re-centers', r.includes('+0.00') && r.includes('+0.0°'), r);

await page.keyboard.down('KeyW');
await page.waitForTimeout(600);
await page.keyboard.up('KeyW');
const pct = async () => Number((await row('throttle')).match(/(\d+)%/)[1]);
await page.waitForTimeout(100); // let the panel show the released key
const before = await pct();
await page.waitForTimeout(300);
check('throttle rose and holds after release', before > 50 && (await pct()) === before, `${before}%`);
await page.keyboard.press('KeyR');
await page.waitForTimeout(100);
check('reset → throttle 50%', (await row('throttle')).includes(' 50%'), await row('throttle'));

await browser.close();
server.httpServer.close();
console.log(failures ? `${failures} failed` : 'all e2e checks passed');
process.exit(failures ? 1 : 0);
