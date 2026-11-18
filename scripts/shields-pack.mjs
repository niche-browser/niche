#!/usr/bin/env node
// Builds the Shields packs Niche downloads (docs/shields.md): the filter lists of
// resources/shields/lists.json with uBlock Origin's scriptlets and stand-in resources, as
//   shields.pack                 the lists every copy of Niche uses
//   shields-<id>.pack            one per regional list, fetched by the Macs that speak its language
//   shields-x-<id>.pack          one per optional list (Settings ▸ Privacy "More lists"), fetched
//                                when its switch goes on; shields-lists.json names them
//
// The default set is uBlock Origin Lite's: its own catalogue (platform/mv3/rulesets.json in the
// uBlock checkout) is read on every run. A list its default rulesets gained is added, one they
// lost is dropped, and its optional rulesets become the optional packs, so what uBO Lite
// changes is changed here by the next run with nobody touching lists.json. Lists there without
// "ubol" are Niche's own choice on top.
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
  // The addresses come from resources/shields/lists.json, reviewed with the repository; only https.
  if (!/^https:\/\//.test(list.url)) throw new Error(`${list.id}: not an https address (${list.url})`);
  for (let attempt = 1; ; attempt++) {
    try {
      const answer = await fetch(list.url, { headers: { 'user-agent': 'niche-shields-pack' }, redirect: 'follow', signal: AbortSignal.timeout(120000) });
      if (!answer.ok) throw new Error(`HTTP ${answer.status}`);
      const text = await answer.text();
      if (text.length < minimumBytes || /^\s*<(!doctype|html)/i.test(text)) throw new Error('not a filter list');
      return hostsAsRules(text);
    } catch (error) {
      if (attempt >= 3) throw new Error(`${list.id}: ${error.message} (${list.url})`);
      await new Promise(done => setTimeout(done, 2000 * attempt));
    }
  }
}

// A hosts file (`127.0.0.1 ads.example`: Peter Lowe's list, URLhaus) as the rules it stands for
// (`||ads.example^`), which is how uBlock Origin reads one. Niche's engine does the same from
// 0.1.10; the copies before it read such lines as rules that match nothing, so they get rules.
function hostsAsRules(text) {
  const hosts = /^(?:127\.0\.0\.1|0\.0\.0\.0|::1?)\s+([a-z0-9._-]+)\s*(?:#.*)?$/i;
  if (!text.split('\n', 400).some(line => hosts.test(line.trim()))) return text;
  return text.split('\n').map(line => {
    const found = hosts.exec(line.trim());
    if (!found) return line;
    const host = found[1].toLowerCase();
    return host.includes('.') && host !== 'localhost.localdomain' && !/^[0-9.]+$/.test(host) ? `||${host}^` : '';
  }).join('\n');
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

// uBlock Origin Lite's catalogue: which rulesets it starts with, and which it offers.
const ubol = manifest.ubol;
const rulesets = JSON.parse(readFileSync(join(ublock, ubol.rulesets), 'utf8'));
if (!Array.isArray(rulesets) || rulesets.filter(r => r.enabled).length < 3) throw new Error('uBO Lite\'s rulesets.json looks wrong');
const trusted = url => url.startsWith(ubol.trustedPrefix);
const slug = url => new URL(url).pathname.split('/').pop().replace(/\.(min\.)?txt$/, '').replace(/[^a-z0-9]+/gi, '-').toLowerCase() || 'list';
const fromRuleset = (ruleset, url, group) => ({ id: `${ruleset.id}-${slug(url)}`, group, title: ruleset.name, licence: 'see its homepage',
                                                homepage: ruleset.homeURL || '', trusted: trusted(url), url });

// The default set: Niche's own lists, and of the ones marked ubol those uBO Lite still starts
// with, plus whatever its default rulesets name that lists.json doesn't know yet.
const defaults = rulesets.filter(r => r.enabled);
const defaultURLs = new Set(defaults.flatMap(r => r.urls));
const mainLists = manifest.lists.filter(list => {
  if (!list.ubol || defaultURLs.has(list.url)) return true;
  console.log(`dropped ${list.id}: no longer in uBO Lite's default rulesets`);
  return false;
});
const known = new Set(manifest.lists.map(list => list.url));
for (const ruleset of defaults) {
  for (const url of ruleset.urls) {
    if (known.has(url)) continue;
    console.log(`added ${url}: new in uBO Lite's default ruleset ${ruleset.id}`);
    mainLists.push(fromRuleset(ruleset, url, ruleset.group === 'malware' ? 'malware' : 'ads'));
  }
}

const main = await Promise.all(mainLists.map(entry));
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

  // The optional lists: Niche's own (lists.json "extras"), then uBO Lite's optional rulesets
  // that aren't regional (those have a language) and aren't already in the default set.
  const inMain = new Set(mainLists.map(list => list.url));
  const offered = manifest.extras.map(e => ({ ...e }));
  for (const ruleset of rulesets) {
    if (ruleset.enabled || ruleset.lang || ubol.skip.includes(ruleset.id) || !ubol.groups[ruleset.group]) continue;
    if (ruleset.group === 'regions' || offered.some(e => e.id === ruleset.id)) continue;
    const group = ubol.groups[ruleset.group];
    const lists = ruleset.urls.filter(url => !inMain.has(url)).map(url => fromRuleset(ruleset, url, group));
    if (lists.length) offered.push({ id: ruleset.id, group, title: ruleset.name, homepage: ruleset.homeURL || '', lists });
  }
  const catalog = [];
  for (const item of offered) {
    try {
      const bytes = write(`shields-x-${item.id}.pack`, await Promise.all(item.lists.map(entry)), { scriptlets: [], redirects: [] });
      catalog.push({ id: item.id, title: item.title, group: item.group, homepage: item.homepage, detail: manifest.details?.[item.id] || '', bytes });
    } catch (error) {
      console.error(`skipped ${error.message}`);
    }
  }
  writeFileSync(join(out, 'shields-lists.json'), JSON.stringify({ built, lists: catalog }));
  console.log(`${catalog.length} optional packs: ${catalog.map(c => c.id).join(', ')}`);
}
