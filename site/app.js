(function () {
  var REPO = 'Vlor999/chargekeeper';
  var BREW = 'brew install --cask vlor999/tap/chargekeeper';
  var DOWNLOAD = '<path d="M11 3h2v9.6l3.3-3.3 1.4 1.4-5.7 5.7-5.7-5.7 1.4-1.4 3.3 3.3zM4 18h16v2H4z"/>';
  var LAPTOP = '<path fill-rule="evenodd" d="M5 4h14a1 1 0 0 1 1 1v10H4V5a1 1 0 0 1 1-1zm1 2v7h12V6zM1 16h22v1a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2z"/>';
  // FR strings; English stays in index.html (data-i18n / data-i18n-html / data-i18n-attr="attr:key").
  var FR = {
    skip: 'Aller au téléchargement', features: 'Fonctions', dl: 'Télécharger', nav: 'Principal', lang: 'Langue',
    tagline: 'La batterie de votre MacBook, <span class="accent">au bon niveau.</span>',
    lead: 'Limite de charge, décharge, calibration et planification, depuis la barre des menus. Gratuit, open source, sans compte.',
    how: 'Comment ça marche', heroMeta: 'Apple silicon · macOS 14 ou plus · Licence MIT',
    heroSr: 'Aperçu du menu ChargeKeeper : batterie à 80 %, charge suspendue à la limite, curseur de limite, boutons de décharge et de charge à 100 %, et flux de puissance de l\'adaptateur vers le MacBook.',
    clock: 'dim. 25 oct. 09:41', paused: 'Charge suspendue', hw: 'Matériel 79 % · 29,1 °C', limit: 'Limite de charge',
    discharge: 'Décharge', full: 'Charger à 100 %', calib: 'Démarrer la calibration', pause: 'Suspendre', flow: 'Flux de puissance',
    mockcap: 'Aperçu, données fictives.',
    first: 'Au premier lancement, macOS vous demande d\'autoriser le <strong>service en arrière-plan</strong> de ChargeKeeper dans Réglages Système &gt; Général &gt; Ouverture. C\'est ce service qui pilote la batterie.',
    flead: 'Garder la batterie entre 50 et 80 % ralentit son usure. ChargeKeeper s\'en charge, même quand l\'app est fermée.',
    f1t: 'Limite de charge', f1: 'Choisissez une limite de 20 à 100 %. Sur macOS 26 et plus, la limite intégrée du Mac prend le relais dès 80 %.',
    f2t: 'Décharge', f2: 'Le Mac tourne sur batterie même branché, jusqu\'à votre limite. À la main ou automatiquement.',
    f3t: 'Plage de repos', f3: 'La recharge ne reprend qu\'une fois le niveau sous une plage, au lieu de compléter à chaque pour cent.',
    f4t: 'Calibration', f4: 'Un cycle complet : 100 %, descente à 10 %, retour à 100 %, une heure de repos, puis votre limite.',
    f5t: 'Protection thermique', f5: 'La charge s\'arrête au-dessus de la température choisie, vérifiée par fenêtres de cinq minutes.',
    f6t: 'Flux de puissance', f6: 'Les watts de l\'adaptateur et de la batterie vers le Mac, en direct. Alerte si l\'adaptateur est trop faible.',
    f7t: 'Planification', f7: 'Changer la limite, calibrer, charger à 100 % ou basculer l\'Économie d\'énergie à heure fixe. Les tâches manquées peuvent s\'exécuter au réveil.',
    f8t: 'Raccourcis et Terminal', f8: 'Toutes les actions dans l\'app Raccourcis, et <code>chargekeeperctl</code> en ligne de commande.',
    more: 'Et aussi', c1: 'Charge à 100 % ponctuelle', c2: 'Couleurs de la LED MagSafe', c3: 'Rester éveillé jusqu\'à la limite',
    c4: 'Niveau figé pendant la veille', c5: 'Pourcentage matériel de la batterie', c6: 'Fonctionne pour tous les comptes',
    c7: 'Anglais et français', c8: '0 % de processeur menu fermé',
    q6: 'Combien de ressources utilise-t-elle ?',
    a6: 'Menu fermé, l\'app n\'utilise pas de processeur et environ 20 à 30 Mo de mémoire ; le service environ 30 Mo. L\'animation du flux de puissance ne tourne que lorsqu\'elle est à l\'écran.',
    q7: 'Comment utiliser chargekeeperctl dans le Terminal ?',
    a7: 'Homebrew l\'ajoute à votre <code>PATH</code>. Avec le .dmg, créez le lien une fois : <code>sudo ln -s /Applications/ChargeKeeper.app/Contents/MacOS/chargekeeperctl /usr/local/bin/chargekeeperctl</code>, puis <code>chargekeeperctl status</code>.',
    privacy: 'Confidentialité',
    pv: 'ChargeKeeper ne va sur Internet que pour chercher les mises à jour sur GitHub. Pas de compte, pas de télémétrie, aucune donnée personnelle collectée.',
    pvl: 'Lire le code (licence MIT)', faq: 'Questions fréquentes',
    q1: 'Pourquoi ChargeKeeper a-t-il besoin d\'un service en arrière-plan ?',
    a1: 'Modifier la charge de la batterie demande des droits administrateur. Un petit service tourne en root et ne fait que ça ; l\'app de la barre des menus lui parle par un socket local réservé aux administrateurs. Vous l\'autorisez une seule fois dans Réglages Système.',
    q2: 'Quels Mac sont compatibles ?', a2: 'Les MacBook Apple silicon, sous macOS 14 ou plus. Les Mac Intel ne sont pas pris en charge.',
    q3: 'Comment marche une limite sous 80 % sur macOS 26 et plus ?',
    a3: 'La limite intégrée de macOS s\'arrête à 80 %. En dessous, ChargeKeeper alterne batterie et adaptateur autour de votre limite : le niveau varie d\'environ 1 %.',
    q4: 'Comment se font les mises à jour ?',
    a4: 'ChargeKeeper vérifie la dernière version GitHub au démarrage, puis toutes les 6 heures. Chaque mise à jour est signée : l\'app vérifie la signature, l\'installe et redémarre son service.',
    q5: 'Comment le désinstaller ?', a5: 'Quittez ChargeKeeper et mettez-le à la corbeille. Avec Homebrew : <code>brew uninstall --zap chargekeeper</code>.',
    indep: 'ChargeKeeper · projet indépendant, non affilié à Apple', rels: 'Versions', bug: 'Signaler un bug', mit: 'Licence MIT',
    legal: 'Mentions légales',
    lg1: '<strong>Éditeur.</strong> Vlor999, particulier, éditeur non professionnel. Contact : <a href="https://github.com/Vlor999/chargekeeper/issues">tickets GitHub</a>.',
    lg2: '<strong>Hébergeur.</strong> GitHub, Inc., 88 Colin P. Kelly Jr. Street, San Francisco, CA 94107, États-Unis.',
    lg3: '<strong>Confidentialité.</strong> L\'app ne contacte que GitHub, pour chercher les mises à jour : GitHub voit votre adresse IP et votre version de macOS dans cette requête. Pas de compte, pas de télémétrie. Ce site est hébergé par GitHub Pages, qui journalise les visites (voir la <a href="https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement">déclaration de confidentialité de GitHub</a>). Il récupère le dernier numéro de version auprès de l\'API GitHub, ne dépose aucun cookie et garde la langue choisie dans le stockage local de votre navigateur. Les polices sont servies par ce site.',
    lg4: '<strong>Avertissement.</strong> ChargeKeeper est fourni tel quel, sans aucune garantie (licence MIT). Il utilise des interfaces de macOS non documentées, susceptibles de changer. Utilisation à vos risques.',
    lg5: '<strong>Marques.</strong> Apple, Mac, MacBook, MagSafe et macOS sont des marques d\'Apple Inc., déposées aux États-Unis et dans d\'autres pays et régions. ChargeKeeper est un projet indépendant, ni affilié à Apple ni approuvé par Apple.'
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
    d.innerHTML = '<h3><svg viewBox="0 0 24 24" aria-hidden="true">' + LAPTOP + '</svg>macOS</h3>';
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
    heroDl.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true">' + DOWNLOAD + '</svg>';
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
