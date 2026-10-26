# SkySpike

Jeu de volley 3v3 (web + APK Android).

- `index.html` : le jeu. **Chaque push de ce fichier sur `main` met à jour l'appli automatiquement** (au prochain lancement, avec internet). Pas besoin de réinstaller.
- `app/loader.html` : le lanceur embarqué dans l'APK. Il télécharge la dernière version du jeu, la garde pour jouer hors connexion, et utilise la copie embarquée si rien n'est disponible.
- `app/debug.keystore` : clé de signature de test fixe, pour que les nouveaux APK s'installent par-dessus l'ancien.
- `.github/workflows/creer-apk.yml` : compile l'APK (onglet Actions → artifact `SkySpike-APK`). Il ne se relance que si `app/` ou le workflow changent, ou à la main via « Run workflow ».

## Portraits illustrés

Le jeu charge automatiquement `art/portraits/<id>.png` s'ils existent, sinon il garde le portrait dessiné par code.

- **Où :** dossier `art/portraits/` du dépôt, un fichier par perso, nom = identifiant en minuscules sans accent :
  `vex, kira, mira, bram, jun, noa, ines, tarek, mei, dario, amara, yanis, yuki, enzo, hugo, leo, sami, zoe, lina, kenji, theo, max, remy, eva, paul, jade`
- **Format :** PNG carré (1024×1024 conseillé, 512×512 minimum), personnage en buste de face, **fond transparent** (le jeu ajoute le fond aux couleurs du rang). Garder la tête entière dans le cadre, centrée dans le haut de l'image.
- **Poids :** idéalement moins de 1 Mo par image.
- **Mise à jour :** dès que l'image est sur `main`, elle apparaît dans l'appli au lancement suivant (compter jusqu'à 5 minutes de cache GitHub). Les images sont gardées sur le téléphone pour jouer hors connexion. Supprimer un fichier remet le portrait dessiné.
- **Utilisées dans :** cartes PERSOS, équipe, adversaires, invocation et présentations des S/S+.

## Son

Effets et musiques sont générés par le jeu (aucun fichier audio). Réglages séparés effets / musique avec volume dans le menu pause ; le son se coupe quand l'appli passe en arrière-plan.
