#!/usr/bin/env node
// Maakt users.json (versleutelde toegang per persoon) en wachtwoorden.txt.
// Zet ook de data-repo klaar (draws.json + members/).
//
//   node tools/maak-accounts.mjs
//
// Bestaat wachtwoorden.txt al, dan blijven die wachtwoorden hetzelfde
// (handig als je alleen een nieuwe token wilt instellen).
// Namen toevoegen/weghalen: pas NAMES hieronder aan en draai opnieuw.

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import readline from 'node:readline';
import { fileURLToPath } from 'node:url';

const NAMES = ['Benjamin', 'Nikola', 'Leonie', 'Dino', 'Harry', 'Francisco', 'Chaimae', 'Estelle', 'Digna', 'Inez'];
const ITERATIONS = 300000;

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const PW_FILE = path.join(ROOT, 'wachtwoorden.txt');
const USERS_FILE = path.join(ROOT, 'users.json');
const offline = process.argv.includes('--offline');   // alleen voor testen

const cfg = fs.readFileSync(path.join(ROOT, 'config.js'), 'utf8');
const repo = (cfg.match(/dataRepo:\s*'([^']+)'/) || [])[1];
const branch = (cfg.match(/branch:\s*'([^']+)'/) || [])[1] || 'main';
if (!repo) { console.error('Zet eerst dataRepo in config.js (bv. \'bjeltinks-lab/kerst-data\').'); process.exit(1); }

function ask(q) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((res) => rl.question(q, (a) => { rl.close(); res(a.trim()); }));
}

const token = process.env.KERST_TOKEN || await ask('Plak je GitHub-token (github_pat_...): ');
if (!token) { console.error('Geen token ingevuld.'); process.exit(1); }

// ---------- data-repo controleren en klaarzetten ----------
const gh = (method, p, body) => fetch(`https://api.github.com/repos/${repo}${p}`, {
  method,
  headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'kerst-lootjes-setup' },
  body: body ? JSON.stringify(body) : undefined
});

if (!offline) {
  const r = await gh('GET', '');
  if (!r.ok) { console.error(`Kan ${repo} niet openen met deze token (${r.status}). Klopt de repo-naam en heeft de token toegang?`); process.exit(1); }
  const info = await r.json();
  if (!info.private) console.warn(`⚠️  ${repo} is PUBLIEK. Maak hem privé (Settings → General → Danger Zone), anders kan iedereen de trekkingen zien.`);
  const exists = await gh('GET', `/contents/draws.json?ref=${branch}`);
  if (exists.status === 404) {
    const put = await gh('PUT', '/contents/draws.json', { message: 'start', branch, content: Buffer.from(JSON.stringify({ draws: {} })).toString('base64') });
    if (!put.ok) { console.error(`Kan niet schrijven in ${repo} (${put.status}). Geef de token "Contents: Read and write".`, await put.text()); process.exit(1); }
    console.log('✓ draws.json aangemaakt in', repo);
  } else if (exists.ok) {
    console.log('✓ draws.json bestaat al (trekkingen blijven staan)');
  } else { console.error('Onverwachte fout', exists.status, await exists.text()); process.exit(1); }
}

// ---------- wachtwoorden ----------
const WORDS = ['ster', 'sneeuw', 'rendier', 'slee', 'kaars', 'bel', 'piek', 'hulst', 'pakje', 'engel', 'zuurstok', 'dennen', 'vlok', 'muts', 'sjaal', 'haard', 'kerstbal', 'lichtje', 'strik', 'kransje', 'oliebol', 'ijspegel', 'wanten', 'cadeau'];
const pick = () => WORDS[crypto.randomInt(WORDS.length)];
const existing = {};
if (fs.existsSync(PW_FILE)) {
  for (const line of fs.readFileSync(PW_FILE, 'utf8').split('\n')) {
    const m = line.match(/^\s*(\S+)\s+(\S+)\s*$/);
    if (m && NAMES.includes(m[1])) existing[m[1]] = m[2];
  }
}
const passwords = Object.fromEntries(NAMES.map((n) => [n, existing[n] || `${pick()}-${pick()}-${100 + crypto.randomInt(900)}`]));

// ---------- token per persoon versleutelen (PBKDF2 + AES-GCM, zelfde als de browser) ----------
const users = {};
for (const n of NAMES) {
  const salt = crypto.randomBytes(16), iv = crypto.randomBytes(12);
  const key = crypto.pbkdf2Sync(passwords[n], salt, ITERATIONS, 32, 'sha256');
  const c = crypto.createCipheriv('aes-256-gcm', key, iv);
  const ct = Buffer.concat([c.update(token, 'utf8'), c.final(), c.getAuthTag()]);
  users[n] = { salt: salt.toString('base64'), iv: iv.toString('base64'), ct: ct.toString('base64') };
}
fs.writeFileSync(USERS_FILE, JSON.stringify({ iterations: ITERATIONS, users }, null, 1) + '\n');
fs.writeFileSync(PW_FILE, '# Wachtwoorden Kerst Lootjes — NIET in git (staat in .gitignore)\n' +
  NAMES.map((n) => `${n.padEnd(10)} ${passwords[n]}`).join('\n') + '\n');

console.log('✓ users.json geschreven');
console.log('✓ wachtwoorden.txt geschreven:\n');
NAMES.forEach((n) => console.log(`   ${n.padEnd(10)} ${passwords[n]}`));
console.log('\nNu: git add users.json && git commit -m "accounts" && git push');
