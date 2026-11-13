"""Lyric Glow local server (made by Chaz).
Serves the page and, on Windows, exposes what the PC is currently playing at /api/nowplaying
by running nowplaying.ps1 in the background. Everything stays on this machine."""
import atexit, http.server, os, subprocess, sys, threading

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
