# HermesKit: known issues

## Implemented today: source-supported limitations

Implemented mitigation: gateway approval requests can fail immediately if client capabilities are missing → GatewayConnector explicitly calls client.capabilities with server_requests true after ready → retain this handshake → keep protocol tests around approval flows. This is source-backed mitigation, not a fresh live-gateway check.
