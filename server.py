"""Lyric Glow local server (made by Chaz).
Serves the page and, on Windows, exposes what the PC is currently playing at /api/nowplaying
by running nowplaying.ps1 in the background. Everything stays on this machine."""
import atexit, http.server, os, re, subprocess, sys, tempfile, threading, urllib.parse

PORT = 8888
HERE = os.path.dirname(os.path.abspath(__file__))
os.chdir(HERE)
latest = b'{"playing":false}'
proc = None

def pump():
    global latest, proc
    if os.name != 'nt' or not os.path.exists('nowplaying.ps1'):
        return
    flags = getattr(subprocess, 'CREATE_NO_WINDOW', 0)
    proc = subprocess.Popen(
        ['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'nowplaying.ps1'],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, creationflags=flags)
    for line in proc.stdout:
        line = line.strip()
        if line.startswith(b'{'):
            latest = line

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path.split('?')[0] == '/api/nowplaying':
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(latest)
        else:
            super().do_GET()
    def do_POST(self):
        # play/pause/skip via the Windows media session. POST + custom header + same-origin check,
        # so other websites can't trigger it.
        parsed = urllib.parse.urlparse(self.path)
        cmd = urllib.parse.parse_qs(parsed.query).get('cmd', [''])[0]
        origin = self.headers.get('Origin', '')
        ok_origin = (not origin) or re.fullmatch(r'http://127\.0\.0\.1:\d+', origin)
        if (parsed.path == '/api/control' and self.headers.get('X-LG') == '1' and ok_origin
                and cmd in ('playpause', 'play', 'pause', 'next', 'prev')):
            try:
                with open(os.path.join(tempfile.gettempdir(), 'lyricglow_cmd.txt'), 'w') as f:
                    f.write(cmd)
                self.send_response(204)
            except OSError:
                self.send_response(500)
        else:
            self.send_response(403)
        self.end_headers()
    def log_message(self, *a):
        pass

atexit.register(lambda: proc and proc.kill())
threading.Thread(target=pump, daemon=True).start()
try:
    http.server.ThreadingHTTPServer(('127.0.0.1', PORT), Handler).serve_forever()
except OSError:
    print('Port %d is busy. Close the other Lyric Glow window first.' % PORT)
    input('Press Enter...')
except KeyboardInterrupt:
    sys.exit(0)
