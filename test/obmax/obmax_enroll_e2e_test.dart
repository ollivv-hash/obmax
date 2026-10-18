// End-to-end check of the V2 protocol against a running obmax-enroll and a
// TLS server that, like Caddy, requires a client certificate issued by the
// enrollment CA. Skipped unless OBMAX_E2E_ENROLL is set (see
// server/enroll/README.md, "Développement").
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/obmax/enroll/obmax_csr.dart';

Future<(int, Map<String, dynamic>)> _post(
  String url,
  Map<String, Object?> body,
) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse(url));
    req.headers.contentType = ContentType.json;
    req.add(utf8.encode(jsonEncode(body)));
    final resp = await req.close();
    final text = await resp.transform(utf8.decoder).join();
    return (resp.statusCode, jsonDecode(text) as Map<String, dynamic>);
  } finally {
    client.close();
  }
}

/// Opens an HTTPS request presenting [chain]/[keyPem]; returns the status,
/// or throws when the server refuses the handshake.
Future<int> _mtlsGet(String hostPort, String chain, String keyPem) async {
  final ctx = SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(chain))
    ..usePrivateKeyBytes(utf8.encode(keyPem));
  final client = HttpClient(context: ctx)
    // Test server, self-signed.
    ..badCertificateCallback = ((_, _, _) => true)
    ..connectionTimeout = const Duration(seconds: 5);
  try {
    final req = await client.getUrl(Uri.parse('https://$hostPort/'));
    final resp = await req.close();
    await resp.drain<void>();
    return resp.statusCode;
  } finally {
    client.close(force: true);
  }
}

void main() {
  final base = Platform.environment['OBMAX_E2E_ENROLL'];
  final code = Platform.environment['OBMAX_E2E_CODE'];
  final tls = Platform.environment['OBMAX_E2E_TLS'];
  final skip = base == null || code == null;

  test('enroll, present the certificate over mTLS, renew', () async {
    final key = ObMaxKeyPair.generate();

    // 1. Enrollment with the invitation code.
    final (status, body) = await _post('$base/v1/enroll', {
      'code': code!.toLowerCase(), // typed by a person
      'csr': key.csrPem(),
      'device': {'name': 'Test e2e', 'platform': 'mobile', 'appVersion': '2.0.0'},
    });
    expect(status, 200, reason: '$body');
    expect(body['jellyfinUsername'], 'paul');
    expect(body['subject'], 'paul/Test e2e');
    final chain = body['certificateChain'] as String;
    expect('BEGIN CERTIFICATE'.allMatches(chain).length, 2);

    // 2. The certificate and the stored key work for mTLS from dart:io
    // (BoringSSL), against a server trusting only the intermediate.
    if (tls != null) {
      expect(await _mtlsGet(tls, chain, key.privateKeyPem), 200);
      // Without a certificate the server refuses, so the check above means
      // something.
      await expectLater(
        _mtlsGet(tls, '', '').catchError((_) => -1),
        completion(isNot(200)),
      );
    }

    // 3. The code is spent.
    final (again, _) = await _post('$base/v1/enroll', {
      'code': code,
      'csr': ObMaxKeyPair.generate().csrPem(),
      'device': {'name': 'x'},
    });
    expect(again, 403);

    // 4. Renewal with the stored key, read back from its PEM.
    final stored = ObMaxKeyPair.fromPrivateKeyPem(key.privateKeyPem);
    final (renewed, renewBody) = await _post('$base/v1/renew', {
      'deviceId': body['deviceId'],
      'certificateChain': chain,
      'csr': stored.csrPem(),
      'appVersion': '2.0.1',
    });
    expect(renewed, 200, reason: '$renewBody');
    expect(renewBody['certificateChain'], isNot(chain));
    if (tls != null) {
      expect(
        await _mtlsGet(tls, renewBody['certificateChain'] as String, key.privateKeyPem),
        200,
      );
    }

    // 5. Another key cannot renew this device.
    final (stolen, _) = await _post('$base/v1/renew', {
      'deviceId': body['deviceId'],
      'certificateChain': renewBody['certificateChain'],
      'csr': ObMaxKeyPair.generate().csrPem(),
    });
    expect(stolen, 403);
  }, skip: skip ? 'OBMAX_E2E_ENROLL not set' : false);
}
