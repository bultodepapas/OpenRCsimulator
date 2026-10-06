import { mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { createServer } from 'vite';

function requiredPath(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return path.resolve(value);
}

const playwrightPath = requiredPath('PLAYWRIGHT_CORE_PATH');
const chromiumPath = requiredPath('CHROMIUM_PATH');
const outputDir = requiredPath('OUT_DIR');
await stat(playwrightPath);
await stat(chromiumPath);
await mkdir(outputDir, { recursive: true });

const require = createRequire(import.meta.url);
const { chromium } = require(playwrightPath);
const packageBuildPath = require.resolve('@dgreenheck/ez-tree');
const packageRoot = path.resolve(path.dirname(packageBuildPath), '..');
const leafAssetNames = ['ash_color.png', 'aspen_color.png', 'oak_color.png', 'pine_color.png'];
const leafAssets = await Promise.all(leafAssetNames.map(async (name) => {
  const bytes = await readFile(path.join(packageRoot, 'src/lib/assets/leaves', name));
  return {
    file: name,
    sha256: createHash('sha256').update(bytes).digest('hex'),
  };
}));
const server = await createServer({
  configFile: false,
  root: path.dirname(fileURLToPath(import.meta.url)),
  server: { host: '127.0.0.1', port: 0, strictPort: true },
});

let browser;
try {
  await server.listen();
  const serverUrl = server.resolvedUrls?.local?.[0];
  if (!serverUrl) throw new Error('Vite did not provide a local URL');

  browser = await chromium.launch({
    headless: true,
    executablePath: chromiumPath,
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  const page = await browser.newPage();
  const pageErrors = [];
  page.on('pageerror', (error) => pageErrors.push(error.message));
  await page.goto(serverUrl, { waitUntil: 'networkidle' });
  await page.waitForFunction('window.ezTreeMetricsReady === true');

  const presets = ['Oak Large', 'Ash Large', 'Pine Large'];
  const trees = await page.evaluate((names) => window.measureTreePresets(names), presets);
  if (pageErrors.length) throw new Error(`Browser errors: ${pageErrors.join('; ')}`);

  const report = {
    format: 'ez-tree-offline-trial-metrics v1',
    package: '@dgreenheck/ez-tree@1.1.0',
    source_tag: 'v1.1.0',
    source_commit: '89083a033a354856acae05f8856bf37c6ebcfa9b',
    package_tarball_sha256: '4147b49d22b01f09c9d7f3c3c34f788ad37841103a758da25e399af3cbce2f98',
    npm_integrity: 'sha512-6pvS6hD6B6h00dm0SnkgYeT4ABU5Y1Z9M44p1tXiV5C0eKrQy2sKECXshoaUv0qAOqYVL68w/PwadUxDFDiHUg==',
    code_license: 'MIT',
    exact_v1_1_leaf_image_license: 'unresolved per-file; outputs not retained',
    leaf_texture_file_hashes: leafAssets,
    runner_dependencies: { three: '0.167.1', vite: '5.4.21' },
    browser_version: browser.version(),
    metrics_method: 'sum of branch and leaf indexed geometry triangles in browser; no binary or image export',
    trees,
  };
  await writeFile(path.join(outputDir, 'metrics.json'), `${JSON.stringify(report, null, 2)}\n`);
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
} finally {
  await browser?.close();
  await server.close();
}
