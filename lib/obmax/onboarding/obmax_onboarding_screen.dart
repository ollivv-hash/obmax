import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:server_core/server_core.dart';

import '../../auth/repositories/server_repository.dart';
import '../../auth/store/client_certificate_store.dart';
import '../../data/services/certificate_upload_server.dart';
import '../../data/services/client_certificate_service.dart';
import '../../ui/navigation/destinations.dart';
import '../../util/pkcs12_decoder.dart';
import '../../util/platform_detection.dart';
import '../enroll/obmax_code_server.dart';
import '../enroll/obmax_enrollment.dart';
import '../obmax_config.dart';
import '../theme/obmax_colors.dart';

/// OB Max entry point, in place of Moonfin's server selection.
///
/// 1. No valid certificate for the server host: "Installer votre certificat"
///    (file picker on a phone, QR code and LAN upload on a TV).
/// 2. Connection test on `/System/Info/Public`. A TLS refusal goes back to 1
///    with the reason, a network failure offers a retry.
/// 3. The server is registered and the user goes on to log in.
class ObMaxOnboardingScreen extends StatefulWidget {
  const ObMaxOnboardingScreen({super.key});

  /// Whether this device lacks a usable certificate for the OB Max server
  /// (never imported, removed in Settings, or expired). Without one nothing
  /// works, so startup goes straight to this screen.
  static Future<bool> needsCertificate() async {
    final host = normalizeCertificateHost(Uri.parse(kObMaxServerUrl).host);
    final stored = await GetIt.instance<ClientCertificateStore>().get(host);
    return stored == null || stored.notAfter.isBefore(DateTime.now());
  }

  @override
  State<ObMaxOnboardingScreen> createState() => _ObMaxOnboardingScreenState();
}

enum _Step { checking, certificate, testing, unreachable }

class _ObMaxOnboardingScreenState extends State<ObMaxOnboardingScreen> {
  final _store = GetIt.instance<ClientCertificateStore>();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  late final String _host = normalizeCertificateHost(
    Uri.parse(kObMaxServerUrl).host,
  );

  _Step _step = _Step.checking;
  String? _error;
  bool _busy = false;

  // Phone: the picked file.
  String? _fileName;
  Uint8List? _file;

  // TV: the LAN upload page the phone sends the file to.
  CertificateUploadServer? _upload;
  List<String> _uploadUrls = const [];
  Timer? _uploadExpiry;

  // V2: invitation code (the main path); the .p12 import stays as a fallback.
  bool _p12Mode = false;
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  ObMaxCodeServer? _codeServer;
  List<String> _codeUrls = const [];
  String? _enrolledUsername;

  bool get _fromPhone => PlatformDetection.isTV;

  @override
  void initState() {
    super.initState();
    unawaited(_checkStoredCertificate());
  }

  @override
  void dispose() {
    _uploadExpiry?.cancel();
    _upload?.close();
    _codeServer?.close();
    _code.dispose();
    _codeFocus.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _checkStoredCertificate() async {
    final stored = await _store.get(_host);
    if (!mounted) return;
    if (stored == null) {
      _askForCertificate();
    } else if (stored.notAfter.isBefore(DateTime.now())) {
      _askForCertificate(error: _expired(stored.notAfter));
    } else {
      await _testConnection();
    }
  }

  void _askForCertificate({String? error}) {
    setState(() {
      _step = _Step.certificate;
      _error = error;
      _busy = false;
    });
    if (!_fromPhone) return;
    if (_p12Mode) {
      _stopCodeServer();
      if (_upload == null) unawaited(_startUpload());
    } else {
      if (_upload != null) _stopUpload();
      if (_codeServer == null) unawaited(_startCodeServer());
    }
  }

  void _switchMode() {
    setState(() => _p12Mode = !_p12Mode);
    _askForCertificate();
  }

  // ------------------------------------------------------- invitation code

  Future<void> _enrollWithCode(String code) async {
    if (_busy || code.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final enrollment = await ObMaxEnroller.enroll(code);
      if (!mounted) return;
      _enrolledUsername = enrollment.jellyfinUsername;
      _code.clear();
      _stopCodeServer();
      await _testConnection();
    } on ObMaxEnrollException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
      if (!_fromPhone) _codeFocus.requestFocus();
    }
  }

  Future<void> _startCodeServer() async {
    final server = ObMaxCodeServer(
      onCode: (code) {
        if (!mounted) return;
        _code.text = _CodeFormatter.format(code);
        unawaited(_enrollWithCode(code));
      },
    );
    try {
      await server.start();
      final urls = await _lanUrls(server.port!, server.path);
      if (urls.isEmpty || !mounted) throw StateError('no LAN address');
      setState(() {
        _codeServer = server;
        _codeUrls = urls;
      });
    } catch (_) {
      server.close();
    }
  }

  void _stopCodeServer() {
    final server = _codeServer;
    if (server == null) return;
    server.close();
    if (mounted) setState(() => _codeServer = null);
  }

  static Future<List<String>> _lanUrls(int port, String path) async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    return [
      for (final interface in interfaces)
        for (final address in interface.addresses)
          if (_isPrivate(address.rawAddress))
            'http://${address.address}:$port$path',
    ];
  }

  // ---------------------------------------------------------------- import

  static String _describe(Pkcs12Exception error) =>
      error.error == Pkcs12Error.wrongPassword
      ? 'Mot de passe incorrect pour ce certificat.'
      : 'Ce fichier n’est pas un certificat valide. Choisissez le fichier .p12 que vous avez reçu.';

  String _expired(DateTime date) {
    final local = date.toLocal();
    final d = '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
    return 'Ce certificat a expiré le $d. Demandez-en un nouveau.';
  }

  Future<void> _pickFile() async {
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['p12', 'pfx'],
        withData: true,
      );
      final file = picked?.files.singleOrNull;
      if (file == null || !mounted) return;
      setState(() {
        _file = file.bytes;
        _fileName = file.name;
        _error = file.bytes == null
            ? 'Impossible de lire ce fichier. Réessayez.'
            : null;
      });
      if (file.bytes != null) _passwordFocus.requestFocus();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Impossible d’ouvrir le sélecteur de fichiers.');
      }
    }
  }

  Future<void> _installFromFile() async {
    final file = _file;
    if (file == null) return;
    final Pkcs12Decoded decoded;
    try {
      decoded = decodePkcs12(file, _password.text);
    } on Pkcs12Exception catch (e) {
      setState(() => _error = _describe(e));
      return;
    }
    await _install(decoded);
  }

  Future<void> _startUpload() async {
    final upload = CertificateUploadServer(describeError: _describe);
    try {
      await upload.start();
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      final urls = [
        for (final interface in interfaces)
          for (final address in interface.addresses)
            if (_isPrivate(address.rawAddress))
              'http://${address.address}:${upload.port}${upload.path}',
      ];
      if (urls.isEmpty || !mounted) throw StateError('no LAN address');
      setState(() {
        _upload = upload;
        _uploadUrls = urls;
      });
      // CertificateUploadServer stops listening after 10 minutes without
      // telling anyone; drop the QR code at the same time.
      _uploadExpiry?.cancel();
      _uploadExpiry = Timer(const Duration(minutes: 10), () {
        if (mounted && identical(_upload, upload)) _stopUpload();
      });
      final decoded = await upload.received;
      if (!mounted || !identical(_upload, upload)) return;
      _stopUpload();
      await _install(decoded);
    } catch (_) {
      upload.close();
      if (mounted) {
        setState(() {
          _upload = null;
          _error =
              'Impossible de démarrer la réception. Vérifiez que la TV est '
              'connectée au Wi-Fi, puis réessayez.';
        });
      }
    }
  }

  void _stopUpload() {
    _uploadExpiry?.cancel();
    _upload?.close();
    setState(() => _upload = null);
  }

  static bool _isPrivate(List<int> ip) =>
      ip[0] == 10 ||
      (ip[0] == 172 && ip[1] >= 16 && ip[1] <= 31) ||
      (ip[0] == 192 && ip[1] == 168);

  Future<void> _install(Pkcs12Decoded decoded) async {
    if (decoded.notAfter.isBefore(DateTime.now())) {
      _askForCertificate(error: _expired(decoded.notAfter));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await _store.save(
      StoredClientCertificate(
        host: _host,
        chainPem: decoded.chainPem,
        keyPem: decoded.keyPem,
        subject: decoded.subject,
        notAfter: decoded.notAfter,
      ),
    );
    if (_store.consumeSecureStorageUnavailable()) {
      _askForCertificate(
        error:
            'Cet appareil n’a pas de stockage sécurisé : le certificat ne peut '
            'pas être enregistré.',
      );
      return;
    }
    await installClientCertificates(_store);
    await ObMaxEnroller.forget(); // an imported certificate does not renew
    _enrolledUsername = null;
    _password.clear();
    _file = null;
    _fileName = null;
    await _testConnection();
  }

  // ------------------------------------------------------- connection test

  Future<void> _testConnection() async {
    setState(() {
      _step = _Step.testing;
      _error = null;
    });
    final failure = await _probe();
    if (!mounted) return;
    switch (failure) {
      case null:
        final server =
            await GetIt.instance<ServerRepository>().addServer(kObMaxServerUrl);
        if (!mounted) return;
        if (server == null) {
          setState(() {
            _step = _Step.unreachable;
            _error = 'Le serveur a répondu, mais son enregistrement a échoué. '
                'Réessayez.';
          });
          return;
        }
        final username = _enrolledUsername;
        context.go(
          username == null || username.isEmpty
              ? '${Destinations.server}?serverId=${server.id}'
              // Activated with a code: straight to sign-in, name filled in.
              : '${Destinations.login}?serverId=${server.id}'
                    '&username=${Uri.encodeQueryComponent(username)}',
        );
      case _ProbeFailure.certificate:
        _askForCertificate(
          error: 'Le serveur a refusé ce certificat. Vérifiez que c’est le bon '
              'fichier, ou demandez-en un nouveau.',
        );
      case _ProbeFailure.network:
        setState(() {
          _step = _Step.unreachable;
          _error = 'Impossible de joindre le serveur. Vérifiez la connexion '
              'internet de l’appareil, puis réessayez.';
        });
    }
  }

  /// GET /System/Info/Public through the same mTLS-aware client as the app.
  Future<_ProbeFailure?> _probe() async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
    configureServerDio(dio);
    try {
      await dio.get<dynamic>('$kObMaxServerUrl/System/Info/Public');
      return null;
    } on DioException catch (e) {
      return _classify(e);
    } catch (_) {
      return _ProbeFailure.network;
    } finally {
      dio.close();
    }
  }

  /// Over TLS 1.3 Android often sees the refusal as a broken pipe or a reset
  /// rather than the certificate_required alert, so those count as a refusal
  /// too. A lookup or connect failure is the network.
  static _ProbeFailure _classify(DioException e) {
    if (isClientCertificateRejected(e)) return _ProbeFailure.certificate;
    final reason = '${e.error} ${e.message}'.toLowerCase();
    const tlsSigns = [
      'broken pipe',
      'connection reset',
      'handshake',
      'certificate',
      'tlsv1_alert',
      'sslv3_alert',
    ];
    if (e.type != DioExceptionType.connectionTimeout &&
        tlsSigns.any(reason.contains) &&
        !reason.contains('failed host lookup')) {
      return _ProbeFailure.certificate;
    }
    final status = e.response?.statusCode;
    if (status == 400 || status == 495 || status == 496) {
      return _ProbeFailure.certificate;
    }
    return _ProbeFailure.network;
  }

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final isTv = PlatformDetection.isTV;
    return Scaffold(
      backgroundColor: ObMaxColors.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.6),
            radius: 1.2,
            colors: [Color(0x5575439B), ObMaxColors.background],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: 24,
                vertical: isTv ? 32 : 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isTv ? 760 : 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset(
                      'assets/obmax/logo.png',
                      height: isTv ? 120 : 110,
                    ),
                    const SizedBox(height: 24),
                    ..._content(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    switch (_step) {
      case _Step.checking:
      case _Step.testing:
        return [
          _title(
            _step == _Step.testing
                ? 'Connexion au serveur…'
                : 'Préparation…',
          ),
          const SizedBox(height: 24),
          const Center(
            child: SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: ObMaxColors.primary,
              ),
            ),
          ),
        ];
      case _Step.unreachable:
        return [
          _title('Serveur injoignable'),
          const SizedBox(height: 12),
          if (_error != null) _message(_error!, error: true),
          const SizedBox(height: 24),
          FilledButton(
            autofocus: true,
            onPressed: _testConnection,
            child: const Text('Réessayer'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _askForCertificate(),
            child: const Text('Remplacer le certificat'),
          ),
        ];
      case _Step.certificate:
        return [
          _title(_p12Mode ? 'Installer votre certificat' : 'Activer OB Max'),
          const SizedBox(height: 12),
          _message(
            _p12Mode
                ? 'Choisissez le certificat personnel (fichier .p12) que vous '
                      'avez reçu, et saisissez son mot de passe.'
                : 'OB Max est un service privé. Saisissez le code d’invitation '
                      'que vous avez reçu (12 caractères).',
          ),
          const SizedBox(height: 24),
          if (!_p12Mode)
            ..._codeEntry(context)
          else if (_fromPhone)
            ..._tvImport(context)
          else
            ..._phoneImport(context),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _message(_error!, error: true),
          ],
          const SizedBox(height: 20),
          Center(
            child: TextButton(
              onPressed: _busy ? null : _switchMode,
              child: Text(
                _p12Mode
                    ? 'J’ai un code d’invitation'
                    : 'J’ai un fichier de certificat (.p12)',
              ),
            ),
          ),
        ];
    }
  }

  List<Widget> _codeEntry(BuildContext context) {
    final isTv = PlatformDetection.isTV;
    final codeServer = _codeServer;
    return [
      TextField(
        controller: _code,
        focusNode: _codeFocus,
        autofocus: !isTv,
        enabled: !_busy,
        textAlign: TextAlign.center,
        textCapitalization: TextCapitalization.characters,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.visiblePassword,
        inputFormatters: [_CodeFormatter()],
        style: const TextStyle(
          color: ObMaxColors.textPrimary,
          fontSize: 24,
          letterSpacing: 3,
          fontWeight: FontWeight.w600,
        ),
        decoration: const InputDecoration(
          hintText: 'XXXX-XXXX-XXXX',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => unawaited(_enrollWithCode(v)),
      ),
      const SizedBox(height: 16),
      FilledButton(
        autofocus: isTv,
        style: FilledButton.styleFrom(
          backgroundColor: ObMaxColors.primary,
          foregroundColor: ObMaxColors.onPrimary,
        ),
        onPressed: _busy ? null : () => unawaited(_enrollWithCode(_code.text)),
        child: _busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Activer'),
      ),
      if (isTv && codeServer != null) ...[
        const SizedBox(height: 28),
        Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: QrImageView(
                  data: _codeUrls.first,
                  size: 150,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Plus simple : scannez ce QR code avec un téléphone connecté '
                    'au même Wi-Fi, et tapez-y le code.',
                    style: TextStyle(
                      color: ObMaxColors.textPrimary,
                      fontSize: 16,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final url in _codeUrls)
                    Text(
                      url,
                      style: const TextStyle(
                        color: ObMaxColors.highlight,
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    ];
  }

  List<Widget> _phoneImport(BuildContext context) {
    final canInstall = !_busy && _file != null;
    return [
      FilledButton.icon(
        autofocus: true,
        onPressed: _busy ? null : _pickFile,
        icon: const Icon(Icons.folder_open),
        label: const Text('Choisir le fichier .p12'),
      ),
      if (_fileName != null) ...[
        const SizedBox(height: 8),
        Text(
          _fileName!,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: ObMaxColors.textSecondary),
        ),
      ],
      const SizedBox(height: 16),
      TextField(
        controller: _password,
        focusNode: _passwordFocus,
        obscureText: true,
        enabled: !_busy,
        style: const TextStyle(color: ObMaxColors.textPrimary),
        decoration: const InputDecoration(
          labelText: 'Mot de passe du certificat',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => canInstall ? _installFromFile() : null,
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: canInstall ? _installFromFile : null,
        child: _busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Installer'),
      ),
    ];
  }

  List<Widget> _tvImport(BuildContext context) {
    final upload = _upload;
    if (upload == null) {
      return [
        FilledButton(
          autofocus: true,
          onPressed: _busy ? null : _startUpload,
          child: const Text('Recevoir le certificat depuis le téléphone'),
        ),
      ];
    }
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: QrImageView(
                data: _uploadUrls.first,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '1. Connectez votre téléphone au même Wi-Fi que la TV.\n'
                  '2. Scannez ce QR code, ou ouvrez l’adresse ci-dessous dans '
                  'son navigateur.\n'
                  '3. Choisissez le fichier .p12, saisissez son mot de passe, '
                  'puis appuyez sur « Envoyer ».',
                  style: TextStyle(
                    color: ObMaxColors.textPrimary,
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                for (final url in _uploadUrls)
                  Text(
                    url,
                    style: const TextStyle(
                      color: ObMaxColors.highlight,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      const Center(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: ObMaxColors.primary,
          ),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'En attente du certificat…',
        textAlign: TextAlign.center,
        style: TextStyle(color: ObMaxColors.textSecondary),
      ),
      // Something focusable, so the remote has a target on this screen.
      const SizedBox(height: 8),
      Center(
        child: TextButton(
          autofocus: true,
          onPressed: _stopUpload,
          child: const Text('Arrêter l’attente'),
        ),
      ),
    ];
  }

  Widget _title(String text) => Text(
    text,
    textAlign: TextAlign.center,
    style: const TextStyle(
      color: ObMaxColors.highlight,
      fontSize: 26,
      fontWeight: FontWeight.w700,
    ),
  );

  Widget _message(String text, {bool error = false}) => Text(
    text,
    textAlign: TextAlign.center,
    style: TextStyle(
      color: error ? ObMaxColors.error : ObMaxColors.textSecondary,
      fontSize: 16,
      height: 1.4,
    ),
  );
}

enum _ProbeFailure { certificate, network }

/// Uppercase, letters and digits only, dashes every four: XXXX-XXXX-XXXX.
class _CodeFormatter extends TextInputFormatter {
  static final _allowed = RegExp(r'[0-9A-Z]');

  static String format(String raw) {
    final chars = raw
        .toUpperCase()
        .split('')
        .where(_allowed.hasMatch)
        .take(12)
        .toList();
    final b = StringBuffer();
    for (var i = 0; i < chars.length; i++) {
      if (i > 0 && i % 4 == 0) b.write('-');
      b.write(chars[i]);
    }
    return b.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = format(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
