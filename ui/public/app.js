/**
 * NoGap Proxy - Minimal Workflow Controller (Stitch Inspired)
 * Focuses on the 3 core developer steps:
 * 1. Start Proxy Egress
 * 2. Start Local Backend & Frontend
 * 3. Launch Chrome with Proxy Tab
 */

// DOM Elements
const el = {
  navStatusDot: document.getElementById('navStatusDot'),
  navStatusLabel: document.getElementById('navStatusLabel'),
  navEgressIp: document.getElementById('navEgressIp'),
  stepCard1: document.getElementById('stepCard1'),
  stepCard2: document.getElementById('stepCard2'),
  stepCard3: document.getElementById('stepCard3'),
  step1StatusPill: document.getElementById('step1StatusPill'),
  step1StatusText: document.getElementById('step1StatusText'),
  detailForwarderPort: document.getElementById('detailForwarderPort'),
  detailUpstream: document.getElementById('detailUpstream'),
  detailLatency: document.getElementById('detailLatency'),
  btnToggleProxy: document.getElementById('btnToggleProxy'),
  btnToggleProxyText: document.getElementById('btnToggleProxyText'),
  btnStopProxy: document.getElementById('btnStopProxy'),
  btnTestEgress: document.getElementById('btnTestEgress'),
  // EC2 Power Card
  ec2StateBadge: document.getElementById('ec2StateBadge'),
  ec2StateText: document.getElementById('ec2StateText'),
  btnStartEc2: document.getElementById('btnStartEc2'),
  btnStopEc2: document.getElementById('btnStopEc2'),
  ec2Notice: document.getElementById('ec2Notice'),
  // Step 2
  port4000Card: document.getElementById('port4000Card'),
  port4000Badge: document.getElementById('port4000Badge'),
  port4000Text: document.getElementById('port4000Text'),
  port3000Card: document.getElementById('port3000Card'),
  port3000Badge: document.getElementById('port3000Badge'),
  port3000Text: document.getElementById('port3000Text'),
  btnCopyDev: document.getElementById('btnCopyDev'),
  // Step 3
  btnLaunchChrome: document.getElementById('btnLaunchChrome'),
  chromeStatusNotice: document.getElementById('chromeStatusNotice'),
  // Drawer
  recentLogCount: document.getElementById('recentLogCount'),
  miniLogTableBody: document.getElementById('miniLogTableBody'),
  toastContainer: document.getElementById('toastContainer')
};

function showToast(msg, type = 'success') {
  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.innerHTML = `<span>${type === 'success' ? '⚡' : '⚠️'}</span> <span>${msg}</span>`;
  el.toastContainer.appendChild(toast);
  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transition = 'opacity 0.3s';
    setTimeout(() => toast.remove(), 300);
  }, 3000);
}

// -------------------------------------------------------------
// Status Polling (Forwarder & Ports)
// -------------------------------------------------------------
async function updateStatus() {
  try {
    const res = await fetch('/api/status');
    const data = await res.json();

    // 1. Forwarder Health
    if (data.forwarderRunning) {
      el.navStatusDot.className = 'pulse-dot active';
      el.navStatusLabel.textContent = 'PROXY ACTIVE';
      el.navEgressIp.textContent = data.currentEgressIp || '52.6.50.56';

      el.step1StatusPill.className = 'status-pill-minimal online';
      el.step1StatusText.textContent = `Egress: ${data.currentEgressIp || '52.6.50.56'} (Protected)`;
      el.btnToggleProxyText.textContent = 'Restart Proxy';
      el.stepCard1.classList.add('active-step');
    } else {
      el.navStatusDot.className = 'pulse-dot offline';
      el.navStatusLabel.textContent = 'PROXY STOPPED';
      el.navEgressIp.textContent = 'Offline';

      el.step1StatusPill.className = 'status-pill-minimal offline';
      el.step1StatusText.textContent = 'Forwarder Stopped';
      el.btnToggleProxyText.textContent = 'Start Proxy';
      el.stepCard1.classList.remove('active-step');
    }

    if (data.upstreamHost) {
      el.detailUpstream.textContent = `${data.upstreamHost}:${data.upstreamPort || 443}`;
    }

    // 2. Port 4000: Backend API Detection
    if (data.port4000Ready) {
      el.port4000Badge.className = 'port-badge ready';
      el.port4000Text.textContent = 'READY (Listening)';
      el.port4000Card.style.borderColor = 'rgba(16, 185, 129, 0.4)';
    } else {
      el.port4000Badge.className = 'port-badge waiting';
      el.port4000Text.textContent = 'Waiting to start';
      el.port4000Card.style.borderColor = 'var(--border-subtle)';
    }

    // 3. Port 3000: Frontend Web Detection
    if (data.port3000Ready) {
      el.port3000Badge.className = 'port-badge ready';
      el.port3000Text.textContent = 'READY (Listening)';
      el.port3000Card.style.borderColor = 'rgba(16, 185, 129, 0.4)';
    } else {
      el.port3000Badge.className = 'port-badge waiting';
      el.port3000Text.textContent = 'Waiting to start';
      el.port3000Card.style.borderColor = 'var(--border-subtle)';
    }

    // Step 2 & 3 activation styling
    if (data.port3000Ready || data.port4000Ready) {
      el.stepCard2.classList.add('active-step');
      el.stepCard3.classList.add('active-step');
    }
  } catch (err) {
    console.error('Status poll error:', err);
  }
}

// -------------------------------------------------------------
// Action Handlers
// -------------------------------------------------------------
// Step 1: Start / Restart Proxy
el.btnToggleProxy.addEventListener('click', async () => {
  const orig = el.btnToggleProxy.innerHTML;
  el.btnToggleProxy.innerHTML = `<span class="spinner"></span> <span>Starting...</span>`;
  el.btnToggleProxy.disabled = true;

  try {
    const res = await fetch('/api/action/restart', { method: 'POST' });
    const data = await res.json();
    if (data.success) {
      showToast('Proxy forwarder started and egress verified', 'success');
      await updateStatus();
    } else {
      showToast('Proxy start encountered an error', 'error');
    }
  } catch (err) {
    showToast(`Error: ${err.message}`, 'error');
  } finally {
    el.btnToggleProxy.innerHTML = orig;
    el.btnToggleProxy.disabled = false;
  }
});

// Step 1: Stop Proxy
el.btnStopProxy.addEventListener('click', async () => {
  const orig = el.btnStopProxy.innerHTML;
  el.btnStopProxy.innerHTML = `<span class="spinner"></span>`;
  el.btnStopProxy.disabled = true;

  try {
    const res = await fetch('/api/action/stop', { method: 'POST' });
    const data = await res.json();
    if (data.success) {
      showToast('Proxy forwarder stopped', 'success');
      await updateStatus();
    }
  } catch (err) {
    showToast(`Error: ${err.message}`, 'error');
  } finally {
    el.btnStopProxy.innerHTML = orig;
    el.btnStopProxy.disabled = false;
  }
});

// Step 1: Verify IP
el.btnTestEgress.addEventListener('click', async () => {
  const orig = el.btnTestEgress.innerHTML;
  el.btnTestEgress.innerHTML = `<span class="spinner"></span> <span>Checking...</span>`;
  el.btnTestEgress.disabled = true;

  try {
    const res = await fetch('/api/action/test-egress', { method: 'POST' });
    const data = await res.json();
    if (data.success) {
      el.detailLatency.textContent = `${data.latencyMs} ms RTT`;
      el.navEgressIp.textContent = data.egressIp;
      showToast(`Verified Egress: ${data.egressIp} (${data.latencyMs}ms)`, 'success');
    } else {
      showToast(`Egress test failed: ${data.error}`, 'error');
    }
  } catch (err) {
    showToast(`Error: ${err.message}`, 'error');
  } finally {
    el.btnTestEgress.innerHTML = orig;
    el.btnTestEgress.disabled = false;
  }
});

// Step 2: Copy command
el.btnCopyDev.addEventListener('click', () => {
  navigator.clipboard.writeText('npm run dev').then(() => {
    el.btnCopyDev.textContent = 'Copied!';
    setTimeout(() => { el.btnCopyDev.textContent = 'Copy'; }, 2000);
    showToast('Copied "npm run dev" to clipboard');
  });
});

// Step 3: Launch Isolated Chrome
el.btnLaunchChrome.addEventListener('click', async () => {
  const orig = el.btnLaunchChrome.innerHTML;
  el.btnLaunchChrome.innerHTML = `<span class="spinner"></span> <span>Launching Chrome...</span>`;
  el.btnLaunchChrome.disabled = true;

  try {
    const res = await fetch('/api/action/launch-chrome', { method: 'POST' });
    const data = await res.json();

    if (data.success) {
      el.chromeStatusNotice.classList.remove('hidden');
      showToast('Chrome launched via proxy to http://localhost:3000', 'success');
    } else {
      showToast('Could not launch Chrome automatically', 'error');
    }
  } catch (err) {
    showToast(`Launch error: ${err.message}`, 'error');
  } finally {
    el.btnLaunchChrome.innerHTML = orig;
    el.btnLaunchChrome.disabled = false;
  }
});

// -------------------------------------------------------------
// Optional Mini-Logs
// -------------------------------------------------------------
async function updateMiniLogs() {
  try {
    const res = await fetch('/api/logs?limit=8');
    const data = await res.json();
    const logs = data.logs || [];
    el.recentLogCount.textContent = logs.length;

    if (logs.length === 0) return;

    el.miniLogTableBody.innerHTML = logs.map(l => `
      <tr>
        <td style="color: ${l.httpCode === 200 ? 'var(--emerald)' : 'var(--red)'}; font-weight: 600;">
          ${l.statusCodeStr}
        </td>
        <td class="text-muted">${l.displayTime}</td>
        <td style="color: #FFFFFF;">${l.host}</td>
        <td>${(l.durationMs / 1000).toFixed(1)}s</td>
        <td class="text-muted">${(l.bytes / 1024).toFixed(1)} KB</td>
      </tr>
    `).join('');
  } catch (_) {}
}

// -------------------------------------------------------------
// EC2 Instance Power Control
// -------------------------------------------------------------
async function updateEc2Status() {
  try {
    const res = await fetch('/api/ec2/status');
    const data = await res.json();
    const state = (data.state || 'unknown').toLowerCase();

    if (state === 'running') {
      el.ec2StateBadge.className = 'ec2-badge running';
      el.ec2StateText.textContent = 'RUNNING';
      el.btnStartEc2.disabled = true;
      el.btnStopEc2.disabled = false;
      el.ec2Notice.classList.add('hidden');
    } else if (state === 'stopped') {
      el.ec2StateBadge.className = 'ec2-badge stopped';
      el.ec2StateText.textContent = 'STOPPED';
      el.btnStartEc2.disabled = false;
      el.btnStopEc2.disabled = true;
      el.ec2Notice.classList.add('hidden');
    } else if (state === 'pending' || state === 'stopping') {
      el.ec2StateBadge.className = 'ec2-badge transitioning';
      el.ec2StateText.textContent = state.toUpperCase() + '...';
      el.btnStartEc2.disabled = true;
      el.btnStopEc2.disabled = true;
      el.ec2Notice.textContent = `EC2 state is transitioning (${state})...`;
      el.ec2Notice.classList.remove('hidden');
    }
  } catch (err) {
    console.error('EC2 status poll error:', err);
  }
}

el.btnStartEc2.addEventListener('click', async () => {
  el.btnStartEc2.disabled = true;
  el.ec2Notice.textContent = 'Sending start signal to AWS...';
  el.ec2Notice.classList.remove('hidden');
  showToast('Initiating EC2 proxy boot sequence...', 'success');

  try {
    await fetch('/api/ec2/start', { method: 'POST' });
    setTimeout(updateEc2Status, 2000);
  } catch (err) {
    showToast(`Error: ${err.message}`, 'error');
  }
});

el.btnStopEc2.addEventListener('click', async () => {
  if (!confirm('Are you sure you want to stop the EC2 instance? This will stop proxy egress.')) {
    return;
  }

  el.btnStopEc2.disabled = true;
  el.ec2Notice.textContent = 'Sending stop signal to AWS...';
  el.ec2Notice.classList.remove('hidden');
  showToast('Initiating EC2 instance shutdown...', 'success');

  try {
    await fetch('/api/ec2/stop', { method: 'POST' });
    setTimeout(updateEc2Status, 2000);
  } catch (err) {
    showToast(`Error: ${err.message}`, 'error');
  }
});

// -------------------------------------------------------------
// Init & Loops
// -------------------------------------------------------------
window.addEventListener('DOMContentLoaded', () => {
  updateStatus();
  updateEc2Status();
  updateMiniLogs();

  // Fast polling for local dev ports and EC2 status
  setInterval(updateStatus, 2500);
  setInterval(updateEc2Status, 4000);
  setInterval(updateMiniLogs, 6000);
});
