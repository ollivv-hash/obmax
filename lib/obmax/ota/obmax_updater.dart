import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../util/platform_detection.dart';
import '../obmax_config.dart';
import '../theme/obmax_colors.dart';

/// Which APK of a release this build installs. `tools/release.ps1` passes it
/// with --dart-define; a build without it guesses from the device.
const _flavorDefine = String.fromEnvironment('OBMAX_FLAVOR');

/// One release as described by the `version.json` asset of the releases repo.
@immutable
class ObMaxRelease {
  const ObMaxRelease({
    required this.versionName,
    required this.versionCode,
    required this.mandatory,
    required this.notes,
    required this.apkUrl,
    required this.sha256,
  });

  final String versionName;
  final int versionCode;
  final bool mandatory;
  final String notes;
  final Uri apkUrl;
  final String sha256;

  static ObMaxRelease? fromJson(Map<String, dynamic> json, String flavor) {
    final assets = json['assets'];
    final asset = assets is Map ? assets[flavor] : null;
    final url = asset is Map ? Uri.tryParse('${asset['url']}') : null;
    final hash = asset is Map ? '${asset['sha256']}'.toLowerCase() : '';
    final code = json['versionCode'];
    if (url == null || hash.length != 64 || code is! int) return null;
    return ObMaxRelease(
      versionName: '${json['versionName'] ?? ''}',
      versionCode: code,
      mandatory: json['mandatory'] == true,
      notes: '${json['notes'] ?? ''}',
      apkUrl: url,
      sha256: hash,
    );
  }
}

/// OB Max over-the-air updates on Android: `version.json` from the latest
/// GitHub release of [kObMaxReleasesRepo], a French dialog, download with
/// progress, SHA-256 check, then PackageInstaller (ObMaxInstaller.kt).
abstract final class ObMaxUpdater {
  static const _channel = MethodChannel('obmax/installer');
  static const _lastCheckKey = 'obmax_update_last_check_ms';
  static const _cooldown = Duration(hours: 24);

  static bool _dialogOpen = false;

  /// Final PackageInstaller results (ObMaxInstaller.kt `onStatus`). Success
  /// replaces the running app, so only failures are seen here in practice.
  static final _statuses = StreamController<({int status, String? message})>
      .broadcast();
  static bool _listening = false;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onStatus') return;
      final args = (call.arguments as Map).cast<String, Object?>();
      _statuses.add((
        status: args['status'] as int? ?? 1,
        message: args['message'] as String?,
      ));
    });
  }

  /// No OTA on iOS (TestFlight later) or anywhere but Android.
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  static String get flavor => _flavorDefine.isNotEmpty
      ? _flavorDefine
      : (PlatformDetection.isTV ? 'androidTv' : 'mobile');

  static Uri get _versionJsonUrl => Uri.parse(
    'https://github.com/$kObMaxReleasesRepo/releases/latest/download/version.json',
  );

  /// At most once a day, from startup. Silent unless there is an update.
  static Future<void> checkIfDue(BuildContext? Function() context) async {
    if (!isSupported) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_lastCheckKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - last < _cooldown.inMilliseconds) return;
      final release = await _fetchNewer();
      await prefs.setInt(_lastCheckKey, now);
      if (release == null) return;
      final ctx = context();
      if (ctx != null && ctx.mounted) await _offer(ctx, release);
    } catch (e) {
      debugPrint('OB Max update check failed: $e');
    }
  }

  /// From Settings > About: always checks and always says what it found.
  static Future<void> checkFromSettings(BuildContext context) async {
    if (!isSupported) return;
    ObMaxRelease? release;
    var failed = false;
    try {
      release = await _fetchNewer();
    } catch (e) {
      debugPrint('OB Max update check failed: $e');
      failed = true;
    }
    if (!context.mounted) return;
    if (release != null) {
      await _offer(context, release);
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          failed
              ? 'Impossible de vérifier les mises à jour. Réessayez plus tard.'
              : 'OB Max est à jour.',
        ),
      ),
    );
  }

  static Future<ObMaxRelease?> _fetchNewer() async {
    final json = await _getJson(_versionJsonUrl);
    final release = ObMaxRelease.fromJson(json, flavor);
    if (release == null) throw const FormatException('version.json invalide');
    final info = await PackageInfo.fromPlatform();
    final installed = int.tryParse(info.buildNumber) ?? 0;
    return release.versionCode > installed ? release : null;
  }

  static Future<Map<String, dynamic>> _getJson(Uri url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(url);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  static Future<void> _offer(BuildContext context, ObMaxRelease release) async {
    if (_dialogOpen) return;
    _dialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !release.mandatory,
        useRootNavigator: true,
        builder: (_) => _UpdateDialog(release: release),
      );
    } finally {
      _dialogOpen = false;
    }
  }

  /// Downloads [release]'s APK into the cache, reporting progress (0..1, or
  /// null while the size is unknown), and returns it once its SHA-256 matches.
  static Future<File> download(
    ObMaxRelease release,
    void Function(double? progress) onProgress,
  ) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/obmax_ota');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final file = File('${dir.path}/obmax-${release.versionName}.apk');

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(release.apkUrl);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: release.apkUrl);
      }
      final total = response.contentLength;
      var received = 0;
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      final out = file.openWrite();
      await for (final chunk in response) {
        out.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress(total > 0 ? received / total : null);
      }
      await out.close();
      hasher.close();
      if (digestSink.value.toString() != release.sha256) {
        await file.delete();
        throw const _ChecksumMismatch();
      }
      return file;
    } finally {
      client.close();
    }
  }

  static Future<bool> canInstall() async =>
      await _channel.invokeMethod<bool>('canInstall') ?? false;

  static Future<void> openInstallPermission() =>
      _channel.invokeMethod<void>('openInstallPermission');

  /// "pending" once the system takes over, otherwise an error message.
  static Future<String> install(File apk) async {
    _listen();
    return await _channel.invokeMethod<String>('install', {'path': apk.path}) ??
        'Erreur inconnue';
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

class _ChecksumMismatch implements Exception {
  const _ChecksumMismatch();
}

enum _Phase { offer, downloading, permission, installing, failed }

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.release});

  final ObMaxRelease release;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog>
    with WidgetsBindingObserver {
  _Phase _phase = _Phase.offer;
  double? _progress;
  String? _error;
  File? _apk;
  StreamSubscription<({int status, String? message})>? _statusSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _statusSub = ObMaxUpdater._statuses.stream.listen((s) {
      // 0 is PackageInstaller.STATUS_SUCCESS, 3 STATUS_FAILURE_ABORTED.
      if (s.status == 0) return;
      _fail(s.status == 3
          ? 'Installation annulée.'
          : 'L’installation a échoué${s.message == null ? '' : ' : ${s.message}'}.');
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the "install unknown apps" screen: carry on if it was granted.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _phase == _Phase.permission) {
      unawaited(_install());
    }
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.downloading;
      _progress = null;
      _error = null;
    });
    try {
      _apk = await ObMaxUpdater.download(
        widget.release,
        (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      await _install();
    } on _ChecksumMismatch {
      _fail('Le fichier téléchargé est corrompu (empreinte SHA-256 invalide). '
          'Réessayez.');
    } catch (_) {
      _fail('Le téléchargement a échoué. Vérifiez votre connexion et '
          'réessayez.');
    }
  }

  Future<void> _install() async {
    final apk = _apk;
    if (apk == null) return;
    if (!await ObMaxUpdater.canInstall()) {
      if (mounted) setState(() => _phase = _Phase.permission);
      return;
    }
    if (mounted) setState(() => _phase = _Phase.installing);
    final result = await ObMaxUpdater.install(apk);
    if (result == 'permission') {
      if (mounted) setState(() => _phase = _Phase.permission);
    } else if (result != 'pending') {
      _fail('L’installation a échoué : $result');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.failed;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final release = widget.release;
    final canDismiss = !release.mandatory && _phase != _Phase.installing;
    return PopScope(
      canPop: canDismiss,
      child: AlertDialog(
        backgroundColor: ObMaxColors.surface,
        title: Text(
          'OB Max ${release.versionName} est disponible',
          style: const TextStyle(color: ObMaxColors.highlight),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _body(release),
          ),
        ),
        actions: _actions(release, canDismiss),
      ),
    );
  }

  List<Widget> _body(ObMaxRelease release) {
    switch (_phase) {
      case _Phase.offer:
        return [
          if (release.mandatory)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Cette mise à jour est obligatoire.',
                style: TextStyle(color: ObMaxColors.primary),
              ),
            ),
          Text(
            release.notes.isEmpty ? 'Corrections et améliorations.' : release.notes,
            style: const TextStyle(color: ObMaxColors.textSecondary),
          ),
        ];
      case _Phase.downloading:
        final p = _progress;
        return [
          Text(p == null
              ? 'Téléchargement…'
              : 'Téléchargement… ${(p * 100).round()} %'),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: p,
            color: ObMaxColors.primary,
            backgroundColor: ObMaxColors.surfaceVariant,
          ),
        ];
      case _Phase.permission:
        return const [
          Text(
            'Pour installer la mise à jour, autorisez OB Max à installer des '
            'applications : ouvrez les réglages, activez « Autoriser depuis '
            'cette source », puis revenez ici.',
          ),
        ];
      case _Phase.installing:
        return const [
          Text('Installation… Confirmez dans la fenêtre du système. OB Max '
              'redémarrera avec vos données intactes.'),
          SizedBox(height: 12),
          LinearProgressIndicator(color: ObMaxColors.primary),
        ];
      case _Phase.failed:
        return [
          Text(_error ?? '', style: const TextStyle(color: ObMaxColors.error)),
        ];
    }
  }

  List<Widget> _actions(ObMaxRelease release, bool canDismiss) {
    final later = TextButton(
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Plus tard'),
    );
    FilledButton primary(String label, VoidCallback onPressed) => FilledButton(
      autofocus: true,
      style: FilledButton.styleFrom(
        backgroundColor: ObMaxColors.primary,
        foregroundColor: ObMaxColors.onPrimary,
      ),
      onPressed: onPressed,
      child: Text(label),
    );
    switch (_phase) {
      case _Phase.offer:
        return [
          if (canDismiss) later,
          primary('Mettre à jour', () => unawaited(_start())),
        ];
      case _Phase.downloading:
      case _Phase.installing:
        return [if (canDismiss) later];
      case _Phase.permission:
        return [
          if (canDismiss) later,
          primary(
            'Ouvrir les réglages',
            () => unawaited(ObMaxUpdater.openInstallPermission()),
          ),
        ];
      case _Phase.failed:
        return [
          if (canDismiss) later,
          primary('Réessayer', () => unawaited(_start())),
        ];
    }
  }
}
