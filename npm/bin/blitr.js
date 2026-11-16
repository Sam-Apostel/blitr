#!/usr/bin/env node
'use strict';
const { spawn } = require('child_process');
const { prepare } = require('../lib/install');

prepare().then(({ command, env }) => {
  const child = spawn(command, process.argv.slice(2), { stdio: 'inherit', env });
  for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) process.on(signal, () => child.kill(signal));
  child.on('exit', (code, signal) => {
    if (signal) process.kill(process.pid, signal);
    else process.exit(code ?? 1);
  });
}, (error) => {
  process.stderr.write(`blitr: ${error.message}\n`);
  process.exit(1);
});
