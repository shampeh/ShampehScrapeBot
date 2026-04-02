const http = require('http');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const PORT = 51789;
const DIR  = __dirname;

// Track active jobs: id -> { process, status, log, url }
const jobs = {};
let jobCounter = 1;

const server = http.createServer((req, res) => {
  // CORS — allow the local HTML file to call us
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  const url = new URL(req.url, `http://localhost:${PORT}`);

  // ── POST /run — start a download
  if (req.method === 'POST' && url.pathname === '/run') {
    let body = '';
    req.on('data', d => body += d);
    req.on('end', () => {
      let parsed;
      try { parsed = JSON.parse(body); } catch { respond(res, 400, { error: 'Bad JSON' }); return; }

      const inputUrl = (parsed.url || '').trim();
      if (!inputUrl) { respond(res, 400, { error: 'No URL' }); return; }

      const id = jobCounter++;
      const ps1 = path.join(DIR, 'gen4.ps1');

      if (!fs.existsSync(ps1)) {
        respond(res, 500, { error: 'gen4.ps1 not found in server directory' });
        return;
      }

      const job = { id, url: inputUrl, status: 'running', log: [], startedAt: Date.now() };
      jobs[id] = job;

      const proc = spawn('powershell.exe', [
        '-ExecutionPolicy', 'Bypass',
        '-File', ps1,
        '-InputUrl', inputUrl
      ], { cwd: DIR });

      job.process = proc;

      proc.stdout.on('data', d => {
        const lines = d.toString().split(/\r?\n/).filter(Boolean);
        lines.forEach(l => job.log.push({ t: Date.now(), msg: l, type: 'out' }));
      });

      proc.stderr.on('data', d => {
        const lines = d.toString().split(/\r?\n/).filter(Boolean);
        lines.forEach(l => job.log.push({ t: Date.now(), msg: l, type: 'err' }));
      });

      proc.on('close', code => {
        job.status = code === 0 ? 'done' : code === 10 ? 'skipped' : 'error';
        job.exitCode = code;
        job.process = null;
      });

      respond(res, 200, { id });
    });
    return;
  }

  // ── GET /status/:id — poll job status + new log lines
  const statusMatch = url.pathname.match(/^\/status\/(\d+)$/);
  if (req.method === 'GET' && statusMatch) {
    const id = parseInt(statusMatch[1]);
    const job = jobs[id];
    if (!job) { respond(res, 404, { error: 'Job not found' }); return; }

    const since = parseInt(url.searchParams.get('since') || '0');
    const newLines = job.log.filter(l => l.t > since);

    respond(res, 200, {
      id: job.id,
      url: job.url,
      status: job.status,
      exitCode: job.exitCode ?? null,
      log: newLines,
      lastT: job.log.length ? job.log[job.log.length - 1].t : 0
    });
    return;
  }

  // ── POST /kill/:id — kill a running job
  const killMatch = url.pathname.match(/^\/kill\/(\d+)$/);
  if (req.method === 'POST' && killMatch) {
    const id = parseInt(killMatch[1]);
    const job = jobs[id];
    if (!job) { respond(res, 404, { error: 'Job not found' }); return; }
    if (job.process) {
      try {
        // Kill the whole process tree (powershell spawns child yt-dlp)
        const { execSync } = require('child_process');
        execSync(`taskkill /PID ${job.process.pid} /T /F`, { stdio: 'ignore' });
      } catch {}
      job.process = null;
    }
    job.status = 'error';
    job.log.push({ t: Date.now(), msg: 'Job cancelled by user.', type: 'err' });
    respond(res, 200, { ok: true });
    return;
  }

  // ── GET /ping — health check
  if (req.method === 'GET' && url.pathname === '/ping') {
    respond(res, 200, { ok: true });
    return;
  }

  respond(res, 404, { error: 'Not found' });
});

function respond(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, { 'Content-Type': 'application/json' });
  res.end(body);
}

server.listen(PORT, '127.0.0.1', () => {
  console.log(`SHAMP.SCRAPE.BOT server running on http://127.0.0.1:${PORT}`);
  console.log(`Place gen4.ps1 and yt-dlp.exe in the same folder as this file.`);
});
