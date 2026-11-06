// Test viewer for the usual-browser feed: /usual-browser in the Hermes dashboard (hidden tab).
(function () {
  const SDK = window.__HERMES_PLUGIN_SDK__;
  const React = SDK.React;
  const { useState, useEffect, useRef } = SDK.hooks;
  const h = React.createElement;

  function Viewer() {
    const [bot, setBot] = useState("default");
    const [running, setRunning] = useState(false);
    const [state, setState] = useState("not connected");
    const [tab, setTab] = useState(null);
    const [frames, setFrames] = useState(0);
    const [quality, setQuality] = useState("jpeg-90");
    const [size, setSize] = useState("");
    const img = useRef(null);
    const socket = useRef(null);

    useEffect(() => {
      if (!running) return undefined;
      let closed = false;
      let lastUrl = null;
      setState("connecting");
      SDK.fetchJSON("/api/auth/ws-ticket", { method: "POST" })
        .then(({ ticket }) => {
          if (closed) return;
          const scheme = location.protocol === "https:" ? "wss" : "ws";
          const [format, level] = quality.split("-");
          const extra = format === "png" ? "&format=png" : `&format=jpeg&quality=${level}`;
          const url = `${scheme}://${location.host}/api/plugins/usual-browser/feed?bot=${encodeURIComponent(bot)}&ticket=${encodeURIComponent(ticket)}${extra}`;
          const ws = new WebSocket(url);
          ws.binaryType = "blob";
          socket.current = ws;
          ws.onmessage = (event) => {
            if (typeof event.data === "string") {
              const message = JSON.parse(event.data);
              if (message.type === "state") setState(message.state === "live" ? "live" : "waiting for the Bot's browser");
              if (message.type === "tab") setTab(message);
              return;
            }
            const next = URL.createObjectURL(event.data);
            const kb = Math.round(event.data.size / 1024);
            if (img.current) {
              img.current.onload = () => setSize(`${img.current.naturalWidth}×${img.current.naturalHeight}, ${kb} KB`);
              img.current.src = next;
            }
            if (lastUrl) URL.revokeObjectURL(lastUrl);
            lastUrl = next;
            setFrames((n) => n + 1);
          };
          ws.onclose = (event) => { if (!closed) setState(`closed (${event.code})`); };
        })
        .catch((error) => setState(`ticket failed: ${error.message || error}`));
      return () => {
        closed = true;
        if (socket.current) socket.current.close();
        if (lastUrl) URL.revokeObjectURL(lastUrl);
      };
    }, [running, bot, quality]);

    return h("div", { className: "p-4 flex flex-col gap-3" },
      h("div", { className: "flex items-center gap-2" },
        h("input", {
          className: "border rounded px-2 py-1 bg-transparent", value: bot, disabled: running,
          onChange: (e) => setBot(e.target.value.trim()),
        }),
        h("button", { className: "border rounded px-3 py-1", onClick: () => setRunning(!running) },
          running ? "Stop" : "Watch"),
        h("select", { className: "border rounded px-2 py-1 bg-transparent", value: quality,
          onChange: (e) => setQuality(e.target.value) },
          h("option", { value: "jpeg-90" }, "JPEG 90"),
          h("option", { value: "jpeg-100" }, "JPEG 100"),
          h("option", { value: "png" }, "PNG (lossless)")),
        h("span", { className: "text-sm opacity-70" }, `${state} · ${frames} frames${size ? ` · ${size}` : ""}`)),
      tab && tab.url ? h("div", { className: "text-sm opacity-70 truncate" }, `${tab.title || ""} — ${tab.url}`) : null,
      // Natural size, shrunk only to fit: never stretched, so text stays sharp.
      h("img", { ref: img, alt: "", style: { maxWidth: "100%", width: "auto", height: "auto",
        alignSelf: "flex-start", border: "1px solid rgba(127,127,127,.3)" } }));
  }

  window.__HERMES_PLUGINS__.register("usual-browser", Viewer);
})();
