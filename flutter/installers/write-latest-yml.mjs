// Writes the update files the desktop app reads (lib/desktop/updater.dart) in electron-updater's
// format: latest.yml (Windows), latest-mac.yml, latest-linux.yml and latest-linux-arm64.yml, each
// naming the version, each file with its base64 SHA-512 and size, and the release date.
//
//   node installers/write-latest-yml.mjs <version> <dir with the installers>
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const [version, dir] = process.argv.slice(2);
if (!version || !dir) {
  console.error('usage: write-latest-yml.mjs <version> <dir>');
  process.exit(1);
}
const names = readdirSync(dir);
const entry = (name) => {
  const buf = readFileSync(join(dir, name));
  return { url: name, sha512: createHash('sha512').update(buf).digest('base64'), size: statSync(join(dir, name)).size };
};
const date = new Date().toISOString();
const write = (file, picked) => {
  if (!picked.length) return;
  const files = picked.map(entry);
  const lines = [`version: ${version}`, 'files:'];
  for (const f of files) lines.push(`  - url: ${f.url}`, `    sha512: ${f.sha512}`, `    size: ${f.size}`);
  lines.push(`path: ${files[0].url}`, `sha512: ${files[0].sha512}`, `releaseDate: '${date}'`, '');
  writeFileSync(join(dir, file), lines.join('\n'));
  console.log(`${file}: ${picked.join(', ')}`);
};
write('latest.yml', names.filter((n) => n === `uwuhere-${version}-setup.exe`));
write('latest-mac.yml', names.filter((n) => /-mac-(arm64|x64)\.(zip|dmg)$/.test(n)).sort((a, b) => (a.endsWith('.zip') ? -1 : 1) - (b.endsWith('.zip') ? -1 : 1)));
write('latest-linux.yml', names.filter((n) => n === `uwuhere-${version}-x86_64.AppImage`));
write('latest-linux-arm64.yml', names.filter((n) => n === `uwuhere-${version}-aarch64.AppImage`));
