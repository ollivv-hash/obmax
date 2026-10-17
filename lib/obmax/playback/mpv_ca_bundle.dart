import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A PEM bundle of the system's trusted CAs, for mpv's `tls-ca-file`.
///
/// libmpv's FFmpeg TLS stack does not read the Android trust store, so
/// `tls-verify=yes` needs the roots handed over as one file. Android keeps
/// them one per file in /system/etc/security/cacerts; only the PEM blocks
/// are copied (the files also carry an `openssl x509 -text` dump).
/// Returns null where no such store exists, and mpv then uses its own
/// default.
Future<String?> mpvCaBundlePath() async {
  if (!Platform.isAndroid) return null;
  final source = Directory('/system/etc/security/cacerts');
  if (!await source.exists()) return null;
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/mtls');
  final bundle = File('${dir.path}/system-ca.pem');
  if (await bundle.exists() && await bundle.length() > 0) return bundle.path;
  final pem = RegExp(
    r'-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----',
  );
  final out = StringBuffer();
  await for (final entry in source.list()) {
    if (entry is! File) continue;
    try {
      for (final m in pem.allMatches(await entry.readAsString())) {
        out.writeln(m.group(0));
      }
    } catch (_) {
      // An unreadable root is skipped, not fatal.
    }
  }
  if (out.isEmpty) return null;
  await dir.create(recursive: true);
  await bundle.writeAsString(out.toString());
  return bundle.path;
}
