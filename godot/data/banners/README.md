# Bannières (template)

Une bannière = des données, aucun code :

- `godot/data/banners/<id>.json` : la fiche (titre, dates, taux, garanties, étincelle, persos vedettes, effets d'invocation).
- `godot/art/banners/<id>_key.png` (16:9) et `<id>_logo.png` (transparent).
- Persos : fiche ajoutée à `godot/data/game.json` (ROSTER), portrait `godot/art/<id>.png`,
  image d'action `godot/art/action/<id>.png`. Champs `outfit`, `anim`, `voice` = tenue, animations et répliques en match.

Le jeu affiche automatiquement chaque bannière entre `start` et `end` (onglet dans INVOQUER).
Format complet : voir le prompt ChatGPT « matériel de bannière ».
