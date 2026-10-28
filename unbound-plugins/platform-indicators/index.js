let unpatch = () => {};

function start() {
    console.log("[PlatformIndicators] Iniciando indicadores...");
    try {
        const metro = window.unbound?.metro;
        if (!metro) return;
        // Presence data hook
    } catch (e) {
        console.error("[PlatformIndicators] Error:", e);
    }
}

function stop() {
    unpatch();
    unpatch = () => {};
}

export default { start, stop };
