# SkySpike — prototype Godot

Un seul match 3v3 (15 points) pour comparer la fluidité avec la version web.
Physique, IA et commandes reprises de `index.html` (mêmes règles, mêmes stats).

- `scripts/game.gd` : moteur (physique du ballon, touches, IA, service, score)
- `scripts/view.gd` : rendu (terrain, joueurs, ballon, traînées, effets)
- `scripts/ui.gd` : HUD, commandes tactiles (joystick + SAUT/SMASH, RÉCEPTION, PLONGEON/FEINTE), menus
- `scripts/sfx.gd` : sons synthétisés au démarrage
- `data/roster.json` : persos et stats exportés depuis la version web (niveau 40, 3 étoiles)

L'APK est compilé par `.github/workflows/godot-apk.yml` (artifact `SkySpike-Godot-APK`), application séparée de SkySpike (`com.skyspike.godot`).

Tests en local : `godot --headless --path godot -- --sim 3` (matchs IA contre IA).

Polices : Anton et Barlow Condensed (SIL Open Font License, voir `fonts/OFL.txt`).
