#!/usr/bin/env node
// Builds the Shields packs Niche downloads (docs/shields.md): the filter lists of
// resources/shields/lists.json with uBlock Origin's scriptlets and stand-in resources, as
//   shields.pack                 the lists every copy of Niche uses
//   shields-<id>.pack            one per regional list, fetched by the Macs that speak its language
// each with a detached Ed25519 signature (<name>.sig, base64) that Niche checks before it trusts
// a download. A pack is raw-deflated JSON: {format, built, lists: [{id, group, title, licence,
// homepage, trusted, languages?, text}], resources: {scriptlets: [...], redirects: [...]}}.
//
//   node scripts/shields-pack.mjs --out <dir> [--ublock <checkout>] [--key <pem>] [--only-main]
//
// Without --ublock it clones the repository lists.json names. The signing key is --key, or the
// PEM in $SHIELDS_SIGNING_KEY; without one the packs are written unsigned (for a local test
// with NICHE_SHIELDS_UNSIGNED=1). A list that fails to download, or comes back too short to be
// one, fails the run: yesterday's packs stay published.
import { execFileSync } from 'node:child_process';
import { createPrivateKey, sign } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, extname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { deflateRawSync } from 'node:zlib';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const option = name => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
const out = option('--out');
if (!out) { console.error('usage: shields-pack.mjs --out <dir> [--ublock <checkout>] [--key <pem>] [--only-main]'); process.exit(2); }
mkdirSync(out, { recursive: true });
const manifest = JSON.parse(readFileSync(join(root, 'resources/shields/lists.json'), 'utf8'));

// A list is text with rules in it; an error page or an empty answer is not.
const minimumBytes = 200;
async function download(list) {
  for (let attempt = 1; ; attempt++) {
    try {
      const answer = await fetch(list.url, { headers: { 'user-agent': 'niche-shields-pack' }, redirect: 'follow', signal: AbortSignal.timeout(120000) });
      if (!answer.ok) throw new Error(`HTTP ${answer.status}`);
      const text = await answer.text();
      if (text.length < minimumBytes || /^\s*<(!doctype|html)/i.test(text)) throw new Error('not a filter list');
      return text;
    } catch (error) {
      if (attempt >= 3) throw new Error(`${list.id}: ${error.message} (${list.url})`);
      await new Promise(done => setTimeout(done, 2000 * attempt));
    }
  }
}

// uBlock Origin's scriptlets (src/js/resources) and the resources it answers blocked requests
// with (src/web_accessible_resources), in adblock-rust's format.
async function resources(ublock) {
  const { builtinScriptlets } = await import(pathToFileURL(join(ublock, 'src/js/resources/scriptlets.js')).href);
  const scriptlets = builtinScriptlets.map(s => ({
    name: s.name,
    aliases: s.aliases || [],
    kind: { mime: s.name.endsWith('.fn') ? 'fn/javascript' : 'application/javascript' },
    content: Buffer.from(s.fn.toString()).toString('base64'),
    ...(s.dependencies?.length ? { dependencies: s.dependencies } : {}),
    ...(s.requiresTrust ? { permission: 1 } : {}),
  }));
  const mimes = { '.js': 'application/javascript', '.gif': 'image/gif', '.png': 'image/png', '.html': 'text/html', '.txt': 'text/plain',
                  '.json': 'application/json', '.mp3': 'audio/mp3', '.mp4': 'video/mp4', '.css': 'text/css', '.xml': 'text/xml' };
  const { default: redirectable } = await import(pathToFileURL(join(ublock, 'src/js/redirect-resources.js')).href);
  const directory = join(ublock, 'src/web_accessible_resources');
  const files = new Set(readdirSync(directory));
  const redirects = [];
  for (const [name, details] of redirectable) {
    const mime = mimes[extname(name)];
    if (!mime || !files.has(name)) continue;
    const alias = details.alias === undefined ? [] : [details.alias].flat();
    redirects.push({ name, aliases: alias, kind: { mime }, content: readFileSync(join(directory, name)).toString('base64') });
  }
  if (scriptlets.length < 50 || redirects.length < 20) throw new Error(`uBlock resources look wrong: ${scriptlets.length} scriptlets, ${redirects.length} redirects`);
  return { scriptlets, redirects };
}

let ublock = option('--ublock');
if (!ublock) {
  ublock = mkdtempSync(join(tmpdir(), 'ublock-'));
  execFileSync('git', ['clone', '--depth', '1', '--branch', manifest.ublock.ref, manifest.ublock.repository, ublock], { stdio: 'ignore' });
}
// uBlock's sources are ES modules without a package.json of their own saying so.
if (!existsSync(join(ublock, 'src/package.json'))) {
  try { writeFileSync(join(ublock, 'src/package.json'), '{"type":"module"}'); } catch { /* a read-only checkout that already resolves */ }
}

const pem = option('--key') ? readFileSync(option('--key'), 'utf8') : process.env.SHIELDS_SIGNING_KEY;
const key = pem ? createPrivateKey(pem) : null;
const built = new Date().toISOString();

function write(name, lists, extra) {
  const bytes = deflateRawSync(Buffer.from(JSON.stringify({ format: 1, built, lists, resources: extra })), { level: 9 });
  writeFileSync(join(out, name), bytes);
  if (key) writeFileSync(join(out, name + '.sig'), sign(null, bytes, key).toString('base64'));
  return bytes.length;
}

const entry = async list => ({ id: list.id, group: list.group, title: list.title, licence: list.licence, homepage: list.homepage,
                               trusted: list.trusted, ...(list.languages ? { languages: list.languages } : {}), text: await download(list) });

const main = await Promise.all(manifest.lists.map(entry));
const extra = await resources(ublock);
const size = write('shields.pack', main, extra);
console.log(`shields.pack: ${main.length} lists, ${extra.scriptlets.length} scriptlets, ${extra.redirects.length} stand-ins, ${(size / 1e6).toFixed(1)} MB${key ? ', signed' : ', UNSIGNED'}`);

if (!args.includes('--only-main')) {
  const index = [];
  for (const list of manifest.regional) {
    try {
      const bytes = write(`shields-${list.id}.pack`, [await entry(list)], { scriptlets: [], redirects: [] });
      index.push({ id: list.id, title: list.title, languages: list.languages, bytes });
    } catch (error) {
      // A regional list that is down today doesn't hold the rest back; its last pack stays.
      console.error(`skipped ${error.message}`);
    }
  }
  writeFileSync(join(out, 'shields-regional.json'), JSON.stringify({ built, lists: index }));
  console.log(`${index.length} of ${manifest.regional.length} regional packs`);
}
