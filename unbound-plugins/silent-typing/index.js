let unpatch = () => {};

function start() {
    console.log("[SilentTyping] Activado.");
    try {
        const metro = window.unbound?.metro;
        if (!metro) return;
        const typing = metro.findByProps("startTyping", "sendTyping") || metro.findByProps("startTyping");
        if (typing && typing.startTyping) {
            const originalStart = typing.startTyping;
            const originalSend = typing.sendTyping;
            typing.startTyping = () => {};
            if (typing.sendTyping) typing.sendTyping = () => {};
            unpatch = () => {
                typing.startTyping = originalStart;
                if (originalSend) typing.sendTyping = originalSend;
            };
        }
    } catch (e) {
        console.error("[SilentTyping] Error al aplicar patch:", e);
    }
}

function stop() {
    unpatch();
    unpatch = () => {};
}

export default { start, stop };
