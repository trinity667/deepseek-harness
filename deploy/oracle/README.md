# Héberger DeepSeek Harness gratuitement, sans terminal ni nom de domaine

Ce guide met en ligne **ton propre DeepSeek Harness** (l'agent), branché sur
**FreeLLMAPI** (le routeur qui fait tourner tes clés API), sur un serveur Oracle
gratuit.

- **Tout se fait en cliquant dans ton navigateur.** Rien n'est installé sur ton
  PC, rien ne prend de place sur ton disque : le serveur tourne chez Oracle.
- **Pas besoin de nom de domaine ni de compte Cloudflare.** Le serveur obtient
  tout seul des adresses HTTPS gratuites en `*.trycloudflare.com`, protégées par
  un **code envoyé à ton e-mail** : personne d'autre ne peut entrer.

Chaque étape indique **où** elle se passe :

| Repère | Où |
|---|---|
| ☁️ **Oracle** | <https://cloud.oracle.com> |
| 🧩 **FreeLLMAPI** | l'adresse `…trycloudflare.com` affichée par le serveur |
| 🤖 **Harness** | l'autre adresse `…trycloudflare.com` affichée par le serveur |

Durée : environ 30 minutes, dont 15 à 20 minutes d'attente pendant que le serveur
s'installe seul.

```
Toi (navigateur) ──HTTPS──▶ Cloudflare : code e-mail obligatoire (seulement ton adresse)
                                │  tunnel sortant (aucun port ouvert sur le serveur)
                     Serveur Oracle ── Harness ──▶ FreeLLMAPI ──▶ tes fournisseurs d'IA
```

## Ce qu'il te faut

- **Un compte Oracle Cloud** (<https://www.oracle.com/cloud/free/>). Oracle demande
  une carte bancaire pour vérifier ton identité ; l'offre *Always Free* ne débite
  rien. **La région d'origine est définitive** : choisis-en une proche de toi.
- **Ton adresse e-mail.**

---

## Étape 1 — ☁️ Oracle : créer le serveur qui s'installe seul (10 min + 20 min d'attente)

1. Ouvre le fichier
   [`deploy/oracle/cloud-init.yaml`](https://github.com/trinity667/deepseek-harness/blob/master/deploy/oracle/cloud-init.yaml)
   sur GitHub → bouton **Copy raw file** (icône de copie). Colle-le dans un
   bloc-notes et **remplace seulement ton e-mail** :

   ```
   ADMIN_EMAIL=toi@example.com      ← ton e-mail
   DOMAIN=                          ← laisse vide
   CLOUDFLARE_TUNNEL_TOKEN=         ← laisse vide
   ```

2. Dans <https://cloud.oracle.com> : menu ☰ → **Compute → Instances → Create
   instance**.
3. **Image and shape** → *Change image* : **Ubuntu**, version **24.04** →
   *Change shape* : **Ampere** → **VM.Standard.A1.Flex**, **2 OCPU** et
   **12 GB** de mémoire (le maximum gratuit).
4. **SSH keys** : choisis *Generate a key pair for me* et clique **Save private
   key** (un petit fichier à garder ; il ne sert qu'en secours).
5. **Boot volume** : coche *Specify a custom boot volume size* → **100 GB**.
6. **Show advanced options → Management → Initialization script** : choisis
   **Paste cloud-init script** et colle **tout** le contenu de ton bloc-notes.
7. **Create**.
   - Si Oracle répond *Out of capacity* (« plus de place »), réessaie dans
     quelques heures ou change d'*Availability Domain* dans *Placement*.
8. Attends que l'instance passe en **Running** (vert), puis encore **15 à
   20 minutes** : elle installe tout, seule.

## Étape 2 — ☁️ Oracle : lire tes adresses et ton mot de passe (2 min)

1. Page de ton instance → **Console history** (dans *Resources* à gauche, ou
   l'onglet *Management* selon la version) → **Capture console history**.
2. Ouvre la capture (⋮ → *View*) et cherche le cadre :

   ```
   ==================================================================
    DeepSeek Harness est prêt.

    Harness     : https://xxxx-xxxx.trycloudflare.com/?token=…
    FreeLLMAPI  : https://yyyy-yyyy.trycloudflare.com
      compte    : toi@gmail.com
      mot de passe (à changer dans Settings) : …
   ==================================================================
   ```

   Pas encore de cadre ? Attends 5 minutes et refais une capture. Une ligne
   `[dsh-bootstrap] ERREUR: …` dit ce qui ne va pas (voir *En cas de problème*).
3. Ces informations sont secrètes : seul ton compte Oracle peut les voir.

## Étape 3 — 🧩 FreeLLMAPI : ajouter tes clés API (10 min)

1. Ouvre l'adresse **FreeLLMAPI** du cadre. Cloudflare te demande ton e-mail,
   puis le **code** reçu par e-mail.
2. Connecte-toi à FreeLLMAPI avec l'e-mail et le mot de passe du cadre.
   **Change tout de suite le mot de passe** (*Settings*).
3. Ajoute tes clés de fournisseurs (Groq, Gemini, OpenRouter…). Si tu les as déjà
   dans l'app FreeLLMAPI de ton PC, exporte-les depuis l'app (fichier `.json` ou
   `.csv`) puis importe-les ici.

Tu n'as **rien à copier** vers le harness : le serveur lui a déjà donné la clé de
FreeLLMAPI.

## Étape 4 — 🤖 Harness : te connecter et tester (5 min)

1. Ouvre le lien **Harness** du cadre (celui avec `?token=`). Cloudflare redemande
   ton code e-mail, puis le harness s'ouvre.
2. Écris à l'agent :

   > Crée un fichier NOTE.md contenant BANANE-42, relis-le avec tes outils et
   > réponds uniquement par le code qu'il contient.

   Il doit répondre **BANANE-42**. 🎉

## Vérifier que c'est sûr

| Vérification | Comment | Résultat attendu |
|---|---|---|
| Protection par e-mail | Ouvre l'adresse du harness dans une fenêtre de navigation privée | Page Cloudflare qui demande un e-mail ; un autre e-mail que le tien est refusé |
| Lien sans jeton | Après le code e-mail, ouvre l'adresse du harness **sans** `?token=…` dans une fenêtre privée | Le harness refuse (erreur 401) |
| Aucun port ouvert | ☁️ Instance → *Networking* → *Security list* | Seul le port 22 (SSH) est ouvert |

Le même montage est testé automatiquement par GitHub sur un serveur ARM à chaque
mise à jour, avec de vrais tunnels protégés : workflow
[*Deploy Oracle test*](https://github.com/trinity667/deepseek-harness/actions/workflows/deploy-oracle-test.yml).

## Utilisation au quotidien

- **Les adresses changent à chaque redémarrage du serveur** (c'est le prix de la
  gratuité sans domaine). Après un redémarrage, refais l'étape 2 pour lire les
  nouvelles.
- **Une adresse ne répond plus** (page d'erreur Cloudflare) :
  ☁️ Instance → **Reboot**, puis étape 2.
- **Tu as régénéré la clé dans FreeLLMAPI** : ☁️ **Reboot**. Au redémarrage, le
  serveur recopie la nouvelle clé vers le harness.
- **Mettre à jour le harness** : ☁️ **Reboot**. Le serveur télécharge la dernière
  version à chaque démarrage.
- Les tunnels gratuits acceptent jusqu'à 200 requêtes simultanées et n'ont pas de
  garantie de disponibilité : c'est largement suffisant pour un usage personnel.

## En cas de problème

| Ce que tu vois dans la console (étape 2) | Que faire |
|---|---|
| `ERREUR: ADMIN_EMAIL n'est pas rempli` (ou pas valide) | L'e-mail de l'étape 1 est resté `toi@example.com` ou a une faute. ☁️ Supprime l'instance (*Terminate*) et recrée-la |
| `ERREUR: les tunnels Cloudflare ne s'ouvrent pas` | ☁️ **Reboot** ; Cloudflare refuse parfois temporairement les tunnels gratuits |
| `ERREUR: FreeLLMAPI ne démarre pas` / `le harness ne démarre pas` | ☁️ **Reboot** ; si ça persiste, utilise le secours ci-dessous |
| Aucun cadre après 30 minutes | Vérifie que le script a bien été collé à l'étape 1.6 (le début doit être `#cloud-config`) |

### Secours : Oracle Cloud Shell (terminal dans le navigateur)

À n'utiliser que pour un diagnostic. ☁️ Icône **>_** (*Cloud Shell*) en haut de la
console Oracle → menu ⚙ → **Upload** → envoie la clé privée de l'étape 1.4, puis :

```bash
chmod 600 ssh-key-*.key && ssh -i ssh-key-*.key ubuntu@IP_DE_TON_INSTANCE 'sudo docker compose --project-directory /opt/dsh logs --tail 60'
```

L'IP est sur la page de l'instance, ligne *Public IP address*. Pour relancer
l'installation, remplace la commande entre apostrophes par
`sudo /opt/dsh/bootstrap.sh`.

## Plus tard : ton propre nom de domaine (adresses fixes)

Quand tu auras un domaine dans Cloudflare, tes adresses deviennent fixes :
`dsh.<domaine>` et `llm.<domaine>`.

1. 🌐 <https://one.dash.cloudflare.com> → **Networks → Tunnels** (ou *Networks →
   Connectors*) → **Create a tunnel** → *Cloudflared* → nom `dsh`. Ne lance aucune
   commande : copie seulement le **jeton** `eyJ…`.
2. Ajoute deux *Public hostnames* : `dsh.<domaine>` → `HTTP` `127.0.0.1:3080`, et
   `llm.<domaine>` → `HTTP` `127.0.0.1:3001`.
3. **Access → Applications → Add an application → Self-hosted** : domaines
   `dsh.<domaine>` et `llm.<domaine>`, politique **Allow** pour ton e-mail,
   connexion **One-time PIN**. Puis, dans <https://dash.cloudflare.com>, ton
   domaine → **SSL/TLS → Edge Certificates → Always Use HTTPS**.
4. Mets `DOMAIN=` et `CLOUDFLARE_TUNNEL_TOKEN=` dans les réglages du serveur, via
   le secours Cloud Shell :

   ```bash
   ssh -i ssh-key-*.key ubuntu@IP_DE_TON_INSTANCE "sudo sed -i -e 's/^DOMAIN=.*/DOMAIN=mondomaine.com/' -e 's/^CLOUDFLARE_TUNNEL_TOKEN=.*/CLOUDFLARE_TUNNEL_TOKEN=eyJ.../' /opt/dsh/settings.env && sudo reboot"
   ```

   Tes clés FreeLLMAPI et tes sessions sont conservées.

## Sécurité

- Le harness **exécute des commandes** demandées par l'IA. Il tourne isolé dans un
  conteneur, en utilisateur non-root, et ne voit ni la clé de chiffrement ni le
  mot de passe de FreeLLMAPI.
- Trois verrous protègent l'accès : le **code e-mail** de Cloudflare (seulement ton
  adresse), le **jeton** du lien du harness, et le **mot de passe** de FreeLLMAPI.
- N'ouvre jamais les ports 3001 ou 3080 dans Oracle, et n'utilise pas de modèle
  « sans refus » (voir `tools/skills/heretic`) sur ce serveur.

## Pour les curieux : les fichiers

| Fichier | Rôle |
|---|---|
| `cloud-init.yaml` | Ce que tu colles dans Oracle : ton e-mail, puis le lancement de `bootstrap.sh` |
| `bootstrap.sh` | Installe Docker, crée le compte FreeLLMAPI, donne sa clé au harness, ouvre les tunnels, démarre tout, affiche le cadre ; rejoué à chaque démarrage |
| `compose.yml` | FreeLLMAPI, le harness et les tunnels (`quick` sans domaine, `named` avec domaine), uniquement sur `127.0.0.1` |
| `dsh/freellmapi.patch.yml` | Config du harness : route FreeLLMAPI, réessais, modèle `auto` |
| `Dockerfile` | Recette de l'image du harness, construite par GitHub Actions (`deploy-image.yml`) |
| `*.env.example` | Modèles des fichiers de secrets que `bootstrap.sh` crée sur le serveur |
