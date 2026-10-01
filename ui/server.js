#!/usr/bin/env node
/**
 * NOGAP Proxy Command Center - Local Web Server & API
 * Provides live telemetry, log streaming (SSE), split-tunnel verification,
 * latency benchmarking, and one-click controls for the workstation proxy.
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const { exec, spawn } = require('child_process');
const os = require('os');

const PORT = process.env.UI_PORT || 3130;
const HOST = '127.0.0.1';
const ROOT_DIR = path.resolve(__dirname, '..');
const PUBLIC_DIR = path.join(__dirname, 'public');
const FORWARDER_DIR = path.join(os.homedir(), '.nogap-proxy-forwarder');
const ACCESS_LOG_PATH = path.join(FORWARDER_DIR, 'access.log');
const PID_FILE_PATH = path.join(FORWARDER_DIR, 'squid.pid');
const CONF_FILE_PATH = path.join(FORWARDER_DIR, 'squid.conf');
const ENV_FILE_PATH = path.join(ROOT_DIR, 'scripts', 'workstation-proxy.env');

// Active SSE client connections
const sseClients = new Set();

// Cache for egress IP and latency checks
let cachedStatus = {
  forwarderRunning: false,
  forwarderPid: null,
  uptimeSeconds: 0,
  memoryUsageMb: 0,
  upstreamHost: '52.6.50.56',
  upstreamPort: 443,
  upstreamUser: 'proxyuser01',
  currentEgressIp: '52.6.50.56',
  directIp: null,
  lastEgressCheck: null,
  egressLatencyMs: null
};

// MIME types
const MIME_TYPES = {
  '.html': 'text/html; charset=UTF-8',
  '.css': 'text/css; charset=UTF-8',
  '.js': 'application/javascript; charset=UTF-8',
  '.json': 'application/json; charset=UTF-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon'
};

function parseLogLine(line) {
  if (!line || !line.trim()) return null;
  // Format: timestamp.msec duration client_ip action/code bytes method URL user hierarchy_code/ip type
  // Example: 1790765249.545 2039 127.0.0.1 TCP_TUNNEL/200 6563 CONNECT sts.us-east-1.amazonaws.com:443 - FIRSTUP_PARENT/52.6.50.56 -
  const parts = line.trim().split(/\s+/);
  if (parts.length < 8) return null;

  const rawTime = parseFloat(parts[0]);
  const date = !isNaN(rawTime) ? new Date(rawTime * 1000) : new Date();
  const durationMs = parseInt(parts[1], 10) || 0;
  const clientIp = parts[2];
  const statusCodeStr = parts[3]; // e.g. TCP_TUNNEL/200 or TCP_DENIED/403
  const bytes = parseInt(parts[4], 10) || 0;
  const method = parts[5];
  const target = parts[6];
  const user = parts[7] === '-' ? null : parts[7];
  const upstream = parts[8] || '-';

  // Parse HTTP code
  let httpCode = 200;
  if (statusCodeStr.includes('/')) {
    httpCode = parseInt(statusCodeStr.split('/')[1], 10) || 200;
  }

  // Parse hostname and port
  let host = target;
  let port = '443';
  if (target.includes(':')) {
    const splitTarget = target.split(':');
    host = splitTarget[0];
    port = splitTarget[1];
  }

  // Categorize service
  let category = 'external';
  let badgeLabel = 'External';
  let badgeColor = 'blue';

  if (host.includes('dynamodb')) {
    category = 'aws-dynamodb';
    badgeLabel = 'DynamoDB';
    badgeColor = 'amber';
  } else if (host.includes('cognito') || host.includes('auth.')) {
    category = 'aws-cognito';
    badgeLabel = 'Cognito';
    badgeColor = 'purple';
  } else if (host.includes('.s3.') || host.endsWith('.s3.amazonaws.com')) {
    category = 'aws-s3';
    badgeLabel = 'S3 Storage';
    badgeColor = 'emerald';
  } else if (host.includes('secretsmanager')) {
    category = 'aws-secrets';
    badgeLabel = 'Secrets Mgr';
    badgeColor = 'red';
  } else if (host.includes('sts.')) {
    category = 'aws-sts';
    badgeLabel = 'AWS STS';
    badgeColor = 'amber';
  } else if (host.includes('amazonaws.com')) {
    category = 'aws-other';
    badgeLabel = 'AWS Service';
    badgeColor = 'amber';
  } else if (host.includes('nogap.ai')) {
    category = 'nogap-api';
    badgeLabel = 'NoGap API';
    badgeColor = 'cyan';
  } else if (host.includes('google') || host.includes('gstatic')) {
    category = 'google';
    badgeLabel = 'Google / CDN';
    badgeColor = 'indigo';
  } else if (host.includes('ipify')) {
    category = 'diagnostics';
    badgeLabel = 'IP Diagnostic';
    badgeColor = 'emerald';
  }

  // Client source type
  const isDocker = clientIp.startsWith('172.') || clientIp.startsWith('10.');
  const sourceLabel = isDocker ? 'Docker Container' : 'Workstation (Host)';

  return {
    raw: line,
    isoTime: date.toISOString(),
    displayTime: date.toLocaleTimeString(),
    timestamp: Math.round(rawTime * 1000),
    durationMs,
    clientIp,
    sourceLabel,
    isDocker,
    statusCodeStr,
    httpCode,
    bytes,
    method,
    target,
    host,
    port,
    user,
    upstream,
    category,
    badgeLabel,
    badgeColor
  };
}

function getSystemMetrics(callback) {
  // Check if forwarder is running
  exec('pgrep -f "squid.*nogapfwd" | head -n 1', (err, stdout) => {
    const pid = stdout.trim();
    cachedStatus.forwarderRunning = Boolean(pid);
    cachedStatus.forwarderPid = pid ? parseInt(pid, 10) : null;

    // Check listening ports for local backend (4000) and frontend (3000)
    exec('ss -tulpn', (ssErr, ssStdout) => {
      const output = ssStdout || '';
      cachedStatus.port3000Ready = output.includes(':3000 ');
      cachedStatus.port4000Ready = output.includes(':4000 ');

      if (!pid) {
        cachedStatus.uptimeSeconds = 0;
        cachedStatus.memoryUsageMb = 0;
        return callback(cachedStatus);
      }

      // Get process stats (memory & uptime)
      exec(`ps -p ${pid} -o etimes=,rss=`, (psErr, psStdout) => {
        if (!psErr && psStdout) {
          const [etimes, rss] = psStdout.trim().split(/\s+/);
          cachedStatus.uptimeSeconds = parseInt(etimes, 10) || 0;
          cachedStatus.memoryUsageMb = ((parseInt(rss, 10) || 0) / 1024).toFixed(1);
        }

        // Read upstream config
        if (fs.existsSync(CONF_FILE_PATH)) {
          try {
            const conf = fs.readFileSync(CONF_FILE_PATH, 'utf8');
            const peerMatch = conf.match(/cache_peer\s+([^\s]+)\s+parent\s+(\d+)/);
            if (peerMatch) {
              cachedStatus.upstreamHost = peerMatch[1];
              cachedStatus.upstreamPort = parseInt(peerMatch[2], 10);
            }
            const userMatch = conf.match(/login=([^:]+):/);
            if (userMatch) {
              cachedStatus.upstreamUser = userMatch[1];
            }
          } catch (_) {}
        }

        callback(cachedStatus);
      });
    });
  });
}

// Watch access.log for live SSE updates
let lastLogSize = 0;
function setupLogWatcher() {
  if (!fs.existsSync(ACCESS_LOG_PATH)) {
    setTimeout(setupLogWatcher, 2000);
    return;
  }

  try {
    const stat = fs.statSync(ACCESS_LOG_PATH);
    lastLogSize = stat.size;
  } catch (_) {}

  fs.watch(ACCESS_LOG_PATH, (eventType) => {
    if (eventType !== 'change') return;
    try {
      const stat = fs.statSync(ACCESS_LOG_PATH);
      if (stat.size > lastLogSize) {
        const stream = fs.createReadStream(ACCESS_LOG_PATH, {
          start: lastLogSize,
          end: stat.size
        });
        let chunk = '';
        stream.on('data', d => { chunk += d.toString('utf8'); });
        stream.on('end', () => {
          lastLogSize = stat.size;
          const lines = chunk.split('\n');
          for (const line of lines) {
            const parsed = parseLogLine(line);
            if (parsed) {
              const eventPayload = `data: ${JSON.stringify(parsed)}\n\n`;
              for (const client of sseClients) {
                client.write(eventPayload);
              }
            }
          }
        });
      } else if (stat.size < lastLogSize) {
        // Log truncated / rotated
        lastLogSize = stat.size;
      }
    } catch (_) {}
  });
}

setupLogWatcher();

// HTTP Request Handler
const server = http.createServer((req, res) => {
  const parsedUrl = new URL(req.url, `http://${req.headers.host}`);
  const pathname = parsedUrl.pathname;

  // Enable CORS for local testing
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    return res.end();
  }

  // API Endpoints
  if (pathname === '/api/status') {
    return getSystemMetrics(status => {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(status));
    });
  }

  if (pathname === '/api/logs') {
    const limit = parseInt(parsedUrl.searchParams.get('limit') || '150', 10);
    if (!fs.existsSync(ACCESS_LOG_PATH)) {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ logs: [], total: 0 }));
    }

    exec(`tail -n ${limit} "${ACCESS_LOG_PATH}"`, (err, stdout) => {
      if (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ error: err.message }));
      }
      const rawLines = stdout.trim().split('\n').filter(Boolean);
      const parsedLogs = rawLines.map(parseLogLine).filter(Boolean).reverse();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ logs: parsedLogs, total: parsedLogs.length }));
    });
    return;
  }

  // Real-time Server-Sent Events (SSE)
  if (pathname === '/api/stream-logs') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive'
    });
    res.write('retry: 3000\n\n');
    sseClients.add(res);

    req.on('close', () => {
      sseClients.delete(res);
    });
    return;
  }

  // One-click actions
  if (req.method === 'POST' && pathname === '/api/action/test-egress') {
    const start = Date.now();
    exec('curl -x http://127.0.0.1:3129 -s --max-time 6 https://api.ipify.org', (err, stdout) => {
      const latencyMs = Date.now() - start;
      if (err) {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({
          success: false,
          error: err.message,
          latencyMs
        }));
      }
      const egressIp = stdout.trim();
      cachedStatus.currentEgressIp = egressIp;
      cachedStatus.lastEgressCheck = new Date().toISOString();
      cachedStatus.egressLatencyMs = latencyMs;

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        success: true,
        egressIp,
        isExpectedProxyIp: egressIp === cachedStatus.upstreamHost,
        latencyMs,
        checkedAt: cachedStatus.lastEgressCheck
      }));
    });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/action/benchmark') {
    // Perform comparative latency test
    const cmd = `
      CURL_LOCAL=$(curl -w "%{time_total}" -o /dev/null -s "http://127.0.0.1:3129" 2>&1 || echo "0")
      CURL_EC2_TLS=$(curl -w "%{time_connect},%{time_appconnect},%{time_total}" -o /dev/null -s -k "https://52.6.50.56:443" 2>&1 || echo "0,0,0")
      CURL_TUNNEL=$(curl -x http://127.0.0.1:3129 -w "%{time_connect},%{time_starttransfer},%{time_total}" -o /dev/null -s "https://api.ipify.org" 2>&1 || echo "0,0,0")
      echo "$CURL_LOCAL|$CURL_EC2_TLS|$CURL_TUNNEL"
    `;

    exec(cmd, (err, stdout) => {
      const parts = (stdout || '').trim().split('|');
      const localTime = parseFloat(parts[0]) || 0;
      const [ec2Tcp, ec2Tls, ec2Total] = (parts[1] || '0,0,0').split(',').map(s => parseFloat(s) || 0);
      const [tunnelConnect, tunnelTtfb, tunnelTotal] = (parts[2] || '0,0,0').split(',').map(s => parseFloat(s) || 0);

      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        localForwarderLatencyMs: Math.round(localTime * 1000),
        ec2TcpLatencyMs: Math.round(ec2Tcp * 1000),
        ec2TlsHandshakeMs: Math.round((ec2Tls - ec2Tcp) * 1000),
        tunnelTotalLatencyMs: Math.round(tunnelTotal * 1000),
        locationSummary: 'India -> US East (us-east-1) Transatlantic RTT'
      }));
    });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/action/restart') {
    exec(`bash "${path.join(ROOT_DIR, 'scripts', 'start-local-forwarder.sh')}"`, (err, stdout, stderr) => {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        success: !err,
        output: stdout + stderr
      }));
    });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/action/stop') {
    exec(`bash "${path.join(ROOT_DIR, 'scripts', 'stop-local-forwarder.sh')}"`, (err, stdout, stderr) => {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        success: !err,
        output: stdout + stderr
      }));
    });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/action/start') {
    exec(`bash "${path.join(ROOT_DIR, 'scripts', 'start-local-forwarder.sh')}"`, (err, stdout, stderr) => {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        success: !err,
        output: stdout + stderr
      }));
    });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/action/launch-chrome') {
    const chromeScript = path.join(ROOT_DIR, 'scripts', 'chrome-via-proxy.sh');
    const targetUrl = 'http://localhost:3000';
    exec(`bash "${chromeScript}" local-manual "${targetUrl}" >/dev/null 2>&1 &`, (err) => {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        success: !err,
        targetUrl,
        message: 'Chrome launched with isolated proxy profile'
      }));
    });
    return;
  }

  // EC2 Power Management
  if (pathname === '/api/ec2/status') {
    const ec2Script = path.join(ROOT_DIR, 'scripts', 'ec2-control.sh');
    exec(`bash "${ec2Script}" json`, (err, stdout) => {
      try {
        const data = JSON.parse(stdout);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(data));
      } catch (e) {
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ instanceId: 'i-0557dd46215ef359f', state: 'unknown', publicIp: '52.6.50.56' }));
      }
    });
    return;
  }

  if (req.method === 'POST' && pathname === '/api/ec2/start') {
    const ec2Script = path.join(ROOT_DIR, 'scripts', 'ec2-control.sh');
    exec(`bash "${ec2Script}" start >/dev/null 2>&1 &`, () => {});
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, message: 'EC2 start command sent' }));
    return;
  }

  if (req.method === 'POST' && pathname === '/api/ec2/stop') {
    const ec2Script = path.join(ROOT_DIR, 'scripts', 'ec2-control.sh');
    exec(`bash "${ec2Script}" stop >/dev/null 2>&1 &`, () => {});
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, message: 'EC2 stop command sent' }));
    return;
  }

  if (pathname === '/api/pac-rules') {
    const pacPath = path.join(ROOT_DIR, 'config', 'workstation.pac');
    let pacContent = '';
    if (fs.existsSync(pacPath)) {
      pacContent = fs.readFileSync(pacPath, 'utf8');
    }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      pacUrl: 'http://127.0.0.1:3129/workstation.pac',
      bypassHosts: [
        'localhost',
        '127.0.0.1',
        '::1',
        '*.local',
        '169.254.169.254',
        'host.docker.internal',
        '*.internal',
        '172.16.0.0/12 (Docker bridge networks)',
        '10.0.0.0/8 (VPC / Container subnets)',
        '192.168.0.0/16 (Local LAN subnets)'
      ],
      proxiedServices: [
        '*.amazonaws.com (DynamoDB, Cognito, S3, Secrets Manager, STS)',
        '*.nogap.ai (All API gateways & staging environments)',
        'External HTTPS and secure internet egress'
      ],
      pacContent
    }));
    return;
  }

  // Static File Serving
  let filePath = path.join(PUBLIC_DIR, pathname === '/' ? 'index.html' : pathname);
  if (!filePath.startsWith(PUBLIC_DIR)) {
    res.writeHead(403);
    return res.end('Forbidden');
  }

  fs.stat(filePath, (err, stats) => {
    if (err || !stats.isFile()) {
      filePath = path.join(PUBLIC_DIR, 'index.html');
    }

    const ext = path.extname(filePath).toLowerCase();
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';

    fs.readFile(filePath, (readErr, content) => {
      if (readErr) {
        res.writeHead(500);
        return res.end('Internal Server Error');
      }
      res.writeHead(200, { 'Content-Type': contentType });
      res.end(content);
    });
  });
});

server.listen(PORT, HOST, () => {
  console.log(`\n======================================================`);
  console.log(`⚡ NOGAP Proxy Command Center running at:`);
  console.log(`👉 http://${HOST}:${PORT}`);
  console.log(`======================================================\n`);
});
