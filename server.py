"""Lyric Glow local server (made by Chaz).
Serves the page and, on Windows, exposes what the PC is currently playing at /api/nowplaying
by running nowplaying.ps1 in the background. Also: play/pause/skip (/api/control) and per-app audio
for the beat/wave (/api/audioapps, /api/audiotarget, /api/spectrum). Everything stays on this machine."""
import atexit, http.server, os, re, subprocess, sys, tempfile, threading, urllib.parse

PORT = 8888
HERE = os.path.dirname(os.path.abspath(__file__))
os.chdir(HERE)
latest = b'{"playing":false}'
proc = None
EMPTY_SPEC = b'{"b":[]}'
latest_spec = EMPTY_SPEC
cap = None
FLAGS = getattr(subprocess, 'CREATE_NO_WINDOW', 0)
PS = ['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File']

def pump():
    global latest, proc
    if os.name != 'nt' or not os.path.exists('nowplaying.ps1'):
        return
    proc = subprocess.Popen(PS + ['nowplaying.ps1'],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, creationflags=FLAGS)
    for line in proc.stdout:
        line = line.strip()
        if line.startswith(b'{'):
            latest = line

def stop_cap():
    global cap, latest_spec
    if cap:
        try:
            cap.kill()
        except OSError:
            pass
        cap = None
    latest_spec = EMPTY_SPEC

def read_cap(p):
    global latest_spec
    for line in p.stdout:
        line = line.strip()
        if line.startswith(b'{'):
            latest_spec = line

def start_cap(pid):
    global cap
    stop_cap()
    if os.name != 'nt' or not os.path.exists('appaudio.ps1'):
        return
    cap = subprocess.Popen(PS + ['appaudio.ps1', 'capture', str(pid)],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, creationflags=FLAGS)
    threading.Thread(target=read_cap, args=(cap,), daemon=True).start()

def list_apps():
    if os.name != 'nt' or not os.path.exists('appaudio.ps1'):
        return b'[]'
    try:
        out = subprocess.run(PS + ['appaudio.ps1', 'list'], capture_output=True, timeout=20, creationflags=FLAGS).stdout.strip()
        return out or b'[]'
    except (subprocess.SubprocessError, OSError):
        return b'[]'

class Handler(http.server.SimpleHTTPRequestHandler):
    def _json(self, body):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        path = self.path.split('?')[0]
        if path == '/api/nowplaying':
            self._json(latest)
        elif path == '/api/spectrum':
            self._json(latest_spec)
        elif path == '/api/audioapps':
            self._json(list_apps())
        else:
            super().do_GET()
    def do_POST(self):
        # play/pause/skip + choosing which app's audio to listen to. POST + custom header + same-origin
        # check, so other websites can't trigger it.
        parsed = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(parsed.query)
        origin = self.headers.get('Origin', '')
        ok = self.headers.get('X-LG') == '1' and ((not origin) or re.fullmatch(r'http://127\.0\.0\.1:\d+', origin))
        status = 403
        if ok and parsed.path == '/api/control' and q.get('cmd', [''])[0] in ('playpause', 'play', 'pause', 'next', 'prev'):
            try:
                with open(os.path.join(tempfile.gettempdir(), 'lyricglow_cmd.txt'), 'w') as f:
                    f.write(q['cmd'][0])
                status = 204
            except OSError:
                status = 500
        elif ok and parsed.path == '/api/audiotarget' and re.fullmatch(r'\d{1,7}', q.get('pid', [''])[0]):
            pid = int(q['pid'][0])
            if pid > 0:
                start_cap(pid)
            else:
                stop_cap()
            status = 204
        self.send_response(status)
        self.end_headers()
    def log_message(self, *a):
        pass

atexit.register(lambda: (proc and proc.kill(), stop_cap()))
threading.Thread(target=pump, daemon=True).start()
try:
    http.server.ThreadingHTTPServer(('127.0.0.1', PORT), Handler).serve_forever()
except OSError:
    print('Port %d is busy. Close the other Lyric Glow window first.' % PORT)
    input('Press Enter...')
except KeyboardInterrupt:
    sys.exit(0)
