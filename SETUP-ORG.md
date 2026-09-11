# Mise en place de l'organisation GitHub (côté prof)

À faire une fois pour préparer l'organisation `mmarchand-teacher`. À partir de l'année suivante, seule l'étape 4 est à refaire par classe.

## 1. Créer l'organisation (si pas déjà fait)

- Va sur https://github.com/account/organizations/new
- Plan **Free**
- Nom de l'organisation : `mmarchand-teacher`
- À l'étape "inviter des membres" : clique sur **Skip this step** (les élèves seront ajoutés plus tard par `nsi-admin`, pas ici)

## 2. Paramétrer l'organisation

Dans `mmarchand-teacher` → **Settings** → **Member privileges**.

**Important, à ne pas sauter :** `Base permissions` doit être sur `No permission`. C'est ce réglage — pas la team — qui décide si être membre de l'organisation donne un accès par défaut à *tous* ses dépôts. Laissé sur "Read" ou plus, la team-classe donnerait à chaque élève un accès à tous les dépôts de tous les autres, même sans jamais y être ajouté comme collaborateur.

- `Member privileges › Base permissions` → **No permission**
- `Member privileges › Repository creation` → décoche tout (seul toi crées des dépôts, via le template)
- `Member privileges › Repository forking` → désactivé

Optionnel : `Require two-factor authentication` (en haut de la page Security) force tous les élèves à activer la 2FA pour accepter l'invitation. Plus sûr, mais un obstacle réel pour de jeunes débutants — à toi de voir.

## 3. Le dépôt template

`nsi-bf/template-eleves` existe déjà : privé, marqué **template**, il contient
`.gitignore`, `.vscode/`, `pyproject.toml`, `README.md` et `hello-world.py`.

C'est la **source unique** de ces fichiers. Ne les duplique pas dans
`scripts-install` : `nsi settings` va les chercher ici par `gh api`, avec le
jeton de l'élève.

Pour le faire évoluer, travaille dedans comme dans un dépôt normal. Attention :
un template est un instantané, une modification ne se propage pas aux dépôts
d'élèves déjà créés — c'est `nsi settings` qui joue ce rôle, à la demande.

## 4. Inscrire une classe

CSV sans en-tête, une ligne par élève :

```
Dupont Jean,jdupont23
Martin Léa,lmartin23
Nguyen Minh,mnguyen23
```

```bash
gh auth login          # une fois, en tant que toi (owner de l'organisation)
./nsi-admin 1B.csv "Classe-1B"
```

Pour chaque ligne, sans rien dupliquer si tu relances : invitation dans la team-roster de la classe (aucun dépôt jamais attaché), création du dépôt individuel depuis le template, ajout de l'élève en collaborateur écriture sur ce seul dépôt.

## 5. Vérifier avant d'envoyer la classe

Rien de ce circuit n'a encore été testé de bout en bout. Avant 30 élèves :

- [ ] `nsi-admin` sur un CSV d'un seul élève test
- [ ] accepter les deux invitations reçues (organisation, puis dépôt)
- [ ] `nsi git` — le dépôt se clone sans rien demander de plus que le token
- [ ] modifier un fichier, `nsi push`, vérifier le commit sur GitHub
- [ ] sur une autre machine (ou après suppression du dossier), `nsi git` puis `nsi pull` récupère la modification

## Pense-bête

| | |
|---|---|
| Organisation | `mmarchand-teacher` |
| Dépôt template | `mmarchand-teacher/template-eleve` |
| Nouvelle classe | `./nsi-admin <csv> "Classe-X"` |
| Réglage critique | Base permissions = No permission |
