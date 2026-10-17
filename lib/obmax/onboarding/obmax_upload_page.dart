// OB Max: the page a phone opens to send its .p12 to the TV (served by
// CertificateUploadServer). French and in the OB Max colors.
const kObMaxCertificateUploadPage = '''
<!doctype html>
<html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>OB Max</title>
<style>
body{font-family:system-ui,sans-serif;background:#080A23;color:#fff;max-width:22rem;margin:2rem auto;padding:0 1rem}
h2{color:#FCE4B6}
p{color:#B8BBD9}
input,button{width:100%;margin:.4rem 0;padding:.7rem;box-sizing:border-box;font-size:1rem;border-radius:.5rem}
input{background:#1A1E4D;color:#fff;border:1px solid #2a2f6b}
button{background:#EDA631;color:#080A23;border:0;font-weight:600}
#msg{min-height:1.2rem;white-space:pre-wrap;margin-top:.6rem}
</style></head><body>
<h2>Envoyer votre certificat</h2>
<p>Choisissez le fichier .p12 et saisissez son mot de passe. Il est envoyé directement à la TV, sur votre réseau local.</p>
<input type="file" id="file" accept=".p12,.pfx">
<input type="password" id="password" placeholder="Mot de passe du certificat">
<button id="send">Envoyer</button>
<div id="msg"></div>
<script>
document.getElementById('send').onclick = async () => {
  const file = document.getElementById('file').files[0];
  const msg = document.getElementById('msg');
  if (!file) { msg.textContent = 'Choisissez d’abord un fichier.'; return; }
  const bytes = new Uint8Array(await file.arrayBuffer());
  let bin = '';
  for (const b of bytes) bin += String.fromCharCode(b);
  msg.textContent = 'Envoi en cours…';
  try {
    const res = await fetch(location.pathname, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({p12Base64: btoa(bin), password: document.getElementById('password').value})
    });
    msg.textContent = res.ok ? 'Envoyé. Terminez sur la TV.' : (await res.text() || 'Échec de l’envoi. Réessayez.');
  } catch (e) {
    msg.textContent = 'La TV n’écoute plus. Recommencez depuis la TV.';
  }
};
</script>
</body></html>
''';
