#!/usr/bin/env node
/**
 * Headed codegen handoff for AHK Record → Copilot flow (Playwright 1.63.0).
 * - Ensures recordings/ + recordings/archive/
 * - Archives previous latest.spec.js before overwrite
 * - Runs: npx --no-install playwright codegen --target=playwright-test -o recordings/latest.spec.js [url]
 * Exit code matches codegen. AHK should wait for this process to exit, then read latest.spec.js.
 */
const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const recordings = path.join(root, 'recordings');
const archive = path.join(recordings, 'archive');
const latest = path.join(recordings, 'latest.spec.js');

fs.mkdirSync(archive, { recursive: true });

if (fs.existsSync(latest)) {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-').replace('T', '-').slice(0, 19);
  fs.copyFileSync(latest, path.join(archive, `${stamp}.spec.js`));
}

const url = process.argv[2] || '';
const args = [
  '--no-install',
  'playwright',
  'codegen',
  '--target=playwright-test',
  '-o',
  path.join('recordings', 'latest.spec.js'),
];
if (url) args.push(url);

const result = spawnSync('npx', args, {
  cwd: root,
  stdio: 'inherit',
  shell: process.platform === 'win32',
  env: process.env,
});

process.exit(result.status == null ? 1 : result.status);
