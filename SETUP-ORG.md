# Mise en place de l'organisation GitHub (côté prof)

L'organisation est **`nsi-bf`**. Tout ce qui la peuple, équipes, dépôts
d'élèves, dépôt-modèle, est fait par **metatest**, qui seul connaît la base des
élèves : `outils/equipe_github.py`. Ce dépôt-ci ne contient plus d'outil
d'administration (`nsi-admin` a été supprimé le 2026-09-11 : il faisait le même
geste avec d'autres noms, et les deux avaient divergé).

Ce document ne garde donc que ce que metatest ne fait pas : les réglages de
l'organisation, à faire une fois à la main.

## 1. Le compte qui agit

`mmarchand-teacher` est **administrateur** de `nsi-bf`. `MMarchand-NSI`, le
compte actif de `gh`, n'en est que **membre** : les appels d'administration lui
rendent 403. `equipe_github.py` prend son jeton par `gh auth token --user` et ne
change pas le compte actif ; il faut simplement que `mmarchand-teacher` soit
authentifié une fois :

```bash
gh auth login --hostname github.com   # en tant que mmarchand-teacher
```

## 2. Réglages de l'organisation

`nsi-bf` → **Settings** → **Member privileges**.

**À ne pas sauter :** `Base permissions` doit être sur **`No permission`**.
C'est ce réglage, pas l'équipe, qui décide si être membre de l'organisation
donne un accès par défaut à *tous* ses dépôts. Laissé sur `Read` ou plus, chaque
élève verrait les dépôts de tous les autres.

- `Member privileges › Base permissions` → **No permission**
- `Member privileges › Repository creation` → tout décocher
- `Member privileges › Repository forking` → désactivé

Optionnel : `Require two-factor authentication` (page Security) force la 2FA
pour accepter l'invitation. Plus sûr, mais un obstacle réel pour de jeunes
débutants.

## 3. Le dépôt-modèle

`nsi-bf/template-eleves` : privé, marqué **Template repository**. C'est la
**source unique** des fichiers de configuration de l'élève, ne pas les
dupliquer dans `scripts-install`.

**Son contenu se règle à part, à la main.** `settings.json` et `pyproject.toml`
sont mis au point dépôt par dépôt, et la version en vigueur est celle de
`nsi-bf/TEST_2025-2026-NSI-eleve`. Ni ce dépôt-ci ni metatest ne sont la source
de ces fichiers.

Ce que metatest fait, et ne fait pas :

- il **crée** le dépôt-modèle s'il n'existe pas, et y pose les fichiers de
  `outils/modele/`, une amorce, pour qu'un modèle neuf ne soit pas vide ;
- il ne **réécrit jamais** un fichier déjà présent dans le modèle
  (`assurer_modele` : `if present and not neuf: continue`). Le réglage à la main
  ne risque rien ;
- **le seul piège** : un fichier présent dans `outils/modele/` et retiré
  volontairement du modèle y serait reposé au prochain passage. Retirer un
  fichier du modèle pour de bon, c'est aussi le retirer de `outils/modele/` ;
- `--rafraichir` (§5) lit le modèle **sur GitHub**, pas `outils/modele/` : c'est
  bien la version réglée à la main qui se propage aux dépôts d'élèves.

Un dépôt engendré depuis un modèle n'a aucun lien avec lui : GitHub ne sait pas
propager une correction, d'où `--rafraichir`.

`nsi reset-config` lit les mêmes fichiers dans ce dépôt, avec le jeton de l'élève
(`TEMPLATE_FICHIERS` et `TEMPLATE_REPO` dans [`nsi`](nsi)). Ces quatre chemins
doivent donc exister dans le modèle.

## 4. Inscrire une classe

Rien à taper ici : les élèves et leurs comptes GitHub viennent de la base
metatest (`eleve.github`).

```bash
cd ~/metatest
METATEST=https://metatest.fly.dev JETON=… \
  uv run python -m outils.equipe_github 1G3              # dit ce qu'il ferait
METATEST=https://metatest.fly.dev JETON=… \
  uv run python -m outils.equipe_github 1G3 --vraiment   # le fait
```

**Rien n'est fait sans `--vraiment`.** L'outil est rejouable, n'efface jamais
rien, et ne régénère jamais un dépôt qui existe.

Pour chaque élève ayant déclaré un compte : invitation dans l'équipe de la
classe, création de son dépôt depuis le modèle, ajout en collaborateur
**écriture** sur ce seul dépôt. L'équipe ne porte aucun droit sur aucun dépôt.

### Nommage

| | |
|---|---|
| Année scolaire | `AAAA-AAAA+1`, bascule le 1ᵉʳ août |
| Équipe | `<classe>_<année>`, `1G3_2026-2027` |
| Dépôt élève | `<équipe>-<compte>`, `1G3_2026-2027-Marie-Dupont` |
| Dossier local | `~/<équipe>` |

Contrat partagé : metatest l'écrit (`nom_equipe`/`nom_depot`), `nsi init` le
relit. Rien ne synchronise les deux dépôts, une modification d'un côté est à
répercuter à la main de l'autre.

## 5. Propager une correction du modèle

```bash
… uv run python -m outils.equipe_github 1G3 --rafraichir             # dit
… uv run python -m outils.equipe_github 1G3 --rafraichir --vraiment  # fait
```

Réécrit fichier par fichier la **configuration** (ce que le modèle tient) dans
les dépôts déjà créés, sans toucher à la **graine** (ce qui appartient à
l'élève). Si l'élève a modifié un fichier tenu en dernier, l'outil s'arrête et
le dit ; `--forcer` passe outre.

## 6. Vérifier avant d'envoyer une classe entière

- [ ] `equipe_github.py` sur une classe d'un seul élève test
- [ ] accepter les deux invitations reçues (organisation, puis dépôt)
- [ ] `nsi init`, le dépôt se clone sans rien demander de plus que le token
- [ ] modifier un fichier, `nsi push`, vérifier le commit sur GitHub
- [ ] sur une autre machine (ou après suppression du dossier), `nsi init` puis
      `nsi pull` récupère la modification

## Pense-bête

| | |
|---|---|
| Organisation | `nsi-bf` |
| Compte administrateur | `mmarchand-teacher` |
| Dépôt-modèle | `nsi-bf/template-eleves` |
| Inscrire une classe | `uv run python -m outils.equipe_github <classe> --vraiment` (dans metatest) |
| Réglage critique | Base permissions = No permission |
