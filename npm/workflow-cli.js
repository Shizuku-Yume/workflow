#!/usr/bin/env node

'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const packageBin = path.dirname(fs.realpathSync(__filename));
const cli = path.join(packageBin, '..', 'bin', 'workflow');
const result = spawnSync('bash', [cli, ...process.argv.slice(2)], {
  cwd: process.cwd(),
  env: process.env,
  stdio: 'inherit',
});

if (result.error) {
  if (result.error.code === 'ENOENT') {
    console.error('workflow: bash is required but was not found on PATH');
  } else {
    console.error(`workflow: ${result.error.message}`);
  }
  process.exit(1);
}

if (result.signal) {
  process.kill(process.pid, result.signal);
}

process.exit(result.status === null ? 1 : result.status);
