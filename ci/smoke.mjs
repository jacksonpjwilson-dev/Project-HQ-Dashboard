// Minimal static-site smoke test: no dependencies.
// Checks: index.html exists; local src/href targets in every .html exist;
// .json/.webmanifest parse; every .js file passes `node --check` syntax check.
import fs from 'node:fs'; import path from 'node:path'; import { execFileSync } from 'node:child_process';
const root = process.cwd(); let fail = 0, n = 0;
const skip = new Set(['node_modules', '.git', '.github']);
const walk = d => fs.readdirSync(d, { withFileTypes: true }).flatMap(e => skip.has(e.name) ? [] : e.isDirectory() ? walk(path.join(d, e.name)) : [path.join(d, e.name)]);
const files = walk(root); const bad = m => { fail++; console.error('FAIL ' + m); };
if (!fs.existsSync(path.join(root, 'index.html'))) bad('index.html missing');
for (const f of files) {
  const rel = path.relative(root, f);
  if (/\.(json|webmanifest)$/.test(f)) { n++; try { JSON.parse(fs.readFileSync(f, 'utf8')); } catch (e) { bad(`${rel} invalid JSON`); } }
  if (/\.(m?js)$/.test(f) && !/\.min\.js$/.test(f)) { n++; try { execFileSync(process.execPath, ['--check', f], { stdio: 'pipe' }); } catch (e) { bad(`${rel} syntax error: ${String(e.stderr).split('\n')[0]}`); } }
  if (f.endsWith('.html')) {
    const html = fs.readFileSync(f, 'utf8');
    for (const m of html.matchAll(/(?:src|href)\s*=\s*["']([^"'#?]+)/gi)) {
      const u = m[1].trim();
      if (/^(https?:|mailto:|tel:|data:|javascript:|\/\/|\$\{|\{)/i.test(u) || u.includes('${')) continue;
      n++; const t = u.startsWith('/') ? path.join(root, u.replace(/^\/[^/]+\//, '/').slice(1)) : path.resolve(path.dirname(f), decodeURI(u));
      const alt = u.startsWith('/') ? path.join(root, u.slice(1)) : t;
      if (!fs.existsSync(t) && !fs.existsSync(alt) && !fs.existsSync(t + '.html')) bad(`${rel} -> missing ${u}`);
    }
  }
}
console.log(`smoke: ${n} checks, ${fail} failed`); process.exit(fail ? 1 : 0);
