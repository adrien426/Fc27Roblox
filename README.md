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

Pour travailler en direct dans Studio : installe [Rojo](https://rojo.space), lance `rojo serve`, puis connecte-toi depuis le plugin Rojo de Studio.

## Façon de travailler

Les changements sont faits sur une branche de travail et publiés en **preview** (release `preview-<branche>`). Ils ne passent dans `main` qu'après validation.
