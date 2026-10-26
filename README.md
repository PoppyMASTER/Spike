# SkySpike

Jeu de volley 3v3 (web + APK Android).

- `index.html` : le jeu. **Chaque push de ce fichier sur `main` met à jour l'appli automatiquement** (au prochain lancement, avec internet). Pas besoin de réinstaller.
- `app/loader.html` : le lanceur embarqué dans l'APK. Il télécharge la dernière version du jeu, la garde pour jouer hors connexion, et utilise la copie embarquée si rien n'est disponible.
- `app/debug.keystore` : clé de signature de test fixe, pour que les nouveaux APK s'installent par-dessus l'ancien.
- `.github/workflows/creer-apk.yml` : compile l'APK (onglet Actions → artifact `SkySpike-APK`). Il ne se relance que si `app/` ou le workflow changent, ou à la main via « Run workflow ».
