import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// A PEM bundle of the trusted CAs, for mpv's `tls-ca-file`.
///
/// libmpv's FFmpeg TLS stack (OpenSSL on Windows, its own build on Android)
/// does not read the system trust store, so `tls-verify=yes` fails unless the
/// roots are handed over as one file:
/// - Android keeps them one per file in /system/etc/security/cacerts; only
///   the PEM blocks are copied (the files also carry an `openssl x509 -text`
///   dump).
/// - Windows: the Root store (user and machine), read through crypt32 once
///   a week.
/// - macOS: the system root keychain, through `security`.
/// - Linux: the distribution bundle, used as is.
/// The roots Caddy's certificates chain to (`assets/obmax/tls-roots.pem`) are
/// always appended: Windows only adds a root to its store the first time it
/// needs it, so a fresh PC may not have ISRG Root X2 yet.
/// Returns null when nothing could be built, and mpv then uses its default.
Future<String?> mpvCaBundlePath() async {
  if (Platform.isLinux) {
    for (final path in const [
      '/etc/ssl/certs/ca-certificates.crt',
      '/etc/pki/tls/certs/ca-bundle.crt',
      '/etc/ssl/cert.pem',
    ]) {
      if (await File(path).exists()) return path;
    }
    return null;
  }
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/mtls');
  final bundle = File('${dir.path}/system-ca.pem');
  if (await bundle.exists() && await bundle.length() > 0) {
    final age = DateTime.now().difference(await bundle.lastModified());
    // Android's store only changes with the system; desktop stores change
    // as Windows and macOS update their roots.
    if (Platform.isAndroid || age < const Duration(days: 7)) return bundle.path;
  }
  final out = StringBuffer();
  try {
    if (Platform.isAndroid) {
      await _androidRoots(out);
    } else if (Platform.isWindows) {
      await _windowsRoots(out);
    } else if (Platform.isMacOS) {
      await _macRoots(out);
    } else {
      return null;
    }
  } catch (_) {
    // The bundled roots below still cover the OB Max server.
  }
  try {
    out.writeln(await rootBundle.loadString('assets/obmax/tls-roots.pem'));
  } catch (_) {}
  if (out.isEmpty) {
    return await bundle.exists() ? bundle.path : null;
  }
  await dir.create(recursive: true);
  await bundle.writeAsString(out.toString());
  return bundle.path;
}

final _pem = RegExp(
  r'-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----',
);

Future<void> _androidRoots(StringBuffer out) async {
  final source = Directory('/system/etc/security/cacerts');
  if (!await source.exists()) return;
  await for (final entry in source.list()) {
    if (entry is! File) continue;
    try {
      for (final m in _pem.allMatches(await entry.readAsString())) {
        out.writeln(m.group(0));
      }
    } catch (_) {
      // An unreadable root is skipped, not fatal.
    }
  }
}

/// CERT_CONTEXT is { DWORD type; BYTE* encoded; DWORD length; ... }: on
/// 64-bit Windows the DER pointer sits at offset 8 and its length at 16.
Future<void> _windowsRoots(StringBuffer out) async {
  final crypt32 = DynamicLibrary.open('crypt32.dll');
  final open = crypt32.lookupFunction<
    Pointer<Void> Function(IntPtr, Pointer<Utf16>),
    Pointer<Void> Function(int, Pointer<Utf16>)
  >('CertOpenSystemStoreW');
  final next = crypt32.lookupFunction<
    Pointer<Uint8> Function(Pointer<Void>, Pointer<Uint8>),
    Pointer<Uint8> Function(Pointer<Void>, Pointer<Uint8>)
  >('CertEnumCertificatesInStore');
  final close = crypt32.lookupFunction<
    Int32 Function(Pointer<Void>, Uint32),
    int Function(Pointer<Void>, int)
  >('CertCloseStore');

  final name = 'ROOT'.toNativeUtf16();
  final store = open(0, name);
  malloc.free(name);
  if (store == nullptr) return;
  try {
    var context = next(store, nullptr);
    while (context != nullptr) {
      final der = Pointer<Pointer<Uint8>>.fromAddress(context.address + 8).value;
      final length = Pointer<Uint32>.fromAddress(context.address + 16).value;
      final b64 = base64.encode(der.asTypedList(length));
      out.writeln('-----BEGIN CERTIFICATE-----');
      for (var i = 0; i < b64.length; i += 64) {
        out.writeln(b64.substring(i, i + 64 > b64.length ? b64.length : i + 64));
      }
      out.writeln('-----END CERTIFICATE-----');
      context = next(store, context);
    }
  } finally {
    close(store, 0);
  }
}

Future<void> _macRoots(StringBuffer out) async {
  final result = await Process.run('/usr/bin/security', [
    'find-certificate',
    '-a',
    '-p',
    '/System/Library/Keychains/SystemRootCertificates.keychain',
  ]).timeout(const Duration(seconds: 30));
  if (result.exitCode != 0) return;
  for (final m in _pem.allMatches('${result.stdout}')) {
    out.writeln(m.group(0));
  }
}
