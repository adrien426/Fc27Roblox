# Consignes pour Claude

## Branches et déploiement (à suivre à chaque tâche)

- Travailler sur sa branche de travail (`claude/…`). Chaque push y produit la release `preview-<branche>`.
- Quand la tâche est terminée et que le build « Build place » de la branche est vert, **fusionner la branche dans `test`**
  et pousser `test` : le workflow « Deploy to Roblox » déploie alors sur l'expérience de test.
  ```
  git fetch origin test && git checkout -B test origin/test
  git merge --no-ff <branche-de-travail>
  git push -u origin test
  ```
  Ne jamais forcer (`--force`) sur `test` ni `main` : le bot y commite les numéros des assets uploadés.
  En cas de conflit sur `src/shared/AssetIds.luau` ou `assets/uploaded.json`, garder la version de `test` puis
  relancer le déploiement (il rajoute ce qui manque).
- Attendre que « Deploy to Roblox » soit vert sur `test`, donner le lien pour jouer, et dire ce qu'il faut vérifier en jeu.
- **Ne fusionner `test` dans `main`** (déploiement en production) **que lorsque l'utilisateur a validé le test.**
- Pas de pull request sans demande explicite.
- **États stables :** un tag `stable-N` n'est posé **que lorsque l'utilisateur le demande explicitement** (« tag
  stable »), jamais automatiquement à chaque passage dans `main`. Il se pose avec le workflow « Tag stable », lancé à
  la main (le proxy de session ne permet pas de pousser un tag directement).
  Pour revenir à un état stable : `git checkout -b <branche> stable-N`, puis le chemin habituel `test` → `main`.
