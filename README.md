# NSI Dev — Ton environnement de développement

Bienvenue ! Ces instructions te permettent d'installer en quelques minutes tout ce dont tu as besoin pour coder en NSI.

---

## Etape 1 — Installation

### Windows

Ouvre **cmd.exe** ou **PowerShell** et colle cette commande :

```
powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/nsi-bf/scripts-install/main/setup.ps1 | iex"
```

> Si l'installation te demande de redémarrer, fais-le puis relance exactement la même commande.

### Mac / Linux

Ouvre un terminal et colle cette commande :

```
curl -fsSL https://raw.githubusercontent.com/nsi-bf/scripts-install/main/nsi | sudo bash -s -- install base
```

> Si l'installation te demande de redémarrer, fais-le puis relance exactement la même commande.

---

## Etape 2 — Créer un compte GitHub

Rends-toi sur [https://github.com/join](https://github.com/join) et crée un compte.

> **Note bien quelque part ton nom d'utilisateur GitHub et donne-le à ton prof.** Il/elle prépare ton dépôt de cours et t'invite dessus. Tu recevras deux e-mails/notifications GitHub à accepter (invitation à l'organisation, puis au dépôt) avant de pouvoir passer à l'étape suivante.

---

## Etape 3 — Configurer ton compte GitHub

Ouvre **VSCode**, puis ouvre un terminal intégré (`Terminal > Nouveau terminal` ou `Ctrl+ù`).

Dans ce terminal, tape :

```
nsi git
```

Il te sera demandé un **token d'accès personnel** (une sorte de mot de passe sécurisé). Ton dépôt et ton identité git sont retrouvés automatiquement à partir de ce token : rien d'autre à taper.

Pour créer ton token : va sur [https://github.com/settings/tokens](https://github.com/settings/tokens), crée un token avec la portée (scope) `repo`.  
**Attention : le token ne s'affiche qu'une seule fois, copie-le immédiatement.**

Une fois terminé, **VSCode s'ouvre automatiquement** dans ton dépôt. C'est là que tu travailleras.

---

## Etape 4 — Sauvegarder et récupérer ton travail

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
| `nsi git` | Configuration initiale de git et GitHub |
| `nsi push` | Sauvegarde et envoie ton travail sur GitHub |
| `nsi pull` | Récupère la dernière version depuis GitHub |
| `nsi update` | Met à jour l'outil `nsi` |
| `nsi install <composant>` | Installe un composant supplémentaire |
| `nsi remove <composant>` | Désinstalle un composant |
