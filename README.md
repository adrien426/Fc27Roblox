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

## Organisation du code (Rojo)

```
src/shared/   Config (dimensions, équipes, formation), BallPhysics (physique du ballon)
src/server/   Match (arbitre, ballon, joueurs ordinateur), Pitch (stade), Rig (corps et maillots)
src/client/   Controls (commandes), BallView (affichage du ballon), Hud (score, messages, barres)
```

## Travailler dans Roblox Studio avec Git

Le code dans `src/` est la référence : c'est lui qui est enregistré sur Git. Le fichier `.rbxlx` n'est qu'une copie construite à partir de ce code. Ce que tu changes directement dans Studio n'arrive donc pas sur Git tout seul. Rojo fait le lien entre les deux.

### Installation (une seule fois)

1. Installe [Rokit](https://github.com/rojo-rbx/rokit), puis dans le dossier du dépôt lance `rokit install` (installe Rojo 7.4.4, la même version que GitHub).
2. Installe le plugin Rojo dans Studio : `rojo plugin install`.
3. Conseillé : installe l'extension **Rojo** et **Luau Language Server** dans VS Code.

### Session de travail

1. Ouvre le dépôt dans VS Code, sur ta branche de travail.
2. Lance `rojo serve` dans le dossier du dépôt.
3. Dans Studio, ouvre le `Fc27.rbxlx` (ou un place vide), onglet **Plugins > Rojo > Connect**.
4. Modifie les scripts **dans VS Code** : chaque enregistrement est envoyé tout de suite dans Studio. Appuie sur **Jouer** dans Studio pour tester.
5. Enregistre tes changements sur Git (commit + push) : GitHub reconstruit la preview.

### Et si je change quelque chose dans Studio ?

- **Un script** : ne le modifie pas dans Studio, il serait écrasé par Rojo. Fais le changement dans le fichier `src/…` correspondant.
- **Un réglage** (éclairage, joueurs…) : ajoute-le dans `default.project.json`, sous `$properties` du service concerné (comme `Lighting` ou `Players`).
- **Un objet construit à la main** (modèle, décor) : clic droit dessus dans Studio > **Enregistrer dans un fichier**, au format `.rbxmx`, dans le dossier `src/` qui correspond à l'endroit voulu (`src/shared` = ReplicatedStorage, `src/server` = ServerScriptService). Rojo l'inclura comme les scripts. Pour un décor à placer directement dans Workspace, il faudra d'abord ajouter un dossier pour Workspace dans `default.project.json`.

## Façon de travailler

Les changements sont faits sur une branche de travail et publiés en **preview** (release `preview-<branche>`). Ils ne passent dans `main` qu'après validation.
