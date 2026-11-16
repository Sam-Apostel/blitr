'use strict';
// Fetches the release (and on Linux the Swift toolchain) at install time, so the first render is not the
// one that waits. Never fails the install: without it, the first `blitr` run downloads the same files.
if (process.env.BLITR_SKIP_DOWNLOAD) process.exit(0);
require('./install').prepare().catch((error) => {
  process.stderr.write(`blitr: ${error.message}\nblitr: the first run of blitr will try again.\n`);
});
