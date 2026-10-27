# Skins en match (`outfit.kit`)

Le corps en match est dessiné en code (petit perso vu de profil). Une tenue se décrit pièce par pièce
dans la fiche du perso (`godot/data/game.json`, champ `outfit.kit`). Toutes les couleurs sont en `#rrggbb`.
L'image pleine taille du skin (profil, fond transparent) va dans `godot/art/skins/<id>.png` :
elle sert à l'écran Invoquer, à l'Aperçu et à l'apparition S++.

| Pièce | Champs | Valeurs |
|---|---|---|
| `top` | `color`, `panel` (plastron devant), `trim` (col croisé), `motif`, `motif_color`, `shoulders` | motif : `nuages`, `lunes` ; shoulders : `nues` |
| `sleeves` | `type`, `color`, `trim` | `kimono` (large et courte), `detachees`, `longues`, `courtes` |
| `forearm` | couleur | manchette du coude au poignet |
| `bracelet` | couleur | |
| `belt` | `color`, `tassels` (true/false) | ceinture de corde + pompons |
| `skirt` | `color`, `under` (2e couche), `trim` (ourlet), `len` (0.15 à 0.4), `motif` | tunique ou jupe |
| `sash` | `color`, `len` (0.3 à 0.8) | pan de tissu qui flotte derrière |
| `shorts` | `color`, `len` (0.3 court … 0.9 cycliste), `stripe` | |
| `thigh_strap` | couleur | sangle de cuisse |
| `socks`, `sock_len` | couleur, 0.15 à 0.5 | |
| `shoes` | `["couleur", "semelle/accent"]` | |
| `ribbons` | `color`, `len` (1 à 3.5), `n` (1 ou 2) | rubans dans les cheveux |
| `hairpin` | `lune` | |

La couleur d'équipe reste visible sur le brassard et l'anneau au sol.
