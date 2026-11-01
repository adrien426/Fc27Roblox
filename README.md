# FC27 Roblox

La version Roblox de [FC27 / Foot Arena](https://github.com/adrien426/Fc27), écrite en Luau.

## Jouer à la dernière version

1. Ouvre la page [Releases](https://github.com/adrien426/Fc27Roblox/releases) du dépôt.
2. Télécharge **Fc27.rbxlx** :
   - **FC27 Roblox** (`latest`) : la version de la branche `main` ;
   - **preview-…** : la version en test d'une branche de travail.
3. Ouvre le fichier dans **Roblox Studio** (Fichier > Ouvrir), puis appuie sur **Jouer**.
4. Pour jouer à plusieurs : dans Studio, **Test > Clients et serveurs** (2 joueurs ou plus), ou publie le jeu sur Roblox (Fichier > Publier sur Roblox).

Le fichier est reconstruit automatiquement par GitHub à chaque envoi de code.

## Le jeu

- Onze contre onze sur un terrain aux vraies dimensions (105 × 68 m) dans un stade construit par script : pelouse rayée, lignes, buts avec filets, tribunes et public, panneaux, projecteurs.
- Chaque joueur Roblox incarne un footballeur de son équipe (Rouges ou Bleus, équilibrées automatiquement). Les joueurs ordinateur complètent les deux équipes à 11 et les gardiens sont toujours gérés par l'ordinateur.
- Le serveur arbitre le match : physique du ballon reprise du jeu web (effet, frottements, rebonds), possession, tacles, sorties (touche, corner, six mètres), buts, poteaux, mi-temps et fin de match (90 minutes en 6 minutes).

## Commandes

| Action | Clavier | Manette | Tactile |
| --- | --- | --- | --- |
| Courir | ZQSD / WASD | Stick gauche | Joystick |
| Passe (vers le meilleur coéquipier dans la direction) | J | A | Passe |
| Tir (maintenir = plus fort) | K | B | Tir |
| Lob (maintenir = plus loin et plus haut) | I | Y | Lob |
| Passe en profondeur | L | LB | — |
| Tacle | E | X | Tacle |
| Sprint (endurance) | Maj | RB | Sprint |
| Saut (tête) | Espace | — | Saut |
| Caméra TV | C | Select | 🎥 |

## Modèles, animations et sons du jeu web

Le jeu reprend les fichiers du jeu web : le footballeur Ch38 (`player.glb`), le stade (`stadium.glb`), les ballons (`balls.glb`), les 40 animations Mixamo et les sons. Roblox ne lit pas ces fichiers directement : les modèles et les sons doivent être **uploadés sur Roblox** (avec une clé Open Cloud), puis le jeu les charge par leur numéro (`src/shared/AssetIds.luau`). Tant qu'un fichier n'est pas uploadé (numéro 0), le jeu garde sa version construite en code.

| Étape | Commande (dans `scripts/`, après `npm ci`) | Résultat |
| --- | --- | --- |
| Préparer les modèles | `node prepare-models.mjs` | `assets/build/*.glb` : sans compression Draco, chaque mesh sous 20 000 triangles (limite Roblox), poteaux du stade retirés |
| Convertir les animations | `node build-anims.mjs` | `src/shared/Clips/*.luau` : un module par clip, joué sur les os du modèle par `src/shared/Skeleton.luau` |
| Pose de repos du joueur | `node build-rest.mjs` | `src/shared/PlayerRest.luau` : rotation de repos de chaque os de `player.glb` et hauteur des hanches, pour que les clips tournent les os comme dans le jeu web |
| Uploader | `node upload-assets.mjs` | modèles et sons sur Roblox, numéros dans `src/shared/AssetIds.luau` et `assets/uploaded.json` |
| Publier une version | `node publish-place.mjs --release preview-<branche>` | le `Fc27.rbxlx` construit par GitHub publié dans une expérience Roblox |

Variables pour l'upload et la publication : `ROBLOX_API_KEY` (clé Open Cloud : droits *assets* lecture/écriture et *universe-places* écriture), `ROBLOX_CREATOR_USER_ID` (ou `ROBLOX_CREATOR_GROUP_ID`), `ROBLOX_UNIVERSE_ID`, `ROBLOX_PLACE_ID`. Les modèles doivent appartenir au même compte (ou groupe) que l'expérience, sinon Roblox refuse de les charger dans le jeu.

Sources : `assets/source/` (copie des fichiers du jeu web ; `anims/base.json` contient les clips intégrés à son `index.html`, extraits par `scripts/extract-web-clips.mjs`).

## Organisation du code (Rojo)

```
src/shared/   Config (dimensions, équipes, formation), BallPhysics (physique du ballon),
              Skeleton (lecture des clips), Clips (animations converties), AssetIds (numéros Roblox)
src/server/   Match (arbitre, ballon, joueurs ordinateur), Pitch (stade), Rig (corps et maillots), Assets (modèles uploadés)
src/client/   Controls (commandes), BallView (affichage du ballon), Hud (score, messages, barres),
              Bodies (animations des joueurs), Sounds (sons)
```

## Travailler dans Roblox Studio avec Git

Le code dans `src/` est la référence : c'est lui qui est enregistré sur Git. Le fichier `.rbxlx` n'est qu'une copie construite à partir de ce code. Ce que tu changes directement dans Studio n'arrive donc pas sur Git tout seul. Rojo fait le lien entre les deux.

### Installation (une seule fois)

1. Installe [Rokit](https://github.com/rojo-rbx/rokit), puis dans le dossier du dépôt lance `rokit install` (installe Rojo 7.7.1, la même version que GitHub).
2. Installe le plugin Rojo dans Studio : `rojo plugin install`.
3. Conseillé : installe l'extension **Rojo** et **Luau Language Server** dans VS Code.

### Du code vers Studio (en direct)

1. Ouvre le dépôt dans VS Code, sur ta branche de travail.
2. Construis le jeu : `rojo build -o Fc27.rbxlx`, puis ouvre `Fc27.rbxlx` dans Studio.
3. Lance `rojo serve`, puis dans Studio **Plugins > Rojo > Connect**.
4. Chaque fichier enregistré dans VS Code est envoyé tout de suite dans Studio. Appuie sur **Jouer** pour tester.

### De Studio vers le code (syncback)

Ce que tu fais à la main dans Studio (modèles, décor, réglages, scripts modifiés) ne revient pas tout seul dans `src/`. Pour le récupérer :

1. Dans Studio, enregistre le jeu dans le même fichier : **Fichier > Enregistrer** (Ctrl+S) sur `Fc27.rbxlx`.
2. Dans le dossier du dépôt, lance `rojo syncback --input Fc27.rbxlx`, puis réponds `y`.
3. Regarde les fichiers changés, puis fais ton commit + push.

Ce que syncback récupère :

| Dans Studio | Arrive dans |
| --- | --- |
| Objets de **Workspace** (modèles, pièces, décor) | `src/workspace/` |
| Scripts de ReplicatedStorage > Shared, ServerScriptService > Server, StarterPlayerScripts > Client | `src/shared/`, `src/server/`, `src/client/` |
| Réglages de **Lighting**, **Players**, **StarterPlayer** | `default.project.json` |

À savoir :
- Le stade, les joueurs et le ballon sont créés par les scripts **au lancement du jeu**. Les changer pendant une partie ne sert à rien : ça disparaît à l'arrêt. Leurs réglages (vitesse, dimensions…) sont dans `src/shared/Config.luau`.
- La caméra et le Terrain de Workspace sont ignorés.
- Ne relance pas `rojo build -o Fc27.rbxlx` avant d'avoir fait le syncback : cela remplacerait ton fichier enregistré par la version du code.
- Ce qui n'est pas dans la liste ci-dessus (par exemple ServerStorage) n'est pas récupéré. Il faut d'abord l'ajouter dans `default.project.json`.

## Façon de travailler

| Branche | Ce qui se passe à chaque envoi (push) |
| --- | --- |
| branche de travail (`claude/…`, …) | le jeu est vérifié et construit, puis publié en release **preview-<branche>** (à ouvrir dans Studio) |
| `test` | déploiement automatique sur l'**expérience Roblox de test** (workflow *Deploy to Roblox*) |
| `main` | déploiement automatique sur l'**expérience Roblox de production**, et release `latest` |

1. Chaque changement est fait sur une branche de travail.
2. Une fois terminé, la branche est **fusionnée dans `test`** (`git merge`, jamais d'écrasement) : le jeu de test se met à jour tout seul.
3. Quand tout est bon en jeu, **`test` est fusionnée dans `main`** : la production se met à jour.

Le déploiement uploade d'abord les modèles et sons qui ont changé, puis pousse leurs numéros (`AssetIds.luau`, `assets/uploaded.json`) sur la branche déployée, dans un commit de `github-actions[bot]`. C'est pour cela qu'on passe de `test` à `main` par une fusion de `test`, sinon les assets seraient recréés.

Secrets du dépôt à créer une fois (Settings > Secrets and variables > Actions) :

| Secret | Valeur |
| --- | --- |
| `ROBLOX_API_KEY` | clé Open Cloud : *assets* lecture/écriture, *universe-places* écriture sur les deux expériences |
| `ROBLOX_CREATOR_USER_ID` | numéro du compte Roblox qui possède les deux expériences |
| `ROBLOX_TEST_UNIVERSE_ID`, `ROBLOX_TEST_PLACE_ID` | l'expérience de test |
| `ROBLOX_PROD_UNIVERSE_ID`, `ROBLOX_PROD_PLACE_ID` | l'expérience de production |

Un déploiement peut aussi être relancé à la main : onglet **Actions > Deploy to Roblox > Run workflow** (choisir `test` ou `main`).
