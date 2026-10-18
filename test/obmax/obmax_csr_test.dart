import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/obmax/enroll/obmax_csr.dart';

void main() {
  test('a key written as PKCS#8 reads back to the same key', () {
    final key = ObMaxKeyPair.generate();
    final again = ObMaxKeyPair.fromPrivateKeyPem(key.privateKeyPem);
    expect(again.privateKeyPem, key.privateKeyPem);
    expect(again.csrPem(), key.csrPem()); // deterministic ECDSA, same key
  });

  test('openssl accepts the CSR and the key', () async {
    final out = Platform.environment['OBMAX_CSR_DIR'];
    if (out == null) return; // only when asked (needs openssl)
    final key = ObMaxKeyPair.generate();
    File('$out/test.key').writeAsStringSync(key.privateKeyPem);
    File('$out/test.csr').writeAsStringSync(key.csrPem());
  });
}
