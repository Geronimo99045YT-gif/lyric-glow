// Lyric Glow desktop app (Windows). Made by Chaz.
// Runs the page from a tiny local server (Spotify login needs an http://127.0.0.1 address),
// reads what Windows is playing via nowplaying.ps1, and auto-grants system-audio capture.
const { app, BrowserWindow, session, desktopCapturer, shell, Menu } = require('electron');
const http = require('http'), fs = require('fs'), path = require('path'), os = require('os');
const { spawn } = require('child_process');

let latest = '{"playing":false}', ps = null, server = null, win = null;

const psPath = () => app.isPackaged ? path.join(process.resourcesPath, 'nowplaying.ps1') : path.join(__dirname, 'nowplaying.ps1');

function startPS() {
  if (process.platform !== 'win32') return;
  ps = spawn('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', psPath()], { windowsHide: true });
  let buf = '';
  ps.stdout.on('data', d => {
    buf += d;
    let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const l = buf.slice(0, i).trim(); buf = buf.slice(i + 1);
      if (l.startsWith('{')) latest = l;
    }
  });
  ps.on('error', () => {});
}

function listen(port) {
  return new Promise((resolve, reject) => {
    const s = http.createServer((q, r) => {
      const u = q.url.split('?')[0];
      if (u === '/api/control' && q.method === 'POST') {
        // play/pause/skip via the Windows media session. POST + custom header + same-origin check, so other websites can't trigger it.
        const cmd = new URL(q.url, 'http://x').searchParams.get('cmd');
        const okOrigin = !q.headers.origin || /^http:\/\/127\.0\.0\.1:\d+$/.test(q.headers.origin);
        if (q.headers['x-lg'] === '1' && okOrigin && ['playpause', 'play', 'pause', 'next', 'prev'].includes(cmd)) {
          try { fs.writeFileSync(path.join(os.tmpdir(), 'lyricglow_cmd.txt'), cmd); r.writeHead(204); } catch (e) { r.writeHead(500); }
        } else r.writeHead(403);
        r.end();
      } else if (u === '/api/nowplaying') {
        r.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
        r.end(latest);
      } else if (u === '/' || u === '/lyric-glow.html') {
        r.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
        r.end(fs.readFileSync(path.join(__dirname, 'lyric-glow.html')));
      } else { r.writeHead(404); r.end(); }
    });
    s.once('error', reject);
    s.listen(port, '127.0.0.1', () => resolve(s));
  });
}

async function startServer() {
  // 8888 first so the Spotify Redirect URI people register stays the same
  for (let p = 8888; p < 8898; p++) {
    try { server = await listen(p); return p; } catch (e) { /* port busy, try next */ }
  }
  throw new Error('No free port');
}

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => { if (win) { if (win.isMinimized()) win.restore(); win.focus(); } });

  app.whenReady().then(async () => {
    const port = await startServer();
    startPS();

    // System audio: hand the page the screen + loopback audio with no picker dialog
    session.defaultSession.setDisplayMediaRequestHandler((req, cb) => {
      desktopCapturer.getSources({ types: ['screen'] })
        .then(src => cb({ video: src[0], audio: 'loopback' }))
        .catch(() => cb({}));
    }, { useSystemPicker: false });

    if (process.env.LG_SMOKE) { // headless self-test
      setTimeout(async () => {
        const np = await (await fetch(`http://127.0.0.1:${port}/api/nowplaying`)).text();
        const pg = await fetch(`http://127.0.0.1:${port}/lyric-glow.html`);
        console.log(JSON.stringify({ port, page: pg.status, nowplaying: np }));
        app.quit();
      }, 3500);
      return;
    }

    if (process.env.LG_CAPTURE_TEST) { // self-test: run the real capture path and report what the analyser hears
      const tw = new BrowserWindow({ width: 900, height: 500, show: true, webPreferences: { contextIsolation: true, sandbox: true, backgroundThrottling: false } });
      await tw.loadURL(`http://127.0.0.1:${port}/lyric-glow.html`);
      await new Promise(r => setTimeout(r, 1500));
      const out = await tw.webContents.executeJavaScript(`(async()=>{
        document.getElementById('live').click();
        await new Promise(r=>setTimeout(r,2500));
        let peak=0,n=0;for(let i=0;i<30;i++){await new Promise(r=>setTimeout(r,100));const d=new Uint8Array(anL.frequencyBinCount);anL.getByteFrequencyData(d);const m=Math.max(...d);if(m>peak)peak=m;n++}
        return JSON.stringify({live, peakLevel:peak, acState:ac.state, dbg:document.getElementById('dbg').textContent, status:document.getElementById('spst').textContent,
          tracks:(capStream?capStream.getTracks().map(t=>t.kind+':'+t.readyState):null)});
      })()`, true).catch(e => 'ERR ' + e);
      console.log('CAPTURE_TEST ' + out);
      app.quit();
      return;
    }

    Menu.setApplicationMenu(null);
    win = new BrowserWindow({
      width: 1280, height: 760, minWidth: 720, minHeight: 480,
      backgroundColor: '#000000', title: 'Lyric Glow', autoHideMenuBar: true,
      icon: path.join(__dirname, 'icon.png'),
      webPreferences: { contextIsolation: true, sandbox: true, backgroundThrottling: false }
    });
    win.loadURL(`http://127.0.0.1:${port}/lyric-glow.html`);
    win.webContents.setWindowOpenHandler(({ url }) => { shell.openExternal(url); return { action: 'deny' }; });
    // start beat-reactive audio capture automatically (executeJavaScript with userGesture=true)
    win.webContents.on('did-finish-load', () => {
      if (win.webContents.getURL().includes('code=')) return;
      setTimeout(() => win.webContents.executeJavaScript("document.getElementById('live')&&document.getElementById('live').click()", true).catch(() => {}), 1500);
    });
  });

  app.on('window-all-closed', () => app.quit());
  app.on('before-quit', () => { try { ps && ps.kill(); } catch (e) {} try { server && server.close(); } catch (e) {} });
}
