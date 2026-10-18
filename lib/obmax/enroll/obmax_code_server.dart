import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// On a TV, a phone on the same Wi-Fi opens this page (QR code) to type the
/// invitation code, rather than the remote. Each code received goes to
/// [onCode]; the TV does the enrollment and shows the result.
class ObMaxCodeServer {
  ObMaxCodeServer({required this.onCode});

  final void Function(String code) onCode;

  final String path = '/${_token()}';
  HttpServer? _server;
  Timer? _timeout;

  int? get port => _server?.port;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _timeout = Timer(const Duration(minutes: 10), close);
    _server!.listen(_handle);
  }

  void close() {
    _timeout?.cancel();
    _server?.close(force: true);
    _server = null;
  }

  static String _token() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    if (request.uri.path != path) {
      response.statusCode = HttpStatus.notFound;
    } else if (request.method == 'GET') {
      response
        ..headers.contentType = ContentType.html
        ..write(_page);
    } else if (request.method == 'POST') {
      try {
        final body = await utf8.decoder
            .bind(request)
            .join()
            .timeout(const Duration(seconds: 10));
        if (body.length > 1024) throw const FormatException();
        final code = (jsonDecode(body) as Map)['code'];
        if (code is! String || code.trim().isEmpty) {
          throw const FormatException();
        }
        onCode(code.trim());
        response.statusCode = HttpStatus.ok;
      } catch (_) {
        response.statusCode = HttpStatus.badRequest;
      }
    } else {
      response.statusCode = HttpStatus.methodNotAllowed;
    }
    await response.close();
  }

  static const _page = '''
<!doctype html>
<html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>OB Max</title>
<style>
body{font-family:system-ui,sans-serif;background:#080A23;color:#fff;max-width:22rem;margin:2rem auto;padding:0 1rem}
h2{color:#FCE4B6}
p{color:#B8BBD9}
input,button{width:100%;margin:.4rem 0;padding:.8rem;box-sizing:border-box;font-size:1.2rem;border-radius:.5rem}
input{background:#1A1E4D;color:#fff;border:1px solid #2a2f6b;text-transform:uppercase;letter-spacing:.15em;text-align:center}
button{background:#EDA631;color:#080A23;border:0;font-weight:600}
#msg{min-height:1.2rem;margin-top:.6rem}
</style></head><body>
<h2>Activer OB Max sur la TV</h2>
<p>Saisissez le code d’invitation reçu (XXXX-XXXX-XXXX). Il est envoyé à la TV, sur votre réseau local.</p>
<input id="code" autocomplete="off" autocapitalize="characters" spellcheck="false" maxlength="20" placeholder="XXXX-XXXX-XXXX">
<button id="send">Envoyer à la TV</button>
<div id="msg"></div>
<script>
document.getElementById('send').onclick = async () => {
  const code = document.getElementById('code').value.trim();
  const msg = document.getElementById('msg');
  if (!code) { msg.textContent = 'Saisissez d’abord le code.'; return; }
  msg.textContent = 'Envoi…';
  try {
    const res = await fetch(location.pathname, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({code})
    });
    msg.textContent = res.ok ? 'Code envoyé. Regardez la TV.' : 'Échec de l’envoi. Réessayez.';
  } catch (e) {
    msg.textContent = 'La TV n’écoute plus. Recommencez depuis la TV.';
  }
};
</script>
</body></html>
''';
}
