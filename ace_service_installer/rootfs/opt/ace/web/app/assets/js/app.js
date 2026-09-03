import RFB from './../../novnc/core/rfb.js';


const installButton = document.getElementById('installButton');
const launchButton = document.getElementById('launchButton');
const copyButton = document.getElementById('copyButton');
const pasteButton = document.getElementById('pasteButton');

const logsButton = document.getElementById('logsButton');
const logsButtonText = document.getElementById('logsButtonText');

const clearLogsButton = document.getElementById('clearLogsButton');

const logsSection = document.getElementById('logsSection');
const logs = document.getElementById('logs');
const logsText = document.getElementById('logsText');
const statusDot = document.getElementById('statusDot');
const statusText = document.getElementById('statusText');

const runtimeText = document.getElementById('runtimeText');

const displayArea = document.getElementById('displayArea');
const display = document.getElementById('display');
const fullscreenButton = document.getElementById('fullscreenButton');

const displayMessage = document.querySelector('.display-placeholder');
const displayMessageText = displayMessage.querySelector('span');

const dropZone = document.getElementById('dropZone');
const fileInput = document.getElementById('fileInput');
const fileList = document.getElementById('fileList');

const toast = document.getElementById('toast');

let toastTimer;
let rfb = null;
let reconnectTimer = null;
let remoteClipboard = '';


// Keep the local mouse pointer visible while only the VNC display is fullscreen.
const fullscreenCursorStyle = document.createElement('style');
fullscreenCursorStyle.textContent = `
    #display.force-visible-cursor,
    #display.force-visible-cursor * {
        cursor: default !important;
    }
`;
document.head.appendChild(fullscreenCursorStyle);


function basePath() {
    return window.location.pathname.replace(/[^/]*$/, '');
}


function fitDisplay() {
    const areaTop = displayArea.getBoundingClientRect().top;
    const bottomGap = 12;
    const availableHeight = Math.max(120, window.innerHeight - areaTop - bottomGap - 8);
    display.style.setProperty('--display-max-height', `${Math.round(Math.min(800, availableHeight))}px`);
}


function getFullscreenElement() {
    return document.fullscreenElement || document.webkitFullscreenElement || null;
}


function showToast(message) {
    clearTimeout(toastTimer);
    toast.textContent = message;
    toast.classList.add('visible');
    toastTimer = setTimeout(() => toast.classList.remove('visible'), 2200);
}


function setStatus(label, state = 'ready') {
    statusText.textContent = label;
    statusDot.dataset.state = state;
}


async function toggleFullscreen() {
    try {
        if (getFullscreenElement()) {
            if (document.exitFullscreen) {
                await document.exitFullscreen();
            } else if (document.webkitExitFullscreen) {
                document.webkitExitFullscreen();
            } else {
                throw new Error('Fullscreen exit is not supported');
            }

            return;
        }

        if (display.requestFullscreen) {
            await display.requestFullscreen();
        } else if (display.webkitRequestFullscreen) {
            display.webkitRequestFullscreen();
        } else {
            throw new Error('Fullscreen is not supported by this browser');
        }
    } catch (err) {
        console.error('Fullscreen failed:', err);
        showToast(err.message || 'Unable to enter fullscreen');
    }
}


function handleFullscreenChange() {
    const isFullscreen = getFullscreenElement() === display;

    fullscreenButton.textContent = isFullscreen
        ? 'Exit fullscreen'
        : 'Fullscreen';

    display.classList.toggle('force-visible-cursor', isFullscreen);

    requestAnimationFrame(() => {
        fitDisplay();

        if (rfb) {
            rfb.showDotCursor = true;
            rfb.focus();
        }
    });
}


async function apiRequest(method, path, body = null, options = {}) {
    const config = {
        cache: 'no-store',
        ...options,
        method,
        headers: {
            'Content-Type': 'application/json',
            ...(options.headers || {}),
        },
    };

    if (body != null && method !== 'GET' && method !== 'HEAD') {
        config.body = JSON.stringify(body);
    }

    const response = await fetch(`./api/${path}`, config);

    const data = await response.json().catch(() => ({}));

    if (!response.ok) {
        throw new Error(data.error || `HTTP ${response.status}`);
    }

    return data;
}


function renderStatus(data) {
    const runtimeData = data.runtime || {};
    runtimeText.textContent = [
        runtimeData.build_version ? `v${runtimeData.build_version}` : 'unknown',
        runtimeData.arch || 'unknown',
        `Wine ${runtimeData.wine_version || 'unknown'}`,
    ].join(' · ');

    const state = data.state || 'ready';
    const label = data.status || 'Ready';

    setStatus(label, state);

    installButton.disabled = state === 'working' || state === 'running' || data.installed === true;
    launchButton.disabled = state === 'working' || state === 'running' || data.installed !== true;
}


async function refreshStatus() {
    try {
        const data = await apiRequest('GET', 'status');
        renderStatus(data);
    } catch (err) {
        setStatus('API unavailable', 'error');
        installButton.disabled = true;
        launchButton.disabled = true;
    }
}


async function refreshLogs() {
    try {
        const data = await apiRequest('GET', 'logs?lines=200');
        const atBottom = logs.scrollTop + logs.clientHeight >= logs.scrollHeight - 24;

        logsText.textContent = (data.lines || []).join('\n') || 'No logs yet...';

        // Restore bottom position.
        if (atBottom) {
            logs.scrollTop = logs.scrollHeight;
        }
    } catch (err) { }
}


async function runAction(name) {
    installButton.disabled = true;
    launchButton.disabled = true;

    try {
        await apiRequest('POST', `action/${name}`, {});
        await refreshStatus();
    } catch (err) {
        console.error(err);
        setStatus(err.message || 'Action failed', 'error');
        await refreshStatus();
    }
}


function connectVnc() {
    // Avoid multiple reconnect attempts running at once.
    clearTimeout(reconnectTimer);
    reconnectTimer = null;

    const scheme = window.location.protocol === 'https:' ? 'wss' : 'ws';
    const wsUrl = `${scheme}://${window.location.host}${basePath()}websockify`;

    displayMessage.hidden = false;
    displayMessageText.textContent = 'Connecting…';

    try {
        const connection = new RFB(display, wsUrl, {
            shared: true,
        });

        rfb = connection;

        connection.scaleViewport = true;
        connection.resizeSession = false;
        connection.showDotCursor = true;

        connection.addEventListener('connect', () => {
            // Ignore events from an old RFB instance.
            if (rfb !== connection) {
                return;
            }

            displayMessage.hidden = true;
        });

        connection.addEventListener('disconnect', () => {
            rfb = null;

            displayMessage.hidden = false;
            displayMessageText.textContent =
                'Display disconnected. Reconnecting…';

            reconnectTimer = setTimeout(connectVnc, 1800);
        });

        connection.addEventListener('credentialsrequired', () => {
            connection.sendCredentials({
                password: '',
            });
        });

        rfb.addEventListener('clipboard', async (event) => {
            remoteClipboard = event.detail.text;

            try {
                await navigator.clipboard.writeText(remoteClipboard);
                showToast('Session clipboard copied');
            } catch {
                showToast('Clipboard access was blocked by the browser');
            }
        });
    } catch (err) {
        console.error('VNC connection failed:', err);

        rfb = null;

        displayMessage.hidden = false;
        displayMessageText.textContent =
            'Unable to connect. Reconnecting…';

        reconnectTimer = setTimeout(() => {
            connectVnc();
        }, 1800);
    }
}


function pasteIntoSession(text) {
    if (!rfb || !text) {
        return;
    }

    // Replace the session clipboard with the browser clipboard.
    remoteClipboard = text;
    rfb.clipboardPasteFrom(text);

    // Put keyboard focus back on the VNC session.
    rfb.focus();

    // Send Ctrl+V to the remote session.
    rfb.sendKey(0xffe3, 'ControlLeft', true);
    rfb.sendKey(0x0076, 'KeyV', true);
    rfb.sendKey(0x0076, 'KeyV', false);
    rfb.sendKey(0xffe3, 'ControlLeft', false);
}


async function uploadFiles(files) {
    const selectedFiles = [...files];

    if (!selectedFiles.length) {
        return;
    }

    fileList.textContent = '';

    const body = new FormData();

    selectedFiles.forEach((file) => {
        body.append('files', file);

        const item = document.createElement('div');
        const name = document.createElement('span');
        const size = document.createElement('span');

        item.className = 'file-item';
        name.textContent = file.name;
        size.textContent = `${Math.ceil(file.size / 1024)} KB`;

        item.append(name, size);
        fileList.append(item);
    });

    try {
        const response = await fetch('./api/files', {
            method: 'POST',
            body,
        });

        const data = await response.json().catch(() => ({}));

        if (!response.ok) {
            throw new Error(data.error || `HTTP ${response.status}`);
        }

        showToast(`${selectedFiles.length} file${selectedFiles.length === 1 ? '' : 's'} uploaded`);
    } catch (err) {
        console.error(err);
        showToast(err.message || 'File upload failed');
    }
}


installButton.addEventListener('click', () => runAction('install'));
launchButton.addEventListener('click', () => runAction('launch'));

fullscreenButton.addEventListener('click', toggleFullscreen);

document.addEventListener('fullscreenchange', handleFullscreenChange);
document.addEventListener('webkitfullscreenchange', handleFullscreenChange);

logsButton.addEventListener('click', () => {
    const isHidden = logsSection.classList.toggle('hidden');
    logsButtonText.textContent = isHidden ? 'Show logs' : 'Hide logs';
    requestAnimationFrame(fitDisplay);
});

clearLogsButton.addEventListener('click', async () => {
    try {
        await apiRequest('DELETE', 'logs');
        logsText.textContent = '';
    } catch (err) {
        console.error(err);
    }
});

copyButton.addEventListener('click', async () => {
    if (!remoteClipboard) {
        showToast('Session clipboard is empty');
        return;
    }

    try {
        await navigator.clipboard.writeText(remoteClipboard);
        showToast('Session clipboard copied');
    } catch {
        showToast('Clipboard access was blocked by the browser');
    }
});

pasteButton.addEventListener('click', async () => {
    try {
        const text = await navigator.clipboard.readText();

        if (!text) {
            showToast('Clipboard is empty');
            return;
        }

        pasteIntoSession(text);
        showToast('Clipboard pasted into session');
    } catch (err) {
        console.error(err);
        showToast('Clipboard access was blocked by the browser');
    }
});

document.addEventListener('keydown', async (event) => {
    const isPaste =
        (event.ctrlKey || event.metaKey) &&
        event.key.toLowerCase() === 'v';

    if (!isPaste) {
        return;
    }

    // Stop noVNC/browser from handling Ctrl+V first.
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();

    if (!rfb) {
        return;
    }

    try {
        const text = await navigator.clipboard.readText();

        if (!text) {
            showToast('Clipboard is empty');
            return;
        }

        pasteIntoSession(text);
        showToast('Clipboard pasted into session');
    } catch (err) {
        console.error(err);
        showToast('Clipboard access was blocked by the browser');
    }
}, true);

dropZone.addEventListener('click', () => {
    fileInput.click();
});

fileInput.addEventListener('change', () => {
    uploadFiles(fileInput.files);
    fileInput.value = '';
});

dropZone.addEventListener('dragover', (event) => {
    event.preventDefault();
    dropZone.classList.add('dragging');
});

dropZone.addEventListener('dragleave', () => {
    dropZone.classList.remove('dragging');
});

dropZone.addEventListener('drop', (event) => {
    event.preventDefault();
    dropZone.classList.remove('dragging');
    uploadFiles(event.dataTransfer.files);
});

window.addEventListener('resize', fitDisplay);

fitDisplay();
connectVnc();
refreshStatus();
refreshLogs();

async function pollStatus() {
    while (true) {
        await refreshStatus();
        await new Promise(resolve => setTimeout(resolve, 900));
    }
}

async function pollLogs() {
    while (true) {
        await refreshLogs();
        await new Promise(resolve => setTimeout(resolve, 1000));
    }
}

fitDisplay();
connectVnc();

pollStatus();
pollLogs();