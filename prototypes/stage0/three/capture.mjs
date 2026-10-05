// Capture mode: build, serve, render t = 3.0 s at 1280x720 in headless Chromium, save PNG.
import { build, preview } from 'vite';
import { chromium } from 'playwright';

await build({ logLevel: 'warn' });
const server = await preview({ preview: { port: 4317, strictPort: true } });
const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
page.on('console', (m) => console.log('[page]', m.text()));
const shots = [
  ['capture', '../capture-three.png'],
  ['capture&inspect', '../capture-three-inspect.png'],
  ['capture&inspect&roll=1&pitch=1&yaw=1', '../capture-three-inspect-deflected.png'],
];
for (const [query, file] of shots) {
  await page.goto(`http://localhost:4317/?${query}`);
  await page.waitForFunction(() => window.__captured === true);
  await page.screenshot({ path: file });
  console.log('saved', file);
}
await browser.close();
server.httpServer.close();
