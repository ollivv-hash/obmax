import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:server_core/server_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/store/client_certificate_store.dart';
import '../../data/services/client_certificate_service.dart';
import '../../util/platform_detection.dart';
import '../obmax_config.dart';
import 'obmax_csr.dart';

enum ObMaxEnrollError {
  invalidCode,
  rateLimited,
  revoked,
  invalidCertificate,
  network,
  server,
  storage,
}

class ObMaxEnrollException implements Exception {
  const ObMaxEnrollException(this.kind, this.message);
  final ObMaxEnrollError kind;

  /// In French, ready to show.
  final String message;

  @override
  String toString() => 'ObMaxEnrollException($kind): $message';
}

/// What enrollment left on this device.
@immutable
class ObMaxEnrollment {
  const ObMaxEnrollment({
    required this.deviceId,
    required this.jellyfinUsername,
    required this.notAfter,
  });

  final String deviceId;
  final String jellyfinUsername;
  final DateTime notAfter;
}

/// V2 activation: an invitation code turns into this device's own client
/// certificate, which then renews itself (see docs/obmax/V2_SPEC.md §5).
abstract final class ObMaxEnroller {
  static const _kDeviceId = 'obmax_enroll_device_id';
  static const _kUsername = 'obmax_enroll_username';
  static const _kNotAfter = 'obmax_enroll_not_after';
  static const _kLastAttempt = 'obmax_enroll_last_renew_attempt';

  /// Renew once less than this is left (a third of 180 days).
  static const renewBefore = Duration(days: 60);

  static String get host =>
      normalizeCertificateHost(Uri.parse(kObMaxServerUrl).host);

  /// The enrollment behind the current certificate, if it came from a code.
  static Future<ObMaxEnrollment?> current() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_kDeviceId);
    final notAfter = DateTime.tryParse(prefs.getString(_kNotAfter) ?? '');
    if (id == null || notAfter == null) return null;
    return ObMaxEnrollment(
      deviceId: id,
      jellyfinUsername: prefs.getString(_kUsername) ?? '',
      notAfter: notAfter,
    );
  }

  /// Forgets the enrollment, when the certificate is replaced by a .p12 or
  /// removed.
  static Future<void> forget() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in [_kDeviceId, _kUsername, _kNotAfter, _kLastAttempt]) {
      await prefs.remove(k);
    }
  }

  /// Activates this device with [code]: new key, request, certificate
  /// installed for the OB Max server.
  static Future<ObMaxEnrollment> enroll(String code) async {
    final key = await compute((_) => ObMaxKeyPair.generate().privateKeyPem, null);
    final pair = ObMaxKeyPair.fromPrivateKeyPem(key);
    final body = await _post('/v1/enroll', {
      'code': code,
      'csr': pair.csrPem(),
      'device': _deviceInfo(),
    });
    return _store(body, key);
  }

  /// Renews the certificate when less than [renewBefore] is left (or
  /// [force]), at most once every 12 hours unless forced. Returns true when
  /// a new certificate was installed.
  static Future<bool> renewIfDue({bool force = false}) async {
    final enrollment = await current();
    if (enrollment == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    if (!force) {
      if (enrollment.notAfter.difference(now) > renewBefore) return false;
      final last = prefs.getInt(_kLastAttempt) ?? 0;
      if (now.millisecondsSinceEpoch - last < const Duration(hours: 12).inMilliseconds) {
        return false;
      }
    }
    await prefs.setInt(_kLastAttempt, now.millisecondsSinceEpoch);

    final stored = await GetIt.instance<ClientCertificateStore>().get(host);
    if (stored == null) {
      await forget();
      return false;
    }
    final pair = ObMaxKeyPair.fromPrivateKeyPem(stored.keyPem);
    try {
      final body = await _post('/v1/renew', {
        'deviceId': enrollment.deviceId,
        'certificateChain': stored.chainPem,
        'csr': pair.csrPem(),
        'appVersion': _deviceInfo()['appVersion'],
      });
      await _store(body, stored.keyPem);
      return true;
    } on ObMaxEnrollException catch (e) {
      // A certificate that isn't ours any more (a .p12 imported since, or
      // one the service no longer knows) cannot be renewed this way.
      if (e.kind == ObMaxEnrollError.invalidCertificate) await forget();
      if (force) rethrow;
      debugPrint('OB Max renewal: $e');
      return false;
    }
  }

  static Map<String, String> _deviceInfo() {
    var name = 'Appareil';
    var version = '';
    if (GetIt.instance.isRegistered<DeviceInfo>()) {
      final info = GetIt.instance<DeviceInfo>();
      name = info.name;
      version = info.appVersion;
    }
    final platform = PlatformDetection.isTV
        ? 'androidTv'
        : PlatformDetection.isAndroid
        ? 'mobile'
        : PlatformDetection.isIOS
        ? 'ios'
        : PlatformDetection.isMacOS
        ? 'macos'
        : 'autre';
    return {'name': name, 'platform': platform, 'appVersion': version};
  }

  static Future<ObMaxEnrollment> _store(
    Map<String, dynamic> body,
    String keyPem,
  ) async {
    final chain = body['certificateChain'] as String?;
    final deviceId = body['deviceId'] as String?;
    final notAfter = DateTime.tryParse('${body['notAfter']}');
    if (chain == null || deviceId == null || notAfter == null) {
      throw const ObMaxEnrollException(
        ObMaxEnrollError.server,
        'Réponse inattendue du service d’activation.',
      );
    }
    final store = GetIt.instance<ClientCertificateStore>();
    await store.save(
      StoredClientCertificate(
        host: host,
        chainPem: chain,
        keyPem: keyPem,
        subject: '${body['subject'] ?? ''}',
        notAfter: notAfter,
      ),
    );
    if (store.consumeSecureStorageUnavailable()) {
      throw const ObMaxEnrollException(
        ObMaxEnrollError.storage,
        'Cet appareil n’a pas de stockage sécurisé : le certificat ne peut '
        'pas être enregistré.',
      );
    }
    await installClientCertificates(store);
    final enrollment = ObMaxEnrollment(
      deviceId: deviceId,
      jellyfinUsername: '${body['jellyfinUsername'] ?? ''}',
      notAfter: notAfter,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDeviceId, enrollment.deviceId);
    await prefs.setString(_kUsername, enrollment.jellyfinUsername);
    await prefs.setString(_kNotAfter, notAfter.toIso8601String());
    return enrollment;
  }

  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> payload,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = serverUserAgent;
    try {
      final request = await client.postUrl(Uri.parse('$kObMaxEnrollUrl$path'));
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final text = await response.transform(utf8.decoder).join();
      Map<String, dynamic> body;
      try {
        body = jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {
        body = const {};
      }
      if (response.statusCode == HttpStatus.ok) return body;
      throw _errorFor(response.statusCode, body);
    } on ObMaxEnrollException {
      rethrow;
    } on Exception catch (e) {
      debugPrint('OB Max enroll $path: $e');
      throw const ObMaxEnrollException(
        ObMaxEnrollError.network,
        'Service d’activation injoignable. Vérifiez la connexion internet de '
        'l’appareil, puis réessayez.',
      );
    } finally {
      client.close();
    }
  }

  static ObMaxEnrollException _errorFor(int status, Map<String, dynamic> body) {
    final message = body['message'] as String?;
    switch (body['error']) {
      case 'invalid_code':
        return ObMaxEnrollException(
          ObMaxEnrollError.invalidCode,
          message ?? 'Ce code n’est pas valide ou a expiré.',
        );
      case 'rate_limited':
        return ObMaxEnrollException(
          ObMaxEnrollError.rateLimited,
          message ?? 'Trop d’essais. Réessayez dans une heure.',
        );
      case 'revoked':
        return ObMaxEnrollException(
          ObMaxEnrollError.revoked,
          message ?? 'Cet appareil a été révoqué.',
        );
      case 'invalid_certificate':
        return ObMaxEnrollException(
          ObMaxEnrollError.invalidCertificate,
          message ?? 'Certificat invalide.',
        );
    }
    return ObMaxEnrollException(
      ObMaxEnrollError.server,
      message ?? 'Erreur du service d’activation (HTTP $status).',
    );
  }
}
