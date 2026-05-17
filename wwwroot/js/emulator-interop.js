// EmulatorJS JS Interop Module
// Called from EmulatorPlayer.razor via IJSRuntime

const EJS_CDN = 'https://cdn.emulatorjs.org/stable/data/';
let _loaderScript = null;
let _audioUnlockBound = false;
let _navigationInProgress = false;

function normalizeReturnUrl(returnUrl) {
    if (!returnUrl || typeof returnUrl !== 'string') return '';

    const trimmed = returnUrl.trim();
    if (!trimmed.startsWith('/')) return '';
    if (trimmed.startsWith('//')) return '';

    return trimmed;
}

function getEjsDataPath() {
    const host = window.location.hostname;
    if (host === 'localhost' || host === '127.0.0.1') {
        return '/emulatorjs/';
    }

    return EJS_CDN;
}

function withCacheBuster(url) {
    if (!url) return url;

    // Keep production caching behavior intact; force-refresh only for local dev/testing.
    if (window.location.hostname !== 'localhost') return url;

    const sep = url.includes('?') ? '&' : '?';
    return `${url}${sep}cb=${Date.now()}`;
}

function bindAudioUnlock() {
    if (_audioUnlockBound) return;
    _audioUnlockBound = true;

    const unlock = async () => {
        try {
            const Ctx = window.AudioContext || window.webkitAudioContext;
            if (!Ctx) return;

            // Resume a context during a trusted gesture to satisfy autoplay policies.
            const ctx = new Ctx();
            if (ctx.state === 'suspended') {
                await ctx.resume();
            }

            // Create and immediately stop a silent source to fully unlock audio routing.
            const gain = ctx.createGain();
            gain.gain.value = 0;
            gain.connect(ctx.destination);

            const osc = ctx.createOscillator();
            osc.connect(gain);
            osc.start();
            osc.stop(ctx.currentTime + 0.01);

            setTimeout(() => {
                try { ctx.close(); } catch (_) {}
            }, 50);
        } catch (_) {
            // Best effort only.
        }
    };

    const onGesture = () => {
        unlock();
        document.removeEventListener('pointerdown', onGesture);
        document.removeEventListener('keydown', onGesture);
    };

    document.addEventListener('pointerdown', onGesture, { passive: true });
    document.addEventListener('keydown', onGesture, { passive: true });
}

export function initEmulator(core, romUrl, biosUrl, romsetName, requiredRomsets, returnUrl) {
    const container = document.getElementById('game');
    if (!container) return;

    const ejsDataPath = getEjsDataPath();

    bindAudioUnlock();

    // Always reset launch-specific globals so previous game settings cannot leak.
    delete window.EJS_gameName;
    delete window.EJS_biosUrl;
    delete window.EJS_gameParentUrl;
    delete window.EJS_externalFiles;

    const safeReturnUrl = normalizeReturnUrl(returnUrl);

    // Set global EJS config vars before loader runs
    window.EJS_player = '#game';
    window.EJS_core = core;
    window.EJS_gameUrl = withCacheBuster(romUrl);
    window.EJS_pathtodata = ejsDataPath;
    window.EJS_onExit = () => {
        if (_navigationInProgress) return;
        _navigationInProgress = true;

        // Ensure emulator/audio is torn down before routing away.
        destroyEmulator();

        if (safeReturnUrl) {
            window.location.assign(safeReturnUrl);
            return;
        }

        if (window.history.length > 1) {
            window.history.back();
            return;
        }

        window.location.assign('/');
    };

    // Only FBNeo should receive EJS_gameName. For MAME cores this can trigger load-content/menu flows.
    if (core === 'fbneo' && romsetName) {
        window.EJS_gameName = romsetName;
    }

    if (biosUrl) {
        window.EJS_biosUrl = biosUrl;
    }

    const isArcadeZipCore = core === 'fbneo' || core === 'mame2003' || core === 'mame2003_plus';
    if (isArcadeZipCore) {
        // Keep stock EmulatorJS loading behavior for arcade sets unless dependency metadata is provided.
        const slash = romUrl.lastIndexOf('/');
        const baseDir = slash >= 0 ? romUrl.slice(0, slash + 1) : '';

        if (Array.isArray(requiredRomsets) && requiredRomsets.length > 0 && baseDir) {
            window.EJS_gameParentUrl = baseDir;
            const extraFiles = {};
            for (const name of requiredRomsets) {
                if (!name || typeof name !== 'string') continue;
                const trimmed = name.trim();
                if (!trimmed) continue;
                const depUrl = /^https?:\/\//i.test(trimmed) || trimmed.startsWith('/')
                    ? trimmed
                    : (baseDir + encodeURIComponent(trimmed));
                extraFiles[trimmed] = withCacheBuster(depUrl);
            }
            if (Object.keys(extraFiles).length > 0) {
                window.EJS_externalFiles = extraFiles;
            }
        }
    }

    // Keyboard/gamepad defaults
    window.EJS_defaultOptions = {
        'save-state-slot': 1,
        'rewind-enabled': false,
        'volume': 1,
        'mute': false,
    };

    // Load EmulatorJS loader
    _loaderScript = document.createElement('script');
    _loaderScript.src = withCacheBuster(ejsDataPath + 'loader.js');
    document.body.appendChild(_loaderScript);
}

export function downloadFile(filename, content, mimeType) {
    const blob = new Blob([content], { type: mimeType });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
}

export function destroyEmulator() {
    // Try emulator API shutdown hooks first when present.
    const emulator = window.EJS_emulator;
    if (emulator && typeof emulator === 'object') {
        try {
            if (typeof emulator.exit === 'function') emulator.exit();
        } catch (_) {}

        try {
            if (typeof emulator.destroy === 'function') emulator.destroy();
        } catch (_) {}

        try {
            if (typeof emulator.stop === 'function') emulator.stop();
        } catch (_) {}

        try {
            if (typeof emulator.pause === 'function') emulator.pause();
        } catch (_) {}

        try {
            const toggleMainLoop = emulator.gameManager?.functions?.toggleMainLoop;
            if (typeof toggleMainLoop === 'function') {
                // The generated WASM wrapper behaves like a call-through; invoking it
                // here is the most direct way to stop the core's main loop.
                toggleMainLoop();
            }
        } catch (_) {}

        try {
            if (emulator.gameManager?.clearEJSResetTimer) {
                emulator.gameManager.clearEJSResetTimer();
            }
        } catch (_) {}

        try {
            if (emulator.Module && typeof emulator.Module._toggleMainLoop === 'function') {
                emulator.Module._toggleMainLoop();
            }
        } catch (_) {}

        try {
            emulator.started = false;
            emulator.paused = true;
            emulator.failedToStart = true;
        } catch (_) {}
    }

    // Remove loader script
    if (_loaderScript) {
        _loaderScript.remove();
        _loaderScript = null;
    }

    // Stop any media elements created by the emulator runtime.
    try {
        document.querySelectorAll('audio,video').forEach((media) => {
            try {
                media.pause();
                media.currentTime = 0;
                media.removeAttribute('src');
                if (typeof media.load === 'function') media.load();
            } catch (_) {}
        });
    } catch (_) {
        // Best effort only.
    }

    // Clear EJS globals
    const ejsGlobals = Object.keys(window).filter(k => k.startsWith('EJS_'));
    ejsGlobals.forEach(k => { try { delete window[k]; } catch (_) {} });

    try {
        if ('EJS_emulator' in window) {
            window.EJS_emulator = null;
        }
    } catch (_) {}

    // Clear the game container
    const container = document.getElementById('game');
    if (container) container.innerHTML = '';

    _navigationInProgress = false;
}
