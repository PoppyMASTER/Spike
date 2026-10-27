# SkySpike — contexte pour Claude Code

Jeu gacha de volley 3v3 (style « The Spike », persos originaux) pour Android, fait avec **Godot 4.7.2**.
Le propriétaire (Djebril) parle français : réponses, textes du jeu et messages de commit en français.
Le plan de travail est dans `ROADMAP.md` : prendre la prochaine tâche non cochée, sauf demande contraire.

## Où est quoi

- `godot/` : le jeu actuel (le dossier `index.html` / `app/` à la racine est l'ancienne version web, ne plus y toucher).
  - `scripts/` : tout le code (UI construite en code, pas de scènes à part `main.tscn`).
    - Autoloads (ordre verrouillé) : `Updater, DB, Save, Sfx, Kit, Art, Net`.
    - `game.gd` (règles, physique, IA), `view.gd` (rendu du match : squelette procédural, tenues `outfit.kit`),
      `hud.gd`, `match.gd`, `app.gd` (navigation), `screens/*.gd` (Équipe, Invoquer, Persos, Jouer, Social),
      `summon_fx.gd` (animation d'invocation), `social.gd` (client du serveur, nœud `Kit.soc`), `net.gd` (en ligne MQTT),
      `ui_draw.gd` (aides de dessin).
  - `data/game.json` : rangs, taux, ROSTER (fiches persos), difficultés… `data/banners/*.json` : bannières.
    `data/SKINS.md` : format des tenues en match. `data/banners/README.md` : format des bannières.
  - `art/` : portraits `<id>.png`, `action/`, `skins/` (pleine taille détourée), `banners/` (`<id>_key.png`, `<id>_logo.png`).
- `server/` : serveur social Cloudflare Worker + D1 (`src/index.js`, `schema.sql`, `wrangler.toml`).
- `.github/workflows/godot-apk.yml` : à chaque push sur `main` touchant `godot/**` → compile l'APK + le paquet
  de mise à jour, publie la release `godot-latest` (titre « SkySpike Godot build N »), déploie le serveur.

## Règles à ne jamais casser

1. **Mises à jour sans réinstaller** : les téléphones chargent `update.pck` (scripts + data + art) par-dessus l'APK.
   - Ne jamais ajouter / retirer / réordonner un autoload, ni ajouter une permission Android, sans monter
     `godot/min_apk.txt` (le paquet sera alors refusé par les vieux APK, qui proposeront de réinstaller).
   - `godot/autoloads.lock` est vérifié par la CI. Préférer créer un nœud enfant (comme `Kit.soc`).
   - Garder `export_presets.cfg` → `include_filter` à jour si on ajoute un dossier de données non importé (json, txt…).
2. **Textures dessinées en `_draw`** : les garder en cache (dictionnaire dans `Art`), sinon elles sont libérées
   avant le rendu et s'affichent en blanc.
3. **Classes internes GDScript** : elles ne voient pas les fonctions statiques de la classe englobante →
   passer par une constante `preload` (ex. `const U := preload("res://scripts/ui_draw.gd")`).
4. **Typage** : pas de `:=` sur une valeur `Variant` (dictionnaire JSON) → type explicite.
5. **Secrets** : jamais de jeton Cloudflare / GitHub dans le code, les logs ou le chat (ils sont dans les secrets GitHub).
6. Ne pas pousser de fichiers lourds inutiles (images > 1 Mo : réduire avec PIL avant).

## Vérifier avant de pousser

```bash
# Godot 4.7.2 (si absent) :
curl -fsSL -o /tmp/g.zip https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip && unzip -oq /tmp/g.zip -d /tmp && mv /tmp/Godot_v4.7.2-stable_linux.x86_64 ~/godot
cd godot
~/godot --headless --path . --import            # importer les nouvelles ressources
~/godot --headless --path . -- --check          # chaque script compile ("ok")
~/godot --headless --path . -- --sim 20         # 20 matchs IA contre IA, scores
# captures d'écran (Xvfb) — regarder les PNG avant de dire que c'est bon :
xvfb-run -a -s "-screen 0 1600x740x24" ~/godot --path . --rendering-driver opengl3 --resolution 1600x740 -- --ui /tmp/ui
#   autres modes : --bannerui DIR, --sppmatch DIR, --shot DIR, --socui DIR, --bench, --bot
```
Ajouter tout nouveau script à la liste de `--check` dans `scripts/main.gd`.
Tester aussi en 2208×1768 (Z Fold 6 ouvert, presque carré) et 2340×1080 (téléphone).

Serveur : `cd server && npx wrangler dev` pour tester en local ; les tests d'API se font avec `curl`.

## Publier

Commit sur `main` (message en français) → la CI compile. Vérifier :
`gh api 'repos/PoppyMASTER/Spike/actions/runs?per_page=1' -q '.workflow_runs[0] | .status + " " + (.conclusion // "")'`, puis
`gh api repos/PoppyMASTER/Spike/releases/tags/godot-latest -q .name` → nouveau numéro de build.
Le joueur reçoit la mise à jour en relançant l'app (deux lancements : téléchargement puis application).
