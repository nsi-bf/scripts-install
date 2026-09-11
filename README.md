# NSI Dev : ton environnement de développement

Bienvenue ! Ces instructions te permettent d'installer en quelques minutes tout ce dont tu as besoin pour coder en NSI.

---

## Etape 1 : installation

### Windows

Ouvre **PowerShell en tant qu'administrateur**, puis colle cette commande :

> Menu Démarrer, tape `powershell`, **clic droit** sur **Windows PowerShell**,
> puis **Exécuter en tant qu'administrateur**.
>
> Pas l'invite de commandes `cmd` : le détecteur de menaces de Windows y
> bloque l'installation.
>
> Sur un ordinateur du lycée, tu ne pourras pas : lance-la sans être
> administrateur, tout ce qui en a besoin y est déjà installé.

```
irm https://raw.githubusercontent.com/nsi-bf/scripts-install/main/setup-windows.ps1 -OutFile "$env:TEMP\nsi-setup.ps1"; Set-ExecutionPolicy Bypass -Scope Process -Force; & "$env:TEMP\nsi-setup.ps1"
```

> Si l'installation te demande de redémarrer, fais-le puis relance exactement la même commande.

### Mac / Linux

Ouvre un terminal et colle cette commande :

```
curl -fsSL https://raw.githubusercontent.com/nsi-bf/scripts-install/main/setup.sh | bash
```

> Pas de `sudo` devant : l'installation demandera elle-même ton mot de passe si elle en a besoin.

Quand c'est fini, **ouvre un nouveau terminal** avant de passer à la suite.

---

## Etape 2 : créer un compte GitHub

Rends-toi sur [https://github.com/join](https://github.com/join) et crée un compte.

> **Note bien quelque part ton nom d'utilisateur GitHub et donne-le à ton prof.** Il/elle prépare ton dépôt de cours et t'invite dessus. Tu recevras deux invitations GitHub à accepter (l'organisation, puis le dépôt) avant de pouvoir passer à l'étape suivante.

---

## Etape 3 : configurer ton compte GitHub

Ouvre **VSCode**, puis ouvre un terminal intégré (`Terminal > Nouveau terminal` ou `Ctrl+ù`).

Dans ce terminal, tape :

```
nsi init
```

Il te sera demandé un **token d'accès personnel** (une sorte de mot de passe sécurisé). Ton dépôt et ton identité git sont retrouvés automatiquement à partir de ce token : rien d'autre à taper.

Pour créer ton token : va sur [https://github.com/settings/tokens](https://github.com/settings/tokens), clique sur **Generate new token (classic)**, et coche les trois portées **`repo`**, **`read:org`** et **`gist`**.

> **Attention : le token ne s'affiche qu'une seule fois, copie-le immédiatement.** Garde-le en lieu sûr : `nsi init` le redemande à chaque fois. Si tu l'as perdu, révoque-le et crée-en un nouveau.

Une fois terminé, **VSCode s'ouvre automatiquement** dans ton dépôt. C'est là que tu travailleras.

---

## Etape 4 : sauvegarder et récupérer ton travail

### Sauvegarder

```
nsi push
```

Cette commande enregistre tout ton travail et l'envoie sur GitHub. Fais-le régulièrement, comme tu brancherais une clé USB pour ne pas perdre tes fichiers.

### Récupérer sur un autre ordinateur

```
nsi pull
```

Cette commande récupère la dernière version de ton travail depuis GitHub.

---

## GitHub : ta nouvelle clé USB

GitHub remplace la clé USB. Tes fichiers y sont stockés en ligne, accessibles depuis n'importe quel ordinateur.

- Tu travailles sur un ordi du lycée → `nsi push` avant de partir
- Tu continues chez toi → `nsi pull` pour récupérer tes fichiers
- Tu reviens au lycée → `nsi pull` puis `nsi push` quand tu as terminé

---

## Référence des commandes

| Commande | Description |
|---|---|
| `nsi init` | Première mise en route : GitHub, ton dépôt, VSCode |
| `nsi push` | Sauvegarde et envoie ton travail sur GitHub |
| `nsi pull` | Récupère la dernière version depuis GitHub |
| `nsi reset-config` | Remet la configuration du projet à la version du prof (efface tes `uv add`) |
| `nsi toggle-config` | Cache ou réaffiche les fichiers de configuration dans VSCode |
| `nsi dir` | Affiche le chemin de ton dossier de cours |
| `nsi update` | Met à jour l'outil `nsi` |
| `nsi install <composant>` | Installe un composant supplémentaire |
| `nsi remove <composant>` | Désinstalle un composant |
