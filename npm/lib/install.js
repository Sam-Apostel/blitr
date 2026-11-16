'use strict';
// Downloads the blitr release that matches this package's version, and on Linux the Swift toolchain it
// was built with, into a per-user cache. Used by the `blitr` command on first run and by postinstall.
//
// Environment:
//   BLITR_HOME          Where releases and toolchains are kept (default ~/.cache/blitr).
//   BLITR_DOWNLOAD_URL  Base URL of the release assets (default the GitHub release of this version).
//   BLITR_SWIFT_DIR     A Swift toolchain to use on Linux instead of downloading one (its usr/bin/swiftc).

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');
const http = require('http');
const https = require('https');
const { pipeline } = require('stream/promises');

const REPO = 'Sam-Apostel/blitr';
const version = require('../package.json').version;
const tag = `v${version}`;

function home() {
  return process.env.BLITR_HOME || path.join(os.homedir(), '.cache', 'blitr');
}

function target() {
  const arch = { x64: 'x86_64', arm64: process.platform === 'darwin' ? 'arm64' : 'aarch64' }[process.arch];
  const platform = { darwin: 'macos', linux: 'linux' }[process.platform];
  if (!arch || !platform) {
    throw new Error(`blitr runs on macOS and Linux (x64 or arm64), not ${process.platform}-${process.arch}`);
  }
  return { platform, arch };
}

function log(message) {
  process.stderr.write(`blitr: ${message}\n`);
}

/// Node's http(s) modules rather than fetch: undici's fetch can crash outright (an internal assertion) when a
/// server closes the connection while the body stream is paused.
function get(url, redirects = 0) {
  return new Promise((resolve, reject) => {
    const client = url.startsWith('https:') ? https : http;
    client.get(url, { headers: { 'user-agent': 'blitr-npm' } }, (response) => {
      const { statusCode, headers } = response;
      if (statusCode >= 300 && statusCode < 400 && headers.location) {
        response.resume();
        if (redirects >= 10) return reject(new Error(`too many redirects for ${url}`));
        return resolve(get(new URL(headers.location, url).toString(), redirects + 1));
      }
      if (statusCode !== 200) {
        response.resume();
        return reject(new Error(`download of ${url} failed (HTTP ${statusCode})`));
      }
      resolve(response);
    }).on('error', (error) => reject(new Error(`download of ${url} failed: ${error.message}`)));
  });
}

async function download(url, file) {
  await pipeline(await get(url), fs.createWriteStream(file));
}

async function sha256(file) {
  const hash = crypto.createHash('sha256');
  await pipeline(fs.createReadStream(file), hash);
  return hash.digest('hex');
}

function untar(archive, directory, strip) {
  fs.mkdirSync(directory, { recursive: true });
  const args = ['-xzf', archive, '-C', directory];
  if (strip) args.push(`--strip-components=${strip}`);
  const result = spawnSync('tar', args, { stdio: ['ignore', 'ignore', 'pipe'] });
  if (result.status !== 0) throw new Error(`unpacking ${path.basename(archive)} failed: ${result.stderr}`);
}

/// Moves a finished directory into place; another process may have won the race, which is fine.
function publish(staging, destination) {
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  try {
    fs.renameSync(staging, destination);
  } catch (error) {
    fs.rmSync(staging, { recursive: true, force: true });
    if (!fs.existsSync(destination)) throw error;
  }
}

function readVersionFile(root) {
  const info = {};
  const text = fs.readFileSync(path.join(root, 'share', 'blitr', 'VERSION'), 'utf8');
  for (const line of text.split('\n')) {
    const match = /^([a-z_]+):\s*(.*)$/.exec(line);
    if (match) info[match[1]] = match[2];
  }
  return info;
}

/// The release tree for this version: <home>/releases/<version>/{bin,lib,share}.
async function ensureRelease() {
  const { platform, arch } = target();
  const destination = path.join(home(), 'releases', version);
  if (fs.existsSync(path.join(destination, 'bin', 'blitr'))) return destination;

  const asset = `blitr-${tag}-${platform}-${arch}.tar.gz`;
  const base = process.env.BLITR_DOWNLOAD_URL || `https://github.com/${REPO}/releases/download/${tag}`;
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'blitr-'));
  try {
    log(`downloading ${asset}`);
    const archive = path.join(work, asset);
    await download(`${base}/${asset}`, archive);
    await download(`${base}/${asset}.sha256`, `${archive}.sha256`);
    const expected = fs.readFileSync(`${archive}.sha256`, 'utf8').trim().split(/\s+/)[0];
    const actual = await sha256(archive);
    if (expected !== actual) throw new Error(`checksum mismatch for ${asset} (expected ${expected}, got ${actual})`);
    const staging = path.join(home(), 'releases', `.${version}-${process.pid}`);
    fs.rmSync(staging, { recursive: true, force: true });
    untar(archive, staging, 1);
    publish(staging, destination);
    return destination;
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
}

/// swift.org's name for this Linux distribution, from /etc/os-release.
function swiftPlatform() {
  let text = '';
  try { text = fs.readFileSync('/etc/os-release', 'utf8'); } catch { /* handled below */ }
  const field = (name) => (new RegExp(`^${name}="?([^"\\n]*)"?$`, 'm').exec(text) || [])[1] || '';
  const id = field('ID');
  const versionId = field('VERSION_ID');
  const like = field('ID_LIKE');
  if (id === 'ubuntu' && ['20.04', '22.04', '24.04'].includes(versionId)) return { dir: `ubuntu${versionId.replace('.', '')}`, name: `ubuntu${versionId}` };
  if (id === 'debian' && versionId === '12') return { dir: 'debian12', name: 'debian12' };
  if (id === 'amzn' && versionId === '2') return { dir: 'amazonlinux2', name: 'amazonlinux2' };
  if (/rhel|centos|fedora/.test(`${id} ${like}`) && versionId.startsWith('9')) return { dir: 'ubi9', name: 'ubi9' };
  if (id === 'fedora' && versionId === '39') return { dir: 'fedora39', name: 'fedora39' };
  return null;
}

function compilerVersion(swiftc) {
  const result = spawnSync(swiftc, ['--version'], { encoding: 'utf8' });
  if (result.status !== 0) return null;
  const match = /Swift version (\S+)/.exec(`${result.stdout}${result.stderr}`);
  return match ? match[1] : null;
}

/// Linux only: the bin directory of a Swift toolchain of exactly the version the release was built with.
async function ensureToolchain(swiftVersion) {
  const candidates = [];
  if (process.env.BLITR_SWIFT_DIR) candidates.push(path.join(process.env.BLITR_SWIFT_DIR, 'usr', 'bin'));
  const onPath = spawnSync('sh', ['-c', 'command -v swiftc'], { encoding: 'utf8' }).stdout.trim();
  if (onPath) candidates.push(path.dirname(onPath));
  candidates.push('/opt/swift/usr/bin', '/usr/share/swift/usr/bin');
  const destination = path.join(home(), 'toolchains', `swift-${swiftVersion}`);
  candidates.push(path.join(destination, 'usr', 'bin'));
  for (const bin of candidates) {
    const swiftc = path.join(bin, 'swiftc');
    if (fs.existsSync(swiftc) && compilerVersion(swiftc) === swiftVersion) return bin;
  }

  const platform = swiftPlatform();
  if (!platform) {
    throw new Error(`blitr needs the Swift ${swiftVersion} toolchain, and there is no download of it for this Linux. `
      + 'Install it from swift.org and set BLITR_SWIFT_DIR to its directory.');
  }
  const suffix = process.arch === 'arm64' ? '-aarch64' : '';
  const name = `swift-${swiftVersion}-RELEASE`;
  const url = `https://download.swift.org/swift-${swiftVersion}-release/${platform.dir}${suffix}/${name}/${name}-${platform.name}${suffix}.tar.gz`;
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'blitr-swift-'));
  try {
    log(`downloading the Swift ${swiftVersion} toolchain (about 1 GB, once)`);
    const archive = path.join(work, 'swift.tar.gz');
    await download(url, archive);
    const staging = path.join(home(), 'toolchains', `.swift-${swiftVersion}-${process.pid}`);
    fs.rmSync(staging, { recursive: true, force: true });
    untar(archive, staging, 1);
    publish(staging, destination);
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
  return path.join(destination, 'usr', 'bin');
}

/// The command to run and the environment to run it in.
async function prepare() {
  const root = await ensureRelease();
  const env = { ...process.env };
  if (process.platform === 'linux') {
    const info = readVersionFile(root);
    const bin = await ensureToolchain(info.swift_version);
    env.PATH = `${bin}${path.delimiter}${env.PATH || ''}`;
    env.SWIFTC = path.join(bin, 'swiftc');
    const runtime = path.join(bin, '..', 'lib', 'swift', 'linux');
    env.LD_LIBRARY_PATH = env.LD_LIBRARY_PATH ? `${runtime}${path.delimiter}${env.LD_LIBRARY_PATH}` : runtime;
  } else if (spawnSync('xcrun', ['--find', 'swiftc'], { stdio: 'ignore' }).status !== 0) {
    throw new Error('blitr compiles your SwiftUI code with Xcode\'s Swift compiler. Install Xcode, or run: xcode-select --install');
  }
  return { command: path.join(root, 'bin', 'blitr'), env };
}

module.exports = { prepare, version };
