# Lyric Glow

Animated, karaoke-style lyrics, a spinning vinyl and beat-reactive edge lighting for whatever you're listening to. Inspired by those "desk setup" reels, built from scratch.

**Made by Chaz.**

- Lyrics sync to the song and fill in word by word (toggleable)
- Full-height vinyl with the album cover as the label, a tonearm that creeps across as the song plays
- Edge glow in the cover's dominant colour that flashes on the beat (toggleable)
- Flowing sound-wave visualiser driven by the live spectrum (toggleable)
- Play / pause / next / previous from the panel buttons (no keyboard shortcuts, so nothing fires while you're gaming): through Windows' media controls (any player, no Premium), or through Spotify's API if you're connected (Premium, also works for cast speakers)
- Pick which app the beat and wave listen to (Windows per-app audio), so games and Discord don't trigger the glow
- Better lyric matching, with an "estimated timing" fallback when only un-timed lyrics exist
- Reads what's playing from **Spotify** or straight from **your PC** (Windows), no account needed
- Lyrics from [LRCLIB](https://lrclib.net), cover art from Apple's public search, BPM from [ReccoBeats](https://reccobeats.com)

## Ways to run it

| | Works on | Needs | Spotify login | Auto-detect what's playing |
|---|---|---|---|---|
| **Windows app** (`app/`) | Windows | nothing (download the `.exe`) | yes | yes |
| **`serve.bat`** | Windows (+ any OS via `python server.py`) | Python | yes | Windows only |
| **`lyric-glow.html`** on its own | anything with a browser | nothing | no | no, use *Search a song* |

On a plain double-clicked `.html`, type a song in **Search a song**, hit **Find lyrics + cover**, then press **Start** the moment it begins. Nudge with **Lyric offset** if it drifts.

## Website

`docs/` is the GitHub Pages site: `index.html` is the landing page and `app.html` is the web app (a copy of `lyric-glow.html`, so re-copy it after editing: `cp lyric-glow.html docs/app.html`). Served at **https://karaokechaz.duckdns.org**. On the web version Spotify login uses `https://karaokechaz.duckdns.org/app.html` as its Redirect URI.

## Quick start

**Windows app:** grab `Lyric-Glow.exe` from the Releases page (or build it, below) and double-click it. Windows SmartScreen will say "unknown publisher" because the app is unsigned: **More info → Run anyway**. In the setup guide choose **Skip, use my PC's player** for zero setup.

**With Python:** double-click `serve.bat` (runs `server.py`, opens `http://127.0.0.1:8888/lyric-glow.html`).

## Connecting Spotify (optional)

Spotify only lets an app's creator (plus a few allow-listed users) log in while it's in development mode, so each person makes their own free app. The in-app setup guide walks through it:

1. Create an app at <https://developer.spotify.com/dashboard>, tick **Web API**.
2. Add the Redirect URI the guide shows you (`http://127.0.0.1:8888/lyric-glow.html`).
3. Add your own Spotify email under **User Management**.
4. Paste the **Client ID** into Lyric Glow and hit **Connect Spotify**.

Auth uses PKCE in the browser, so there's no secret and no backend. Tokens stay in `localStorage`.

## Beat flash

- **App / `serve.bat`:** the app captures system audio automatically (Windows loopback). In a browser use **Capture system audio**, pick *Entire Screen*, tick *Share system audio*.
- **Spotify on a cast speaker?** The audio never touches your PC, so Lyric Glow falls back to the song's BPM (from ReccoBeats) or **Tap tempo**.
- Don't want flashing? Untick **Beat flash**.

Keys: `H` hide/show panel · `F` fullscreen. (No playback keys, on purpose.)

## Build the Windows app

Needs Node.js.

```bash
cd app
npm install
node node_modules/electron/install.js   # newer npm skips Electron's install script
npm run build                            # → app/dist/Lyric-Glow.exe (portable)
```

`npm start` runs it without packaging. `app/sync.js` copies the page and helper from the repo root into `app/` before each run/build.

## Layout

```
lyric-glow.html    the whole UI (single file, no dependencies)
serve.bat          launcher for the Python route
server.py          static server + /api/nowplaying
nowplaying.ps1     reads Windows' media session (title, artist, position)
make-icon.js       draws the app icon (no dependencies)
app/               Electron wrapper
```

## Notes and limits

- Auto-detect uses Windows' media-session API, so it's Windows only. A macOS version would need AppleScript for Spotify / Apple Music.
- Word-level fill timing is estimated from line timings and tempo; LRCLIB only has line-level timestamps.
- Lyrics and BPM come from free third-party services and don't cover every track.
