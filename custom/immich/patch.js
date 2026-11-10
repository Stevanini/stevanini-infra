// Aplica a marca Stevanini no index.html do Immich a cada start (idempotente).
const fs = require('fs'), c = require('crypto');
const W = '/build/www/', S = '/stevanini/';
for (const f of ["stevanini.css", "stevanini-favicon.svg", "GoogleSans.ttf"]) fs.copyFileSync(S + f, W + f);
for (const f of fs.readdirSync(S + 'png')) fs.copyFileSync(S + 'png/' + f, W + f);
// manifest: nome do app
try { const mf = JSON.parse(fs.readFileSync(W + 'manifest.json', 'utf8')); mf.name = 'Stevanini Photos'; mf.short_name = 'Photos'; mf.background_color = '#fbf6ec'; fs.writeFileSync(W + 'manifest.json', JSON.stringify(mf, null, 2)); } catch (e) {}
let h = fs.readFileSync(W + 'index.html', 'utf8');
const v = c.createHash('md5').update(fs.readFileSync(S + 'stevanini.css')).digest('hex').slice(0, 8);
if (h.includes('stevanini-title')) {
  const js = fs.readFileSync(S + 'title.js', 'utf8').trim();
  h = h.replace(/(stevanini(?:\.css|-favicon\.svg))\?v=\w+/g, `$1?v=${v}`).replace(/<script id="stevanini-title">[\s\S]*?<\/script>/, () => `<script id="stevanini-title">${js}</script>`);
  fs.writeFileSync(W + 'index.html', h);
} else {
  h = h.replace(/<link rel="(shortcut )?icon"[^>]*>\s*/g, '').replace('</head>',
    `<link rel="stylesheet" href="/stevanini.css?v=${v}"><link rel="icon" type="image/svg+xml" href="/stevanini-favicon.svg?v=${v}"><script id="stevanini-title">${fs.readFileSync(S + 'title.js', 'utf8').trim()}</script></head>`);
  fs.writeFileSync(W + 'index.html', h);
}
