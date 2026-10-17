# Upstream PRs (Moonfin-Client/Moonfin-Core)

Two clean branches, based on `upstream/main` and free of anything OB Max. They are
cherry-picked as-is into `obmax/main`, so once merged upstream the rebase drops them.

Open them yourself from GitHub (push the branch to your fork first).

---

## `upstream-pr/ws-port0`

**Title:** Fix WebSocket connections to port 0 in the client-certificate connection factory

**Description:**

`dart:io` hands WebSocket upgrades to `HttpClient.connectionFactory` as
`https://host:0/...` (or `http://host:0/...`) and only fills in the scheme's default
port on its own internal connect path. `applyClientCertificates`
(`packages/server_core/lib/src/network/client_certificates_io.dart`) passes `uri.port`
straight to `Socket.startConnect` / `SecureSocket.startConnect`, so every `wss://`
session socket dials port 0 and fails with `SocketException: Connection refused`.

Since `_MoonfinHttpOverrides` installs this factory unconditionally on Android, the
Jellyfin session WebSocket fails for **all Android users, with or without a client
certificate**: no remote control ("Play on" from Jellyfin web), no session
notifications. Logs show `Jellyfin WebSocket connection failed, retrying` every ~40 s.

**Fix:** when the port is 0, fall back to the scheme's default (443 for https/wss,
80 otherwise). 6 lines, no behaviour change for any other request.

**Tested:** Nvidia Shield (Android 11), Flutter 3.47.7, behind Caddy (TLS 1.3, client
certificate required). Before: `Connection refused` loop. After: `Jellyfin WebSocket
connected` at startup, remote pause/play/stop from Jellyfin web applied on the device.
Also reproduced and verified on Windows with an identical `HttpOverrides`.

---

## `upstream-pr/mtls-onboarding`

**Title:** Offer client-certificate import for the first https candidate

**Description:**

Adding a server behind a reverse proxy that requires a client certificate (e.g. Caddy
with `client_auth { mode require_and_verify }`) never showed the "Add client
certificate" button on Android TV:

1. With TLS 1.3 the client completes its side of the handshake before the server
   verifies the certificate. Caddy sends `certificate_required` (alert 116) and closes
   the connection. On Android, the request write usually hits the closed socket first:
   `HttpException: Broken pipe` (5/5 tries on a Shield), so
   `isClientCertificateRejected()` does not match and `clientCertCandidate` stays null.
   On Windows the same probe reads `TLSV1_ALERT_CERTIFICATE_REQUIRED` (10/10).
2. The fallback meant for exactly this case ("a proxy that turns a missing certificate
   away looks like any other failure, so offer the import anyway") checks
   `lastCandidate`, which is always the plain `http://host:8920` candidate built by
   `ServerRepository._buildCandidates`. It never fires.

**Fix:** offer the import for the first `https` candidate that was tried instead of the
last candidate.

**Possible follow-ups (not in this PR):** treat `Broken pipe` / `Connection reset by
peer` on an https candidate as "certificate possibly required" in
`isClientCertificateRejected()`, and have `probeServerPublicInfo` keep the first TLS
error instead of only the last path's error.

**Tested:** Nvidia Shield (Android 11) against Caddy over TLS 1.3: the button now shows
under "Unable to connect to server", the `.p12` imports through "Send from phone" and
login (Quick Connect) succeeds.

Side note: `clientCertAddButton` and the certificate dialog strings ("Client
certificate", "Send from phone", "Stop waiting") have no French translation yet.
