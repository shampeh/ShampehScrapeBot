# 🤖 Shampeh.scrape.bot

A dark, themed browser-based GUI for **yt-dlp** — download entire channels, playlists, and profiles from 9 platforms with a scheduled monitor, live progress tracking, and 27 visual themes including animated live wallpapers.

---

## ✨ Features

- **One-click downloads** — paste a URL, hit `+ QUEUE`, it runs immediately
- **Scheduled monitor** — add URLs to a watch list and auto-check every X minutes
- **Smart skip** — if you already have the latest video, it skips the entire scrape automatically
- **Live progress** — shows `Item 9 of 47` in real time as yt-dlp downloads
- **27 themes** — Dark, Light, Matrix, Ocean, Harry Potter, Taylor Swift, 6 Christmas themes, 5 Halloween themes, 5 live animated wallpapers (Ocean waves, Aurora, Lava, Galaxy, Forest)
- **Per-URL controls** — Run Now, Pause, Resume, Cancel for each monitored URL
- **Activity log** — timestamped session log of everything that happens
- **Persistent monitors** — your watched URLs survive browser restarts via localStorage
- **Default theme memory** — set any theme as your default launch theme

---

## 📦 Supported Sites

| Platform | Type |
|---|---|
| YouTube | Channels, playlists, individual videos |
| Twitch | Channels, VODs |
| TikTok | Profiles |
| Kick | Channels |
| Rumble | Channels |
| X / Twitter | Profiles, tweets with video |
| Reddit | Subreddits, user posts |
| Facebook | Pages, public videos |
| SoundCloud | Artists, playlists |

---

## 🗂 File Overview

| File | Purpose |
|---|---|
| `yt-dlp-gui.html` | The main app — open this in your browser |
| `server.js` | Local Node.js server that bridges the UI to PowerShell |
| `start.bat` | Double-click launcher — starts the server and opens the app |
| `gen4.ps1` | PowerShell script that runs yt-dlp with all the right flags |
| `preview.html` | Standalone UI preview — works without the server (phone friendly) |

---

## ⚙️ Requirements

Before running, make sure you have:

- [**Node.js**](https://nodejs.org) — v18 or later
- [**yt-dlp.exe**](https://github.com/yt-dlp/yt-dlp/releases) — place in the same folder
- [**ffmpeg.exe**](https://ffmpeg.org/download.html) — place in the same folder (required for merging video/audio and embedding metadata)

> All four must live in the **same folder**.

---

## 🚀 How to Run

1. Download and extract the zip
2. Place `yt-dlp.exe` and `ffmpeg.exe` in the folder
3. Double-click **`start.bat`**
   - This starts the local server on port `51789`
   - Opens `yt-dlp-gui.html` in your browser automatically
4. The status bar will turn green: **Server connected — ready**
5. Paste a URL and hit `+ QUEUE` or `+ MONITOR`

---

## 🔧 How It Works

```
Browser (yt-dlp-gui.html)
        │
        │  HTTP POST /run  { url: "..." }
        ▼
Local Server (server.js)  ← Node.js, port 51789
        │
        │  spawns process
        ▼
PowerShell (gen4.ps1)
        │
        │  runs yt-dlp.exe with flags
        ▼
yt-dlp.exe  →  downloads to folder named after the channel
```

### Step by step

**1. You paste a URL and click `+ QUEUE`**
The browser sends a `POST /run` request to the local Node.js server running on your machine.

**2. The server spawns PowerShell**
`server.js` runs `gen4.ps1` via `powershell.exe`, passing your URL as a parameter. It captures all stdout/stderr output in real time.

**3. gen4.ps1 does the smart work**
Before downloading anything, it asks yt-dlp for just the first (newest) item in the channel. If that item already exists in your local folder or archive file, it exits immediately with code `10` (skipped). This means re-running a channel you already have takes seconds, not minutes.

**4. If new content exists, yt-dlp downloads everything new**
It uses a download archive file (`zzArchive/archive-channelname.txt`) to track what's been downloaded before, so it never re-downloads a file you already have.

**5. The browser polls for progress**
Every 800ms the browser calls `GET /status/:jobId` to get new log lines. It parses `[download] Downloading item X of Y` to show a real progress bar.

**6. When done, the job auto-removes from Active Jobs**
After 3 seconds the completed job disappears from the UI. The result is logged permanently in the Activity Log.

### Scheduled Monitor

When you click `+ MONITOR` instead of `+ QUEUE`, the URL is saved to a watch list in your browser's localStorage. The scheduler fires every X minutes (you set this) and runs each unpaused URL through the same download pipeline. Because of the smart skip logic in `gen4.ps1`, channels that are already up to date finish in seconds.

### Cancel

Clicking **CANCEL** on a running job sends a `POST /kill/:jobId` to the server, which runs `taskkill /PID ... /T /F` — killing the PowerShell process and the yt-dlp child process instantly.

---

## 📁 Output Structure

Downloads are saved next to `gen4.ps1` in folders named after the channel:

```
📁 D:\ttclaud\
  ├── yt-dlp-gui.html
  ├── server.js
  ├── start.bat
  ├── gen4.ps1
  ├── yt-dlp.exe
  ├── ffmpeg.exe
  │
  ├── 📁 MrBeast\
  │     ├── 20240101 - Video Title [abc123].mkv
  │     └── 20240215 - Another Video [def456].mkv
  │
  ├── 📁 monstercat - Twitch\
  │     └── ...
  │
  └── 📁 zzArchive\
        ├── archive-MrBeast.txt
        └── archive-monstercat - Twitch.txt
```

Files are named: `YYYYMMDD - Title [VideoID].mkv`

---

## 🎨 Themes

Switch themes any time from the dropdown in the top-right corner — even while downloads are running.

| Category | Themes |
|---|---|
| Base | Dark, Light, Blue, Hacker |
| Nature | Ocean, Dark Ocean, Jaws |
| Pop culture | Harry Potter, Taylor Swift, Dark Fantasy |
| Christmas | Classic, Snow, Cozy (embers), Candy, Ice, Retro |
| Halloween | Classic, Witch, Ghost, Blood, Zombie |
| Live Wallpaper | 🌊 Ocean waves, 🌌 Aurora borealis, 🌋 Lava, 🔭 Galaxy, 🌲 Forest fireflies |

When you change theme, you'll be asked **"make new default?"** — click YES to always launch in that theme.

---

## 🔑 Advanced Options

Click **ADVANCED OPTIONS** to access:

- **Format & Quality** — Best quality, Max 1080p, Max 720p, Audio only, M4A
- **Container** — MKV, MP4, WebM, MP3
- **Embed** — Subtitles (English), Thumbnail, Metadata, Chapters
- **File behaviour** — No overwrites, Download archive, Restrict filenames, Continue on error
- **Output template** — Filename format options

---

## 🧹 Resetting

Your monitored URLs and settings are saved in your browser's localStorage, tied to the file path. To wipe everything:

- Click **RESET ALL DATA** in the Activity Log section, or
- Open browser console (F12) and run `localStorage.clear()`

---

## 📋 Notes

- The app only works when `start.bat` is running — the server must be active for downloads to work
- `preview.html` works standalone without the server — useful for checking themes on mobile
- Multiple URLs can be queued and will run in parallel
- The `zzArchive` folder keeps track of everything downloaded so re-runs are always safe

---

## 📄 License

MIT — do whatever you want with it.
