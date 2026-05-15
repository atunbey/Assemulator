// EmulatorJS JS Interop Module
// Called from EmulatorPlayer.razor via IJSRuntime

const EJS_CDN = 'https://cdn.emulatorjs.org/latest/data/';
let _loaderScript = null;

export function initEmulator(core, romUrl, biosUrl) {
    const container = document.getElementById('game');
    if (!container) return;

    // Set global EJS config vars before loader runs
    window.EJS_player = '#game';
    window.EJS_core = core;
    window.EJS_gameUrl = romUrl;
    window.EJS_pathtodata = EJS_CDN;

    if (biosUrl) {
        window.EJS_biosUrl = biosUrl;
    }

    // Keyboard/gamepad defaults
    window.EJS_defaultOptions = {
        'save-state-slot': 1,
        'rewind-enabled': false,
    };

    // Load EmulatorJS loader
    _loaderScript = document.createElement('script');
    _loaderScript.src = EJS_CDN + 'loader.js';
    document.body.appendChild(_loaderScript);
}

export function destroyEmulator() {
    // Remove loader script
    if (_loaderScript) {
        _loaderScript.remove();
        _loaderScript = null;
    }

    // Clear EJS globals
    const ejsGlobals = Object.keys(window).filter(k => k.startsWith('EJS_'));
    ejsGlobals.forEach(k => { try { delete window[k]; } catch (_) {} });

    // Clear the game container
    const container = document.getElementById('game');
    if (container) container.innerHTML = '';
}
