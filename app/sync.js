// Keeps the app's copy of the page and helper in step with the originals one folder up.
const fs = require('fs'), path = require('path');
for (const f of ['lyric-glow.html', 'nowplaying.ps1']) {
  fs.copyFileSync(path.join(__dirname, '..', f), path.join(__dirname, f));
}
console.log('synced page + helper');
