// Khronos validation; pin in package-lock.json. Tool directory is passed explicitly.
const fs = require('node:fs');
const path = require('node:path');
const validator = require(path.resolve(process.argv[2], 'node_modules/gltf-validator'));
(async () => {
  const reports = [];
  for (const file of process.argv.slice(4)) {
    const report = await validator.validateBytes(new Uint8Array(fs.readFileSync(file)), {
      uri: path.basename(file), maxIssues: 100,
    });
    reports.push({file: path.basename(path.dirname(file)) + '/' + path.basename(file), report});
  }
  fs.writeFileSync(process.argv[3], JSON.stringify(reports, null, 2) + '\n');
  // Originals are retained as evidence of a discovered upstream defect.
  // Only this known source error is tolerated for the diagnostic A/B; derivatives must pass.
  if (reports.some(x => x.report.issues.messages.some(issue => issue.severity === 0 &&
      !(x.file.startsWith('source/') && issue.code === 'SCENE_NON_ROOT_NODE')))) process.exitCode = 1;
})().catch(e => { console.error(e); process.exitCode = 1; });
