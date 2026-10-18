import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// The device's own key for OB Max enrollment: EC P-256, generated here and
/// never sent anywhere. Only certificate requests (CSR) signed with it leave
/// the device.
class ObMaxKeyPair {
  ObMaxKeyPair._(this._private, this._public);

  final ECPrivateKey _private;
  final ECPublicKey _public;

  static final _domain = ECDomainParameters('prime256v1');

  static ObMaxKeyPair generate() {
    final random = FortunaRandom()
      ..seed(KeyParameter(_secureBytes(32)));
    final generator = ECKeyGenerator()
      ..init(
        ParametersWithRandom(ECKeyGeneratorParameters(_domain), random),
      );
    final pair = generator.generateKeyPair();
    return ObMaxKeyPair._(
      pair.privateKey,
      pair.publicKey,
    );
  }

  /// Reads back a key written by [privateKeyPem].
  static ObMaxKeyPair fromPrivateKeyPem(String pem) {
    final der = _pemBody(pem, 'PRIVATE KEY');
    // PrivateKeyInfo { version, algorithm, OCTET STRING ECPrivateKey }
    final info = _Der.read(der).children;
    final ecKey = _Der.read(info[2].value).children;
    // ECPrivateKey { version 1, OCTET STRING d, [1] publicKey? }
    final d = _bytesToBigInt(ecKey[1].value);
    final q = _domain.G * d;
    return ObMaxKeyPair._(
      ECPrivateKey(d, _domain),
      ECPublicKey(q, _domain),
    );
  }

  /// PKCS#8, as the rest of the app stores client keys.
  String get privateKeyPem {
    final ecPrivateKey = _seq([
      _int(BigInt.one),
      _octets(_bigIntTo32(_private.d!)),
      _context(1, _bitString(_publicPoint)),
    ]);
    final info = _seq([
      _int(BigInt.zero),
      _ecAlgorithm,
      _octets(ecPrivateKey),
    ]);
    return _pem('PRIVATE KEY', info);
  }

  Uint8List get _publicPoint => _public.Q!.getEncoded(false);

  static final _ecAlgorithm = _seq([
    _oid('1.2.840.10045.2.1'), // id-ecPublicKey
    _oid('1.2.840.10045.3.1.7'), // prime256v1
  ]);

  /// A PKCS#10 request for this key. The service sets the real subject, so
  /// the one here is only a placeholder.
  String csrPem({String commonName = 'obmax'}) {
    final subject = _seq([
      _set([
        _seq([_oid('2.5.4.3'), _utf8(commonName)]),
      ]),
    ]);
    final spki = _seq([_ecAlgorithm, _bitString(_publicPoint)]);
    final info = _seq([
      _int(BigInt.zero),
      subject,
      spki,
      _context(0, Uint8List(0)), // no attributes
    ]);
    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter<ECPrivateKey>(_private));
    final sig = signer.generateSignature(info) as ECSignature;
    final request = _seq([
      info,
      _seq([_oid('1.2.840.10045.4.3.2')]), // ecdsa-with-SHA256
      _bitString(_seq([_int(sig.r), _int(sig.s)])),
    ]);
    return _pem('CERTIFICATE REQUEST', request);
  }
}

// ------------------------------------------------------------------ DER

Uint8List _tlv(int tag, List<int> value) {
  final len = value.length;
  final List<int> lenBytes;
  if (len < 0x80) {
    lenBytes = [len];
  } else {
    final bytes = <int>[];
    var n = len;
    while (n > 0) {
      bytes.insert(0, n & 0xff);
      n >>= 8;
    }
    lenBytes = [0x80 | bytes.length, ...bytes];
  }
  return Uint8List.fromList([tag, ...lenBytes, ...value]);
}

Uint8List _seq(List<Uint8List> items) =>
    _tlv(0x30, [for (final i in items) ...i]);
Uint8List _set(List<Uint8List> items) =>
    _tlv(0x31, [for (final i in items) ...i]);
Uint8List _octets(List<int> b) => _tlv(0x04, b);
Uint8List _bitString(List<int> b) => _tlv(0x03, [0, ...b]);
Uint8List _utf8(String s) => _tlv(0x0c, utf8.encode(s));
Uint8List _context(int n, List<int> b) => _tlv(0xa0 | n, b);

Uint8List _int(BigInt v) {
  var bytes = _bigIntToBytes(v);
  if (bytes.isEmpty) bytes = Uint8List.fromList([0]);
  if (bytes[0] & 0x80 != 0) bytes = Uint8List.fromList([0, ...bytes]);
  return _tlv(0x02, bytes);
}

Uint8List _oid(String dotted) {
  final parts = dotted.split('.').map(int.parse).toList();
  final out = <int>[parts[0] * 40 + parts[1]];
  for (final p in parts.skip(2)) {
    final chunk = <int>[p & 0x7f];
    var n = p >> 7;
    while (n > 0) {
      chunk.insert(0, (n & 0x7f) | 0x80);
      n >>= 7;
    }
    out.addAll(chunk);
  }
  return _tlv(0x06, out);
}

Uint8List _bigIntToBytes(BigInt v) {
  final hex = v.toRadixString(16);
  final even = hex.length.isOdd ? '0$hex' : hex;
  return Uint8List.fromList([
    for (var i = 0; i < even.length; i += 2)
      int.parse(even.substring(i, i + 2), radix: 16),
  ]);
}

Uint8List _bigIntTo32(BigInt v) {
  final b = _bigIntToBytes(v);
  return Uint8List(32)..setRange(32 - b.length, 32, b);
}

BigInt _bytesToBigInt(List<int> bytes) =>
    bytes.fold(BigInt.zero, (acc, b) => (acc << 8) | BigInt.from(b));

/// Just enough DER reading for the key this file writes.
class _Der {
  _Der(this.tag, this.value);
  final int tag;
  final Uint8List value;

  static _Der read(Uint8List data, [int offset = 0]) {
    final (der, _) = _readAt(data, offset);
    return der;
  }

  static (_Der, int) _readAt(Uint8List data, int offset) {
    final tag = data[offset];
    var len = data[offset + 1];
    var pos = offset + 2;
    if (len & 0x80 != 0) {
      final n = len & 0x7f;
      len = 0;
      for (var i = 0; i < n; i++) {
        len = (len << 8) | data[pos + i];
      }
      pos += n;
    }
    return (_Der(tag, Uint8List.sublistView(data, pos, pos + len)), pos + len);
  }

  List<_Der> get children {
    final out = <_Der>[];
    var pos = 0;
    while (pos < value.length) {
      final (child, next) = _readAt(value, pos);
      out.add(child);
      pos = next;
    }
    return out;
  }
}

String _pem(String label, Uint8List der) {
  final b64 = base64.encode(der);
  final lines = [
    for (var i = 0; i < b64.length; i += 64)
      b64.substring(i, min(i + 64, b64.length)),
  ];
  return '-----BEGIN $label-----\n${lines.join('\n')}\n-----END $label-----\n';
}

Uint8List _pemBody(String pem, String label) {
  final body = pem
      .replaceAll('-----BEGIN $label-----', '')
      .replaceAll('-----END $label-----', '')
      .replaceAll(RegExp(r'\s'), '');
  return base64.decode(body);
}

Uint8List _secureBytes(int n) {
  final r = Random.secure();
  return Uint8List.fromList([for (var i = 0; i < n; i++) r.nextInt(256)]);
}
