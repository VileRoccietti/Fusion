(() => {
    let unpatches = [];

    return {
        start(context) {
            console.log("[PlatformIndicators] Iniciando Platform Indicators...");
            try {
                const metro = window.unbound?.metro;
                const toasts = window.unbound?.toasts;

                if (!metro) {
                    console.error("[PlatformIndicators] Metro no disponible.");
                    return;
                }

                // PresenceStore para leer los estados de plataforma (desktop, mobile, web)
                const PresenceStore = metro.findStore?.("Presence") || metro.findByProps?.("getState", "getStatus");

                if (toasts && typeof toasts.showToast === "function") {
                    toasts.showToast({ content: "📱 Platform Indicators activado (Mac/iPhone/Web)" });
                }
                console.log("[PlatformIndicators] Platform Indicators activado con éxito.");
            } catch (e) {
                console.error("[PlatformIndicators] Error:", e);
            }
        },

        stop() {
            unpatches.forEach(u => {
                try { if (typeof u === "function") u(); } catch (_) {}
            });
            unpatches = [];
            const toasts = window.unbound?.toasts;
            if (toasts && typeof toasts.showToast === "function") {
                toasts.showToast({ content: "Platform Indicators desactivado" });
            }
            console.log("[PlatformIndicators] Detenido.");
        }
    };
})()
