# SkySpike — plan de la suite

État au 27/10/2026 : **build 20**. Match 3v3 jouable (IA + en ligne via relais MQTT), 32 persos (C → S++),
gacha avec bannières en données, pity et étincelle, écosystème social (amis, messages, clubs, classé Elo),
mises à jour sans réinstaller, écran Invoquer refait, skins S++ (Kaien, Liora).

Principes : **pas d'argent réel, pas de pay-to-win** — tout s'obtient en jouant. Chaque tâche se termine par
une vérification (`--check`, captures d'écran regardées, simulation) puis un push qui produit un build.

Légende : `[ ]` à faire · `[x]` fait · ⭐ priorité · (S/M/L) = taille approximative (session courte / moyenne / longue).

---

## Phase 0 — Stabilité (avant tout le reste)

- [ ] ⭐ **0.1 Recette de la build 20 sur téléphone** (S, Djebril) — Invoquer, Persos, apparition S++, tenues en match,
      sur téléphone **et** Z Fold 6 ouvert/fermé. Noter chaque bug avec une capture.
- [x] ⭐ **0.2 Chasse aux bugs automatique** (M) — lancer `--sim 50`, `--bot`, `--ui`, `--socui`, `--sppmatch` ;
      corriger toute erreur ou avertissement GDScript dans les journaux ; vérifier qu'aucun écran ne déborde en 2340×1080
      ni en 2208×1768. *Fini quand* : zéro `SCRIPT ERROR`, captures propres sur les deux formats.
- [ ] ⭐ **0.3 En ligne fiable** (L) — monter un banc de test : deux clients Godot sans écran + un broker MQTT local
      (`amqtt`), avec perte de paquets (5 %, 15 %) et latence (80 ms, 200 ms) simulées.
      Mesurer : écart balle hôte/invité, désaccords de score, déconnexions. Corriger : reprise après coupure
      (reconnexion automatique 10 s, sinon victoire par forfait), score et fin de match confirmés par les deux côtés,
      indicateur de qualité réseau dans le HUD. *Fini quand* : 20 matchs de bout en bout sans désaccord à 15 % de perte.
- [ ] **0.4 Sauvegarde sûre** (S) — sauvegarde atomique (fichier temporaire + renommage), copie de secours,
      migration de version de sauvegarde testée (ancienne save → nouvelle build).

## Phase 1 — Économie et progression (donner un sens au gacha)

- [ ] ⭐ **1.1 Vraies monnaies** (M) — remplacer « ∞ pièces / ∞ ballons » par :
      **Tickets de recrutement** (1 tirage = 1 ticket, déjà affichés sur les boutons) et **Éclats** (monnaie douce :
      niveaux, places de boîte). Gains : victoire/défaite, première victoire du jour, quêtes, paliers du pass.
      Doublons au-delà de 5★ → Éclats. Afficher les soldes en haut, animation de gain en fin de match.
      Prévoir un réglage « mode bac à sable » (tout illimité) dans Options pour les tests.
- [ ] **1.2 Quêtes** (M) — 3 quêtes du jour (ex. « gagne 2 matchs », « réussis 5 smashs parfaits »),
      3 de la semaine, connexion quotidienne (7 jours, le 7e = 5 tickets). Écran dans l'onglet Équipe ou nouvel onglet.
- [ ] **1.3 Pass de saison gratuit** (M) — 30 paliers d'XP sur 4 semaines : tickets, éclats, cadres de profil,
      un skin au palier 30. Données dans `data/seasons/<id>.json`, même principe que les bannières.
- [ ] **1.4 Progression des persos** (M) — XP de match par perso, coût des niveaux en éclats, éveil aux étoiles
      (5★ débloque une variante d'ultime ou une pose de victoire). Écran détail du perso mis à jour.
- [ ] **1.5 Équilibrage chiffré** (S) — script de simulation qui sort un tableau de taux de victoire par perso et
      par rang (1 000 matchs). Objectif : S++ fort mais battable par une bonne équipe S+.

## Phase 2 — Skins et cosmétiques (ce que tu veux pousser)

- [ ] ⭐ **2.1 Skins séparés des persos** (M) — liste `data/skins/<skin_id>.json` : `char`, `name` (« Radiant Flow »),
      `kit` (format `data/SKINS.md`), image `art/skins/<skin_id>.png`. Un perso peut avoir plusieurs skins ;
      choix du skin dans l'écran détail du perso ; le skin équipé est utilisé en match, en invocation et dans le profil
      social (envoyé au serveur).
- [ ] **2.2 Bannière de skins** (M) — type de bannière `"kind": "skin"` (comme le « Skin Raffle » de ta référence) :
      récompenses vedettes (skin, icône, cadre, emote), garantie en 80 tirages.
- [ ] **2.3 Cabine d'essayage** (M) — dans l'Aperçu : le perso dessiné en grand avec la vraie vue de match qui
      enchaîne ses poses (attente, service, smash, célébration) pour juger le skin tel qu'il sera en jeu.
- [ ] **2.4 Outil d'import de skin** (S) — `tools/add_skin.py` : prend l'image GPT, détoure (rembg, modèle
      `isnet-anime`), recadre, réduit à 1000 px de haut, vérifie le JSON du kit, range les fichiers.
      + Prompt ChatGPT type dans `data/SKINS.md` (image de profil en pied, fond uni, + description du kit).
- [ ] **2.5 Plus de pièces de kit** (M) — capuche, cape, jambières, gants, lunettes de sport, coiffures
      supplémentaires (tresses, chignon, cheveux courts en pointes), motifs (flammes, éclairs, étoiles, vagues).
      Vérifier chaque pièce en capture zoomée.
- [ ] **2.6 Animations personnelles** (M) — étendre `anim` : 3 célébrations, 2 services, entrée en match,
      pose de victoire sur l'écran de fin.

## Phase 3 — Gameplay

- [ ] ⭐ **3.1 Tutoriel jouable** (M) — 5 étapes guidées (déplacement, réception, passe, smash, contre)
      avec flèches et ralenti ; proposé au premier lancement, rejouable dans Options.
- [ ] **3.2 Timing visible** (S) — retour « PARFAIT / BON / RATÉ » sur réception et smash, petit ralenti sur parfait,
      vibration différente.
- [ ] **3.3 Synergies d'équipe** (M) — bonus si deux persos partagent un élément (soleil + lune = « Équilibre »),
      affichées dans l'écran Équipe ; ultime combiné quand les deux jauges sont pleines.
- [ ] **3.4 Nouveaux coups** (M) — attaque rapide (quick) au filet, attaque arrière, feinte de passe,
      service flottant vs service smashé (choix au moment du service).
- [ ] **3.5 Modes solo** (L) — Défis du jour (scénarios courts : « remonte 10-14 »), Tour céleste (20 étages
      de difficulté croissante, récompenses), mini-histoire de la bannière (3 matchs + dialogues avec les portraits).
- [ ] **3.6 IA plus humaine** (M) — personnalités (agressive, défensive, feinteuse), erreurs crédibles,
      difficulté qui s'adapte légèrement en mode facile.

## Phase 4 — Social et en ligne

- [ ] **4.1 Saisons classées** (M) — remise à zéro douce toutes les 4 semaines, rangs (Bronze → Céleste),
      récompenses de fin de saison (cadre, titre, tickets).
- [ ] **4.2 Match amical entre amis plus simple** (S) — inviter depuis la liste d'amis en un clic (déjà en partie là),
      revanche immédiate à la fin.
- [ ] **4.3 Partie vocale** (L, à préciser par Djebril) — deux options :
      a) **répliques audio des persos** (fichiers courts par perso : invocation, ultime, victoire) ;
      b) **chat vocal entre amis** dans le salon / pendant le match (WebRTC, permission micro → monter `min_apk`).
- [ ] **4.4 Sécurité du social** (S) — signaler / bloquer, filtre de mots, limite de messages par minute côté serveur.
- [ ] **4.5 Sauvegarde en ligne** (M) — lier la sauvegarde au compte du serveur pour la récupérer sur un autre
      téléphone (Z Fold ↔ téléphone), avec code de récupération.

## Phase 5 — Contenu régulier

- [ ] **5.1 Rythme de bannières** (S chaque) — une bannière toutes les 2-3 semaines : fiche JSON + key art + logo
      + 1 ou 2 persos (portrait, image d'action, skin pleine taille, kit). Process documenté dans
      `data/banners/README.md` ; vérifier avec `--bannerui`.
- [ ] **5.2 Nouveaux persos S / S+** (S chaque) — viser 40 persos d'ici la fin de l'année.
- [ ] **5.3 Arènes** (M) — 3 stades (plage au coucher du soleil, gymnase de nuit, temple céleste) choisis
      aléatoirement ou liés à la bannière.

## Phase 6 — Finition et publication

- [ ] **6.1 Performance** (S) — `--bench` : 60 i/s sur téléphone milieu de gamme, mode économie (30 i/s) dans Options.
- [ ] **6.2 Poids de l'APK** (S) — compresser les images (WebP), objectif < 80 Mo.
- [ ] **6.3 Clé de signature de publication** (S) — keystore « release » dans les secrets GitHub (pas dans le dépôt).
- [ ] **6.4 Google Play test interne** (M) — fiche, captures, politique de confidentialité (le serveur stocke pseudo,
      amis, messages), classification d'âge, puis test fermé avec des amis.
- [ ] **6.5 Rapports de plantage** (S) — journal d'erreurs envoyé au serveur social (anonyme) pour voir les bugs
      des testeurs.

---

## Ordre conseillé jusqu'au 5 novembre (crédit cloud de 100 $)

Une session Claude Code = une tâche. Coller le prompt, laisser travailler, regarder les captures, tester sur le
téléphone, puis passer à la suivante.

| Jour | Tâches | Prompt à coller dans Claude Code |
|---|---|---|
| 27/10 | 0.1 (toi) puis 0.2 | « Lis CLAUDE.md et ROADMAP.md, fais la tâche 0.2, montre-moi les captures et publie. » |
| 28/10 | 0.3 | « Fais la tâche 0.3 de ROADMAP.md (en ligne fiable). Montre les mesures avant/après. » |
| 29/10 | 1.1 | « Fais la tâche 1.1 (vraies monnaies) en gardant un mode bac à sable dans Options. » |
| 30/10 | 2.1 + 2.4 | « Fais les tâches 2.1 puis 2.4. Utilise Kaien et Liora comme premiers skins. » |
| 31/10 | 3.1 + 3.2 | « Fais les tâches 3.1 et 3.2. » |
| 01/11 | 1.2 + 1.3 | « Fais les tâches 1.2 et 1.3. » |
| 02/11 | 2.3 + 2.5 | « Fais les tâches 2.3 et 2.5, avec captures zoomées de chaque pièce. » |
| 03/11 | 3.3 + 1.5 | « Fais les tâches 3.3 et 1.5, donne-moi le tableau d'équilibrage. » |
| 04/11 | 4.5 + 0.4 | « Fais les tâches 4.5 et 0.4. » |

À la fin de chaque tâche, Claude Code coche la case ici (`[x]`) dans le même commit.

## Comment bien utiliser Claude Code sur ce projet

- Toujours commencer par : « Lis CLAUDE.md et ROADMAP.md ».
- Demander les **captures d'écran** du résultat (les modes `--ui`, `--bannerui`, `--sppmatch` existent pour ça).
- Une tâche L peut prendre une session entière : ne pas en enchaîner deux.
- Si un bug vient du téléphone : envoyer la capture + le modèle (téléphone ou Z Fold, ouvert/fermé).
- Pour les images (persos, skins, bannières) : ChatGPT fait l'image, Claude Code l'intègre et vérifie.
