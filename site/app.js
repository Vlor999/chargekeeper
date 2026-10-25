(function () {
  var REPO = 'Vlor999/jauge';
  var BREW = 'brew install --cask vlor999/tap/jauge';
  var APPLE = '<path d="M16.4 12.7c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.8-1.8-3.4-1.8-1.4-.1-2.8.9-3.5.9s-1.8-.8-3-.8c-1.5 0-3 .9-3.8 2.3-1.6 2.8-.4 7 1.2 9.3.8 1.1 1.7 2.4 2.9 2.3 1.2 0 1.6-.7 3-.7s1.8.7 3 .7 2-1.1 2.8-2.2c.9-1.3 1.2-2.5 1.2-2.6 0 0-2.4-.9-2.4-3.9zM14.1 5.8c.6-.8 1.1-1.9.9-3-.9 0-2.1.6-2.7 1.4-.6.7-1.1 1.8-1 2.9 1.1.1 2.2-.5 2.8-1.3z"/>';
  // FR strings; English stays in index.html (data-i18n / data-i18n-html / data-i18n-attr="attr:key").
  var FR = {
    skip: 'Aller au téléchargement', features: 'Fonctions', dl: 'Télécharger', nav: 'Principal', lang: 'Langue',
    tagline: 'La batterie de votre MacBook, <span class="accent">au bon niveau.</span>',
    lead: 'Limite de charge, décharge, calibration et planification, depuis la barre des menus. Gratuit, open source, sans compte.',
    how: 'Comment ça marche', heroMeta: 'Apple silicon · macOS 14 ou plus · Licence MIT',
    heroSr: 'Aperçu du menu Jauge : batterie à 80 %, charge suspendue à la limite, curseur de limite, boutons de décharge et de charge à 100 %, et flux de puissance de l\'adaptateur vers le MacBook.',
    clock: 'dim. 25 oct. 09:41', paused: 'Charge suspendue', hw: 'Matériel 79 % · 29,1 °C', limit: 'Limite de charge',
    discharge: 'Décharge', full: 'Charger à 100 %', calib: 'Démarrer la calibration', pause: 'Suspendre', flow: 'Flux de puissance',
    mockcap: 'Aperçu, données fictives.',
    first: 'Au premier lancement, macOS vous demande d\'autoriser le <strong>service en arrière-plan</strong> de Jauge dans Réglages Système &gt; Général &gt; Ouverture. C\'est ce service qui pilote la batterie.',
    flead: 'Garder la batterie entre 50 et 80 % ralentit son usure. Jauge s\'en charge, même quand l\'app est fermée.',
    f1t: 'Limite de charge', f1: 'Choisissez une limite de 20 à 100 %. Sur macOS 26 et plus, la limite intégrée du Mac prend le relais dès 80 %.',
    f2t: 'Décharge', f2: 'Le Mac tourne sur batterie même branché, jusqu\'à votre limite. À la main ou automatiquement.',
    f3t: 'Plage de repos', f3: 'La recharge ne reprend qu\'une fois le niveau sous une plage, au lieu de compléter à chaque pour cent.',
    f4t: 'Calibration', f4: 'Un cycle complet : 100 %, descente à 10 %, retour à 100 %, une heure de repos, puis votre limite.',
    f5t: 'Protection thermique', f5: 'La charge s\'arrête au-dessus de la température choisie, vérifiée par fenêtres de cinq minutes.',
    f6t: 'Flux de puissance', f6: 'Les watts de l\'adaptateur et de la batterie vers le Mac, en direct. Alerte si l\'adaptateur est trop faible.',
    f7t: 'Planification', f7: 'Changer la limite, calibrer, charger à 100 % ou basculer l\'Économie d\'énergie à heure fixe. Les tâches manquées peuvent s\'exécuter au réveil.',
    f8t: 'Raccourcis et Terminal', f8: 'Toutes les actions dans l\'app Raccourcis, et <code>jaugectl</code> en ligne de commande.',
    more: 'Et aussi', c1: 'Charge à 100 % ponctuelle', c2: 'Couleurs de la LED MagSafe', c3: 'Rester éveillé jusqu\'à la limite',
    c4: 'Niveau figé pendant la veille', c5: 'Pourcentage matériel de la batterie', c6: 'Fonctionne pour tous les comptes',
    c7: 'Anglais et français', c8: '0 % de processeur menu fermé',
    q6: 'Combien de ressources utilise-t-elle ?',
    a6: 'Menu fermé, l\'app n\'utilise pas de processeur et environ 20 à 30 Mo de mémoire ; le service environ 30 Mo. L\'animation du flux de puissance ne tourne que lorsqu\'elle est à l\'écran.',
    q7: 'Comment utiliser jaugectl dans le Terminal ?',
    a7: 'Homebrew l\'ajoute à votre <code>PATH</code>. Avec le .dmg, créez le lien une fois : <code>sudo ln -s /Applications/Jauge.app/Contents/MacOS/jaugectl /usr/local/bin/jaugectl</code>, puis <code>jaugectl status</code>.',
    privacy: 'Confidentialité',
    pv: 'Jauge ne va sur Internet que pour chercher les mises à jour sur GitHub. Pas de compte, pas de télémétrie, rien ne quitte votre Mac.',
    pvl: 'Lire le code (licence MIT)', faq: 'Questions fréquentes',
    q1: 'Pourquoi Jauge a-t-elle besoin d\'un service en arrière-plan ?',
    a1: 'Modifier la charge de la batterie demande des droits administrateur. Un petit service tourne en root et ne fait que ça ; l\'app de la barre des menus lui parle par un socket local réservé aux administrateurs. Vous l\'autorisez une seule fois dans Réglages Système.',
    q2: 'Quels Mac sont compatibles ?', a2: 'Les MacBook Apple silicon, sous macOS 14 ou plus. Les Mac Intel ne sont pas pris en charge.',
    q3: 'Comment marche une limite sous 80 % sur macOS 26 et plus ?',
    a3: 'La limite intégrée de macOS s\'arrête à 80 %. En dessous, Jauge alterne batterie et adaptateur autour de votre limite : le niveau varie d\'environ 1 %.',
    q4: 'Comment se font les mises à jour ?',
    a4: 'Jauge vérifie la dernière version GitHub au démarrage, puis toutes les 6 heures. Chaque mise à jour est signée : l\'app vérifie la signature, l\'installe et redémarre son service.',
    q5: 'Comment la désinstaller ?', a5: 'Quittez Jauge et mettez-la à la corbeille. Avec Homebrew : <code>brew uninstall --zap jauge</code>.',
    indep: 'Jauge · projet indépendant, non affilié à Apple', rels: 'Versions', bug: 'Signaler un bug', mit: 'Licence MIT'
  };
  var lang, EN = {};
  try { lang = localStorage.getItem('lang'); } catch (e) {}
  if (lang !== 'fr' && lang !== 'en') lang = /^fr/i.test(navigator.language || '') ? 'fr' : 'en';
  function t(fr, en) { return lang === 'en' ? en : fr; }
  // First call per key stores the English original; then pick EN or FR.
  function str(k, cur) { if (!(k in EN)) EN[k] = cur; return lang === 'fr' && FR[k] != null ? FR[k] : EN[k]; }
  function translate() {
    document.documentElement.lang = lang;
    document.querySelectorAll('[data-i18n]').forEach(function (el) { el.textContent = str(el.dataset.i18n, el.textContent); });
    document.querySelectorAll('[data-i18n-html]').forEach(function (el) { el.innerHTML = str(el.dataset.i18nHtml, el.innerHTML); });
    document.querySelectorAll('[data-i18n-attr]').forEach(function (el) {
      var p = el.dataset.i18nAttr.split(':');
      el.setAttribute(p[0], str(p[1], el.getAttribute(p[0])));
    });
    document.querySelectorAll('.lang button').forEach(function (b) { b.setAttribute('aria-pressed', b.lang === lang); });
  }
  var meta = document.getElementById('release-meta');
  var box = document.getElementById('downloads');
  var heroDl = document.getElementById('hero-dl'), heroVer = document.getElementById('hero-ver');
  var rel; // undefined while loading, null on error; kept so a language switch re-renders without refetching

  function fail() {
    meta.textContent = t('Pas encore de version publiée.', 'No release published yet.');
    box.innerHTML = '';
    var a = document.createElement('a');
    a.className = 'btn';
    a.href = 'https://github.com/' + REPO + '/releases';
    a.textContent = t('Voir les versions sur GitHub', 'See releases on GitHub');
    box.appendChild(a);
  }

  function brew() {
    var d = document.createElement('div');
    d.className = 'code';
    var c = document.createElement('code');
    c.textContent = BREW;
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'copy';
    b.textContent = t('Copier', 'Copy');
    b.addEventListener('click', function () {
      if (navigator.clipboard) navigator.clipboard.writeText(c.textContent).then(function () {
        b.textContent = t('Copié', 'Copied');
        setTimeout(function () { b.textContent = t('Copier', 'Copy'); }, 1500);
      }, function () {});
    });
    d.appendChild(c);
    d.appendChild(b);
    return d;
  }

  function render() {
    heroDl.href = '#download';
    heroDl.textContent = t('Télécharger', 'Download');
    heroVer.textContent = '';
    if (rel === undefined) { meta.textContent = t('Recherche de la dernière version…', 'Looking up the latest release…'); return; }
    if (!rel) return fail();
    var dmg = (rel.assets || []).filter(function (a) { return /\.dmg$/.test(a.name); })[0];
    if (!dmg) return fail();
    var ver = rel.tag_name || rel.name;
    var date = rel.published_at ? new Date(rel.published_at).toLocaleDateString(t('fr-FR', 'en-US'), { day: 'numeric', month: 'long', year: 'numeric' }) : '';
    meta.textContent = 'Version ' + ver + (date ? ' · ' + date : '');
    heroVer.textContent = ver + ' · ';
    box.innerHTML = '';
    var d = document.createElement('div');
    d.className = 'dl on';
    d.innerHTML = '<h3><svg viewBox="0 0 24 24" aria-hidden="true">' + APPLE + '</svg>macOS</h3>';
    var a = document.createElement('a');
    a.className = 'btn primary';
    a.href = dmg.browser_download_url;
    a.textContent = t('Télécharger pour Apple silicon', 'Download for Apple silicon');
    var n = document.createElement('small');
    n.textContent = t('✓ Signée et notarisée par Apple · mises à jour automatiques', '✓ Signed and notarized by Apple · automatic updates');
    d.appendChild(a);
    d.appendChild(n);
    d.appendChild(brew());
    box.appendChild(d);
    heroDl.href = dmg.browser_download_url;
    heroDl.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true">' + APPLE + '</svg>';
    heroDl.appendChild(document.createTextNode(t('Télécharger pour macOS', 'Download for macOS')));
  }

  function setLang(l) {
    lang = l;
    translate();
    render();
  }
  setLang(lang);
  document.querySelectorAll('.lang button').forEach(function (b) {
    b.addEventListener('click', function () {
      try { localStorage.setItem('lang', b.lang); } catch (e) {}
      setLang(b.lang);
    });
  });
  fetch('https://api.github.com/repos/' + REPO + '/releases/latest', { headers: { Accept: 'application/vnd.github+json' } })
    .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
    .then(function (r) { rel = r; render(); })
    .catch(function () { rel = null; render(); });
})();
