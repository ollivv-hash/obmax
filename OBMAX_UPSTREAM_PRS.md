# Upstream PRs (Moonfin-Client/Moonfin-Core)

Two clean branches on the fork `ollivv-hash/Moonfin-Core`, based on `upstream/main` and free of anything OB Max. They are cherry-picked as-is into `obmax/main`, so once merged upstream the rebase drops them.

How to open each one:

1. Open the "Create PR" link below while signed in as `ollivv-hash`.
2. Check the header: base `Moonfin-Client/Moonfin-Core` `main` ← head `ollivv-hash/Moonfin-Core` `upstream-pr/…`, one commit.
3. Click **Create pull request**, paste the title, replace the template with the body below (it follows the template, boxes already ticked), then **Create pull request**.
4. Watch the CI bot comment on the PR (analyzer, tests, builds) and answer review questions there.

Upstream asks contributors to say when an AI assistant helped, and to have run the change themselves: the bodies say both.

---

## PR 1: `upstream-pr/ws-port0`

**Opened:** https://github.com/Moonfin-Client/Moonfin-Core/pull/1893 (2026-10-17)

**Create PR:** https://github.com/Moonfin-Client/Moonfin-Core/compare/main...ollivv-hash:Moonfin-Core:upstream-pr/ws-port0?expand=1

**Title:**

```
Fix WebSocket connections to port 0 in the client-certificate connection factory
```

**Body:**

```markdown
# Pull Request

## Summary
`dart:io` hands WebSocket upgrades to `HttpClient.connectionFactory` as `https://host:0/...` (or `http://host:0/...`) and only fills in the scheme's default port on its own internal connect path. `applyClientCertificates` (`packages/server_core/lib/src/network/client_certificates_io.dart`) passes `uri.port` straight to `Socket.startConnect` / `SecureSocket.startConnect`, so every `wss://` session socket dials port 0 and fails with `SocketException: Connection refused`.

Since `_MoonfinHttpOverrides` installs this factory unconditionally on Android, the Jellyfin session WebSocket fails for all Android users, with or without a client certificate: no remote control ("Play on" from Jellyfin web) and no session notifications. The log shows `Jellyfin WebSocket connection failed, retrying` every ~40 s.

The fix falls back to the scheme's default port (443 for https/wss, 80 otherwise) when the port is 0. No change for any other request.

## Related Issues
- Related to: none found

## Type of Change
- [x] Bug fix
- [ ] New feature
- [ ] Refactor
- [ ] Performance improvement
- [ ] UI/UX update
- [ ] Documentation update
- [ ] Build/CI change
- [ ] Other (describe):

## Changes Made
- `applyClientCertificates`: use the scheme's default port when `dart:io` passes port 0.

## Platform
- [x] Android
- [x] Android TV
- [ ] iOS
- [ ] tvOS
- [ ] Web
- [ ] macOS
- [ ] Windows
- [ ] Linux
- [ ] All / Shared code

## Testing
- [ ] Tested on emulator / simulator
- [x] Tested on physical device
- [x] Manual testing completed
- [ ] Not tested (explain why):

Nvidia Shield (Android 11), Flutter 3.47.7, server behind Caddy (TLS 1.3, client certificate required). Also reproduced and verified on Windows with an identical `HttpOverrides`.

### Test Steps
1. Sign in on Android or Android TV and watch logcat: before the fix, `Jellyfin WebSocket connection failed, retrying` with `Connection refused` every ~40 s.
2. With the fix, `Jellyfin WebSocket connected` at startup and no reconnects over 90 s.
3. From Jellyfin web, "Play on" the device, then pause / play / stop: all applied on the device.

## Screenshots (if applicable)
n/a

## Checklist
- [x] Code builds successfully
- [x] Code follows project style and conventions
- [x] No unnecessary commented-out code
- [x] No new warnings introduced

Written with the help of an AI assistant (Claude Code); I ran and verified the change on the device above.
```

---

## PR 2: `upstream-pr/mtls-onboarding`

**Opened:** https://github.com/Moonfin-Client/Moonfin-Core/pull/1894 (2026-10-17)

**Create PR:** https://github.com/Moonfin-Client/Moonfin-Core/compare/main...ollivv-hash:Moonfin-Core:upstream-pr/mtls-onboarding?expand=1

**Title:**

```
Offer client-certificate import for the first https candidate
```

**Body:**

```markdown
# Pull Request

## Summary
Adding a server behind a reverse proxy that requires a client certificate (e.g. Caddy with `client_auth { mode require_and_verify }`) never showed the "Add client certificate" button on Android TV:

1. With TLS 1.3 the client completes its side of the handshake before the server verifies the certificate. Caddy sends `certificate_required` (alert 116) and closes the connection. On Android the request write usually hits the closed socket first: `HttpException: Broken pipe` (5/5 tries on a Shield), so `isClientCertificateRejected()` does not match and `clientCertCandidate` stays null. On Windows the same probe reads `TLSV1_ALERT_CERTIFICATE_REQUIRED` (10/10).
2. The fallback meant for this case ("a proxy that turns a missing certificate away looks like any other failure, so offer the import anyway") checks `lastCandidate`, which is always the plain `http://host:8920` candidate built by `ServerRepository._buildCandidates`. It never fires.

This PR offers the import for the first `https` candidate that was tried instead of the last candidate.

Possible follow-ups, not in this PR: treat `Broken pipe` / `Connection reset by peer` on an https candidate as "certificate possibly required" in `isClientCertificateRejected()`, and have `probeServerPublicInfo` keep the first TLS error instead of only the last path's.

## Related Issues
- Related to: none found

## Type of Change
- [x] Bug fix
- [ ] New feature
- [ ] Refactor
- [ ] Performance improvement
- [ ] UI/UX update
- [ ] Documentation update
- [ ] Build/CI change
- [ ] Other (describe):

## Changes Made
- `AddServerDialog`: the import fallback uses the first https candidate tried, not the last candidate.

## Platform
- [x] Android
- [x] Android TV
- [ ] iOS
- [ ] tvOS
- [ ] Web
- [ ] macOS
- [ ] Windows
- [ ] Linux
- [ ] All / Shared code

## Testing
- [ ] Tested on emulator / simulator
- [x] Tested on physical device
- [x] Manual testing completed
- [ ] Not tested (explain why):

Nvidia Shield (Android 11) against Caddy over TLS 1.3. `test/add_server_dialog_test.dart` and `test/auth/server_repository_idn_test.dart` pass.

### Test Steps
1. Without any client certificate imported, add a server whose proxy requires one (TLS 1.3).
2. Before: "Unable to connect to server" and no import button. After: the "Add client certificate" button shows under the error.
3. Import the `.p12` through "Send from phone" (TV) or the file picker (phone), then sign in (Quick Connect works).

## Screenshots (if applicable)
n/a

## Checklist
- [x] Code builds successfully
- [x] Code follows project style and conventions
- [x] No unnecessary commented-out code
- [x] No new warnings introduced

Written with the help of an AI assistant (Claude Code); I ran and verified the change on the device above.
```

Side note for a separate contribution: `clientCertAddButton` and the certificate dialog strings ("Client certificate", "Send from phone", "Stop waiting") had no French translation. Upstream translations go through Weblate (translate.moonfin.io), not through the `.arb` files.
