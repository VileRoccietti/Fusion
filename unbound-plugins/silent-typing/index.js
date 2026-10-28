(() => {
    let unpatches = [];

    return {
        start(context) {
            console.log("[SilentTyping] Iniciando Silent Typing...");
            try {
                const metro = window.unbound?.metro;
                const patcher = window.unbound?.patcher;
                const toasts = window.unbound?.toasts;

                if (!metro) {
                    console.error("[SilentTyping] Metro no disponible.");
                    return;
                }

                // Buscar el módulo de typing en Metro
                const Typing = metro.findByProps("startTyping") || metro.findByProps("sendTyping");

                if (Typing) {
                    if (patcher && typeof patcher.instead === "function") {
                        if (typeof Typing.startTyping === "function") {
                            unpatches.push(patcher.instead(Typing, "startTyping", () => {
                                // Evento suprimido client-side: 0 llamadas de red
                            }));
                        }
                        if (typeof Typing.sendTyping === "function") {
                            unpatches.push(patcher.instead(Typing, "sendTyping", () => {
                                // Evento suprimido client-side
                            }));
                        }
                        if (typeof Typing.stopTyping === "function") {
                            unpatches.push(patcher.instead(Typing, "stopTyping", () => {
                                // Evento suprimido client-side
                            }));
                        }
                    } else {
                        // Fallback de reemplazo directo
                        const originalStart = Typing.startTyping;
                        Typing.startTyping = () => {};
                        unpatches.push(() => { Typing.startTyping = originalStart; });
                    }
                }

                if (toasts && typeof toasts.showToast === "function") {
                    toasts.showToast({ content: "🤫 Silent Typing activado (escritura invisible)" });
                }
                console.log("[SilentTyping] Silent Typing activado con éxito.");
            } catch (e) {
                console.error("[SilentTyping] Error al aplicar patch:", e);
            }
        },

        stop() {
            unpatches.forEach(u => {
                try { if (typeof u === "function") u(); } catch (_) {}
            });
            unpatches = [];
            const toasts = window.unbound?.toasts;
            if (toasts && typeof toasts.showToast === "function") {
                toasts.showToast({ content: "Silent Typing desactivado" });
            }
            console.log("[SilentTyping] Detenido.");
        }
    };
})()
