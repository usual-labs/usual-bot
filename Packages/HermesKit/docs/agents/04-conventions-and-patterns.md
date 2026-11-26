# HermesKit: conventions and ownership

## Implemented today

Transport and HTTP interfaces permit test fakes. Keep gateway wire protocol in Gateway/Transport, auth in Auth, state orchestration in Stores and domain behavior in Chat/Rooms/Routines. Cache data can be purged; it is not the gateway source of truth.

Preserve the source patterns at the anchors below. Treat placeholder/sample data as such; do not convert it to a product guarantee. Keep secrets out of client bundles and documentation.

`Trace` (`Diagnostics/Trace.swift`) logs every field public, so its callers pass only durations,
sizes, counts, method names, random IDs, `Trace.tag`s and `Trace.reason` codes. Never words, names,
paths, a gateway's error message or `AppModel.describe`, which can quote the gateway. `Trace.tag`
must stay the same hash as the plugin's `push.tag` (`tests/test_push_trace.py` and `TraceTests` pin
it to one value): it's how one chat is matched across devices and the gateway's log.

## Maintenance rule

Changes belong in their existing owning module. Add a top-level abstraction only when the current structure cannot clearly own the behavior; update this KB in the same turn.

Source anchors: `Package.swift`, `Sources/HermesKit/Stores/AppModel.swift`, `Sources/HermesKit/Stores/OfflineCache.swift`, `Sources/HermesKit/Auth/TokenStore.swift`, `Sources/HermesKit/Transport/GatewayConnection.swift`, `Sources/HermesKit/Transport/JSONRPCChannel.swift`, `Sources/HermesKit/Gateway/GatewayAddress.swift`.
