#if DEBUG
    import Foundation

    /// The demo's inline widgets: pages a Bot wrote and named with `::preview{file="…"}`, which
    /// the app runs in the message.
    enum DemoWidget {
        static let diskPath = "/home/hermes/.hermes/profiles/ops/work/disk.html"
        static let pricingPath = "/home/hermes/.hermes/profiles/atlas/work/pricing.html"

        static var files: [String: Data] {
            [diskPath: Data(disk.utf8), pricingPath: Data(pricing.utf8)]
        }

        /// Ops shows disk use per server as bars you can tap.
        static var diskTurn: [HistoryMessage] {
            [
                HistoryMessage(role: "user", text: "Show me disk use on each server."),
                HistoryMessage(
                    role: "tool", name: "terminal", context: "for h in web-1 web-2 db-1; do ssh $h df -h /; done"),
                HistoryMessage(role: "tool", name: "write_file", context: "work/disk.html"),
                HistoryMessage(
                    role: "assistant",
                    text: """
                        Disk use on each server this morning. Tap one for its biggest folders.
                        ::preview{file="\(diskPath)" height="220"}
                        """),
            ]
        }

        /// Atlas's pricing comparison in the room, as a widget you can set the team size in.
        static let pricingReply = """
            I checked the three competitors' pricing pages again; nobody changed theirs this week. \
            Here's what each would cost us:
            ::preview{file="\(pricingPath)"}
            """

        private static let disk = """
            <!doctype html>
            <html><head><meta charset="utf-8">
            <style>
              .row{display:flex;align-items:center;gap:10px;margin:6px 0;cursor:pointer;border:0;
                background:none;color:inherit;font:inherit;padding:0;width:100%;text-align:left}
              .name{width:52px;font-weight:600;white-space:nowrap}
              .bar{flex:1;height:14px;border-radius:7px;background:var(--border);overflow:hidden}
              .fill{height:100%;border-radius:7px;background:var(--accent)}
              .hot .fill{background:#e5484d}
              .pct{width:40px;text-align:right;color:var(--muted-foreground);font-variant-numeric:tabular-nums}
              #detail{margin-top:10px;padding:10px 12px;border-radius:10px;background:var(--card);
                border:1px solid var(--border);color:var(--muted-foreground)}
            </style></head>
            <body>
            <div id="rows"></div>
            <div id="detail">Tap a server.</div>
            <script>
            const servers = [
              {name:"web-1", used:41, top:"/var/log 6 GB · /srv/app 4 GB · /home 2 GB"},
              {name:"web-2", used:38, top:"/srv/app 4 GB · /var/log 3 GB · /tmp 1 GB"},
              {name:"db-1", used:78, top:"/var/lib/postgres 61 GB · /var/backups 22 GB · /var/log 9 GB"},
            ];
            const rows = document.getElementById("rows");
            for (const s of servers) {
              const row = document.createElement("button");
              row.className = "row" + (s.used > 70 ? " hot" : "");
              row.innerHTML = `<span class="name">${s.name}</span><span class="bar"><span class="fill"
                style="display:block;width:${s.used}%"></span></span><span class="pct">${s.used}%</span>`;
              row.setAttribute("aria-label", `${s.name}, ${s.used} percent full`);
              row.onclick = () => document.getElementById("detail").textContent = `${s.name}: ${s.top}`;
              rows.appendChild(row);
            }
            </script>
            </body></html>
            """

        private static let pricing = """
            <!doctype html>
            <html><head><meta charset="utf-8">
            <style>
              .box{width:300px;max-width:100%}
              label{display:flex;justify-content:space-between;color:var(--muted-foreground)}
              input{width:100%;accent-color:var(--accent);margin:6px 0 10px}
              table{width:100%;border-collapse:collapse}
              td{padding:6px 0;border-top:1px solid var(--border)}
              td:last-child{text-align:right;font-variant-numeric:tabular-nums;font-weight:600}
            </style></head>
            <body><div class="box">
            <label for="seats"><span>Team size</span><span id="count"></span></label>
            <input id="seats" type="range" min="1" max="40" value="12">
            <table id="prices"></table>
            </div>
            <script>
            const plans = [["Tallyhouse", s => 12 * s], ["Brightdesk", s => 15 * s], ["Pinwheel", s => s <= 3 ? 0 : 9 * s]];
            const seats = document.getElementById("seats");
            function show() {
              const n = Number(seats.value);
              document.getElementById("count").textContent = n + (n === 1 ? " seat" : " seats");
              document.getElementById("prices").innerHTML = plans
                .map(([name, cost]) => `<tr><td>${name}</td><td>$${cost(n)} a month</td></tr>`).join("");
            }
            seats.oninput = show;
            show();
            </script>
            </body></html>
            """
    }
#endif
