# Héberger DeepSeek Harness gratuitement, sans terminal

Ce guide met en ligne **ton propre DeepSeek Harness** (l'agent), branché sur
**FreeLLMAPI** (le routeur qui fait tourner tes clés API), sur un serveur Oracle
gratuit, protégé par une connexion Cloudflare.

**Tout se fait en cliquant dans ton navigateur.** Rien n'est installé sur ton PC,
rien ne prend de place sur ton disque : le serveur tourne chez Oracle.

Chaque étape indique **où** elle se passe :

| Repère | Où |
|---|---|
| 🌐 **Cloudflare** | <https://dash.cloudflare.com> et <https://one.dash.cloudflare.com> |
| ☁️ **Oracle** | <https://cloud.oracle.com> |
| 🧩 **FreeLLMAPI** | `https://llm.<ton-domaine>` (une fois installé) |
| 🤖 **Harness** | `https://dsh.<ton-domaine>` (une fois installé) |

Durée : environ 45 minutes, dont 15 à 20 minutes d'attente pendant que le serveur
s'installe seul.

## Ce qu'il te faut avant de commencer

- **Un nom de domaine dans Cloudflare** (par exemple `mondomaine.com`). Si tu
  n'en as pas, achète-en un chez Cloudflare (*Domain Registration → Register
  Domains*, quelques euros par an) : il est configuré automatiquement.
- **Un compte Oracle Cloud.** Oracle demande une carte bancaire pour vérifier ton
  identité ; l'offre *Always Free* ne débite rien.
- **Ton adresse e-mail**, qui servira à te connecter.

```
Toi (navigateur) ──HTTPS──▶ Cloudflare : connexion par code e-mail obligatoire
                                │  tunnel (aucun port ouvert sur le serveur)
                     Serveur Oracle ── Harness (dsh.<domaine>) ──▶ FreeLLMAPI (llm.<domaine>)
```

---

## Étape 1 — 🌐 Cloudflare : créer le tunnel (10 min)

Le tunnel est le « câble » entre Cloudflare et ton futur serveur. On le crée en
premier, car le serveur a besoin de son jeton pour s'installer.

1. Ouvre <https://one.dash.cloudflare.com> et choisis ton compte. La première
   fois, Cloudflare te fait choisir un nom d'équipe et l'offre **Free** (gratuite
   jusqu'à 50 utilisateurs).
2. Menu **Networks → Tunnels** (selon la version : *Networks → Connectors →
   Cloudflare Tunnels*) → **Create a tunnel**.
3. Type **Cloudflared** → *Next* → nom : `dsh` → *Save tunnel*.
4. Cloudflare affiche des commandes d'installation. **N'en lance aucune.**
   Copie seulement le **jeton** : la longue suite de caractères qui commence par
   `eyJ` à la fin de la commande. Colle-le dans un bloc-notes pour l'étape 2.
5. *Next* → onglet **Public hostnames** (ou *Published application routes*) →
   ajoute **deux** adresses :

   | Sous-domaine | Domaine | Type | URL |
   |---|---|---|---|
   | `dsh` | ton domaine | `HTTP` | `127.0.0.1:3080` |
   | `llm` | ton domaine | `HTTP` | `127.0.0.1:3001` |

   Le tunnel restera « Inactive » / « Down » tant que le serveur n'existe pas :
   c'est normal.

## Étape 2 — 🌐 Cloudflare : protéger l'accès (5 min)

Sans cette étape, n'importe qui pourrait atteindre tes pages. **Ne la saute pas.**

1. Toujours dans <https://one.dash.cloudflare.com> : **Access → Applications**
   (ou *Access controls → Applications*) → **Add an application** →
   **Self-hosted**.
2. Nom : `dsh`. Ajoute **deux** domaines publics : `dsh.<ton-domaine>` et
   `llm.<ton-domaine>`.
3. Politique : nom `moi`, action **Allow**, règle **Emails** = ton adresse e-mail.
4. Méthode de connexion : **One-time PIN** (un code envoyé par e-mail).
5. Enregistre.
6. Dans <https://dash.cloudflare.com>, choisis ton domaine → **SSL/TLS → Edge
   Certificates** → active **Always Use HTTPS**.

## Étape 3 — ☁️ Oracle : créer le serveur qui s'installe seul (10 min + 20 min d'attente)

1. Ouvre le fichier
   [`deploy/oracle/cloud-init.yaml`](https://github.com/trinity667/deepseek-harness/blob/master/deploy/oracle/cloud-init.yaml)
   sur GitHub → bouton **Copy raw file** (icône de copie). Colle-le dans ton
   bloc-notes et **remplis les 3 valeurs encadrées en haut** :

   ```
   DOMAIN=mondomaine.com                        ← ton domaine, sans https://
   ADMIN_EMAIL=toi@example.com                  ← ton e-mail
   CLOUDFLARE_TUNNEL_TOKEN=COLLE_ICI_LE_JETON…  ← le jeton eyJ… de l'étape 1
   ```

   Ne change rien d'autre dans le fichier.
2. Dans <https://cloud.oracle.com> : menu ☰ → **Compute → Instances → Create
   instance**.
3. **Image and shape** → *Change image* : **Ubuntu**, version **24.04** →
   *Change shape* : **Ampere** → **VM.Standard.A1.Flex**, **2 OCPU** et
   **12 GB** de mémoire (le maximum gratuit).
4. **SSH keys** : choisis *Generate a key pair for me* et clique **Save private
   key** (un petit fichier, à garder au cas où ; il ne sert qu'en secours).
5. **Boot volume** : coche *Specify a custom boot volume size* → **100 GB**.
6. **Show advanced options → Management → Initialization script** : choisis
   **Paste cloud-init script** et colle **tout** le contenu de ton bloc-notes.
7. **Create**.
   - Si Oracle répond *Out of capacity* (« plus de place »), réessaie dans
     quelques heures ou change d'*Availability Domain* dans la section
     *Placement*.
8. Attends que l'instance passe en **Running** (vert), puis encore **15 à
   20 minutes** : elle installe Docker et télécharge le harness toute seule.

## Étape 4 — ☁️ Oracle : lire ton lien et ton mot de passe (2 min)

Le serveur écrit ses informations de connexion sur sa console.

1. Page de ton instance → **Console history** (dans *Resources* à gauche, ou
   l'onglet *Management* selon la version) → **Capture console history**.
2. Ouvre la capture (⋮ → *View*). Cherche le cadre :

   ```
   ==================================================================
    DeepSeek Harness est prêt.

    Harness     : https://dsh.mondomaine.com/?token=…
    FreeLLMAPI  : https://llm.mondomaine.com
      compte    : toi@example.com
      mot de passe (à changer dans Settings) : …
   ==================================================================
   ```

   Si le cadre n'apparaît pas encore, attends 5 minutes et refais une capture.
   Si tu vois une ligne `[dsh-bootstrap] ERREUR: …`, elle dit quelle valeur
   corriger (voir *En cas de problème*).
3. Ces informations sont secrètes : seul ton compte Oracle peut les voir.

## Étape 5 — 🧩 FreeLLMAPI : ajouter tes clés API (10 min)

1. Ouvre `https://llm.<ton-domaine>`. Cloudflare te demande ton e-mail puis le
   code reçu : c'est la protection de l'étape 2.
2. Connecte-toi à FreeLLMAPI avec l'e-mail et le mot de passe du cadre.
   **Change tout de suite le mot de passe** (*Settings*).
3. Ajoute tes clés de fournisseurs (Groq, Gemini, OpenRouter…). Si tu les as déjà
   dans l'app FreeLLMAPI de ton PC, exporte-les depuis l'app (fichier `.json` ou
   `.csv`) puis importe-les ici.

Tu n'as **rien à copier** vers le harness : le serveur lui a déjà donné la clé
de FreeLLMAPI.

## Étape 6 — 🤖 Harness : te connecter et tester (5 min)

1. Ouvre le lien **Harness** du cadre (celui avec `?token=`). Cloudflare demande
   ton code e-mail, puis le harness s'ouvre et retient ta session.
2. Écris à l'agent :

   > Crée un fichier NOTE.md contenant BANANE-42, relis-le avec tes outils et
   > réponds uniquement par le code qu'il contient.

   Il doit répondre **BANANE-42**. 🎉

## Vérifier que c'est sûr

| Vérification | Comment | Résultat attendu |
|---|---|---|
| Protection active | Ouvre `https://dsh.<ton-domaine>` dans une fenêtre de navigation privée | Page de connexion **Cloudflare Access**, jamais le harness directement |
| Lien sans jeton | Après connexion Cloudflare, ouvre `https://dsh.<ton-domaine>` sans `?token=` dans une fenêtre privée | Le harness refuse (erreur 401) |
| Tunnel en marche | 🌐 *Networks → Tunnels* | Le tunnel `dsh` est **Healthy** |
| Aucun port ouvert | ☁️ Instance → *Networking* → *Security list* | Seul le port 22 (SSH) est ouvert, rien pour 3001 ou 3080 |

Le même montage est testé automatiquement par GitHub sur un serveur ARM à chaque
mise à jour : workflow
[*Deploy Oracle test*](https://github.com/trinity667/deepseek-harness/actions/workflows/deploy-oracle-test.yml).

## Utilisation au quotidien

- **Nouveau lien du harness** : le jeton change à chaque redémarrage du serveur.
  Si le harness te refuse l'accès, refais l'étape 4 pour lire le nouveau lien.
- **Tu as régénéré la clé dans FreeLLMAPI** : ☁️ Instance → **Reboot**. Au
  redémarrage, le serveur recopie la nouvelle clé vers le harness.
- **Mettre à jour** : ☁️ Instance → **Reboot**. Le serveur télécharge la dernière
  version du harness à chaque démarrage.

## En cas de problème

| Ce que tu vois dans la console (étape 4) | Que faire |
|---|---|
| `ERREUR: DOMAIN n'est pas rempli` (ou `ADMIN_EMAIL`, `CLOUDFLARE_TUNNEL_TOKEN`) | Une valeur de l'étape 3 est restée vide. ☁️ Supprime l'instance (*Terminate*) et recrée-la avec la bonne valeur |
| `ERREUR: FreeLLMAPI ne démarre pas` / `le harness ne démarre pas` | ☁️ *Reboot* ; si ça persiste, utilise le secours ci-dessous |
| Aucun cadre après 30 minutes | Vérifie que le script a bien été collé à l'étape 3.6 (le début doit être `#cloud-config`) |
| Le tunnel reste *Down* | Le jeton collé est incomplet : recrée l'instance avec le jeton entier |

### Secours : Oracle Cloud Shell (terminal dans le navigateur)

À n'utiliser que si on te le demande pour diagnostiquer. ☁️ Icône **>_** (*Cloud
Shell*) en haut de la console Oracle → menu ⚙ → **Upload** → envoie la clé privée
de l'étape 3.4, puis :

```bash
chmod 600 ssh-key-*.key && ssh -i ssh-key-*.key ubuntu@IP_DE_TON_INSTANCE 'sudo docker compose --project-directory /opt/dsh logs --tail 60'
```

L'IP de ton instance est sur sa page, ligne *Public IP address*. Pour relancer
l'installation : remplace la commande entre apostrophes par
`sudo /opt/dsh/bootstrap.sh`.

## Sécurité

- Le harness **exécute des commandes** demandées par l'IA. Il tourne isolé dans un
  conteneur, en utilisateur non-root. Il ne voit ni la clé de chiffrement ni le
  mot de passe de FreeLLMAPI.
- Ne supprime jamais l'application Cloudflare Access de l'étape 2, et n'ouvre
  jamais les ports 3001 ou 3080 dans Oracle.
- N'utilise pas de modèle « sans refus » (voir `tools/skills/heretic`) sur ce
  serveur.

## Pour les curieux : les fichiers

| Fichier | Rôle |
|---|---|
| `cloud-init.yaml` | Ce que tu colles dans Oracle : tes 3 valeurs, puis le lancement de `bootstrap.sh` |
| `bootstrap.sh` | Installe Docker, crée le compte FreeLLMAPI, donne sa clé au harness, démarre tout, affiche le cadre ; rejoué à chaque démarrage |
| `compose.yml` | Les trois services (FreeLLMAPI, harness, cloudflared), uniquement sur `127.0.0.1` |
| `dsh/freellmapi.patch.yml` | Config du harness : route FreeLLMAPI, réessais, modèle `auto` |
| `Dockerfile` | Recette de l'image du harness, construite par GitHub Actions (`deploy-image.yml`) |
| `*.env.example` | Modèles des fichiers de secrets que `bootstrap.sh` crée sur le serveur |
