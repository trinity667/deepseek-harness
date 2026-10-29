# Déployer DeepSeek Harness gratuitement sur Oracle Cloud

Ce dossier installe sur **une VM Oracle Cloud Always Free** :

- **FreeLLMAPI** (image officielle `ghcr.io/tashfeenahmed/freellmapi`) : le routeur
  qui fait tourner tes clés API et bascule entre les modèles ;
- **DeepSeek Harness** (`dsh web`), compilé depuis ce dépôt, branché sur FreeLLMAPI ;
- **cloudflared** : le tunnel Cloudflare qui donne une adresse HTTPS publique
  **sans ouvrir aucun port**, avec **Cloudflare Access** qui exige une connexion
  avant d'atteindre l'interface.

```
Navigateur ──HTTPS──▶ Cloudflare (Access : connexion obligatoire)
                           │ tunnel sortant
                    VM Oracle ── cloudflared ──▶ dsh 127.0.0.1:3080 ──▶ FreeLLMAPI 127.0.0.1:3001
```

Tout est gratuit. Il te faut seulement un **nom de domaine géré par Cloudflare**
(gratuit si tu en as déjà un, sinon quelques euros par an).

| Fichier | Rôle |
|---|---|
| `setup-vm.sh` | Prépare la VM : Docker, swap de 4 Go, clone du dépôt, `.env` avec une clé de chiffrement |
| `compose.yml` | Les trois services ; seuls des ports locaux (`127.0.0.1`) sont utilisés |
| `Dockerfile` | Image du harness (compile `pnpm run build`, tourne en utilisateur non-root) |
| `dsh/freellmapi.patch.yml` | Config du harness : route `freellmapi`, réessais, modèle `auto`, pas de titres LLM |
| `.env.example` | Modèle des secrets ; la copie `.env` n'est jamais commitée |

---

## 1. Créer la VM Oracle (15 min)

1. Crée un compte sur <https://www.oracle.com/cloud/free/>. Une carte bancaire est
   demandée pour vérifier ton identité ; l'offre Always Free ne débite rien.
   **La région d'origine est définitive** : choisis-en une proche de toi.
2. *Compute → Instances → Create instance* :
   - **Image** : Canonical Ubuntu 24.04 ;
   - **Shape** : `VM.Standard.A1.Flex` (Ampere, ARM), **2 OCPU, 12 Go** de mémoire
     (c'est la limite gratuite depuis juin 2026) ;
   - **Boot volume** : 100 Go ;
   - **SSH keys** : télécharge la clé privée proposée, ou colle ta clé publique.
3. Si Oracle répond *Out of capacity*, réessaie plus tard ou dans un autre
   *Availability Domain*.
4. Note l'**adresse IP publique** de la VM. N'ajoute **aucune** règle d'entrée :
   seul le port SSH 22, ouvert par défaut, est nécessaire.

## 2. Préparer la VM (10 min)

Depuis ton PC :

```bash
ssh -i chemin/vers/cle.key ubuntu@IP_DE_LA_VM
```

Puis sur la VM :

```bash
git clone https://github.com/trinity667/deepseek-harness.git
bash deepseek-harness/deploy/oracle/setup-vm.sh
exit
```

Reconnecte-toi en SSH (pour que le groupe `docker` soit pris en compte).

## 3. Démarrer et configurer FreeLLMAPI

```bash
cd ~/deepseek-harness
docker compose -f deploy/oracle/compose.yml up -d freellmapi
docker compose -f deploy/oracle/compose.yml logs freellmapi | grep -i "setup code"
```

Le tableau de bord n'est **jamais** exposé sur Internet. Ouvre-le à travers SSH,
depuis ton PC :

```bash
ssh -i chemin/vers/cle.key -L 3001:127.0.0.1:3001 ubuntu@IP_DE_LA_VM
```

Puis, dans ton navigateur : <http://localhost:3001>

1. Crée le compte administrateur (avec le *setup code* affiché dans les logs).
2. Ajoute tes clés de fournisseurs. Depuis l'app de bureau FreeLLMAPI, tu peux les
   exporter (fichier `.env`, `.csv` ou `.json`) puis les importer ici.
3. Copie la **clé unifiée** de FreeLLMAPI dans `deploy/oracle/.env`, ligne
   `FREE_LLM_API_KEY=`.

## 4. Créer le tunnel et la protection Cloudflare

Dans <https://one.dash.cloudflare.com> (Zero Trust, offre gratuite) :

1. **Networks → Tunnels → Create a tunnel** → *Cloudflared* → nomme-le `dsh`.
   Copie le **jeton** du tunnel dans `.env`, ligne `CLOUDFLARE_TUNNEL_TOKEN=`.
2. Dans le tunnel, **Public hostname** :
   - sous-domaine `dsh`, ton domaine (ex. `dsh.mondomaine.com`) ;
   - service **HTTP**, URL `127.0.0.1:3080`.
3. **Access → Applications → Add → Self-hosted** :
   - domaine : le même `dsh.mondomaine.com` ;
   - politique **Allow**, règle *Emails* = ton adresse e-mail ;
   - méthode de connexion : *One-time PIN* (code reçu par e-mail).
4. Dans `.env`, mets `DSH_PUBLIC_HOST=dsh.mondomaine.com`.

## 5. Compiler et lancer le harness

```bash
cd ~/deepseek-harness
DSH_COMMIT=$(git rev-parse HEAD) docker compose -f deploy/oracle/compose.yml up -d --build
```

La première compilation prend du temps (comptes 20 à 40 minutes sur 2 OCPU).
Ensuite, récupère l'adresse de connexion, qui contient un **jeton de lancement**
valable pour ce démarrage du processus :

```bash
docker compose -f deploy/oracle/compose.yml logs dsh | grep "dsh web"
```

Ouvre cette adresse dans ton navigateur : Cloudflare demande d'abord ton code
e-mail, puis le harness échange le jeton contre un cookie de session. Ne partage
jamais cette adresse : le jeton donne accès au harness.

## 6. Vérifier que tout est correct

Ces contrôles ne dépendent ni de toi ni de moi :

| Vérification | Commande | Résultat attendu |
|---|---|---|
| Services en marche | `docker compose -f deploy/oracle/compose.yml ps` | `freellmapi` *healthy*, `dsh` et `cloudflared` *running* |
| Aucun port public à part SSH | `sudo ss -tlnp` | seulement `:22` sur `0.0.0.0` ; `3001` et `3080` sur `127.0.0.1` |
| Protection Cloudflare active | depuis ton PC : `curl -sI https://dsh.mondomaine.com` | une redirection (`302`) vers `cloudflareaccess.com`, jamais `200` |
| FreeLLMAPI exige sa clé | sur la VM : `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3001/v1/models` | `401` |
| L'agent répond | dans l'interface : « crée un fichier NOTE.md contenant BANANE-42, relis-le et donne-moi le code » | la réponse `BANANE-42` |
| Aucun secret dans git | `git status --short deploy/oracle` | `.env` n'apparaît pas (il est ignoré) |

## Mettre à jour

```bash
cd ~/deepseek-harness && git pull
DSH_COMMIT=$(git rev-parse HEAD) docker compose -f deploy/oracle/compose.yml up -d --build
```

Pour FreeLLMAPI, change la version de l'image dans `compose.yml`, puis
`docker compose -f deploy/oracle/compose.yml up -d freellmapi`.

## Sauvegarder

Les données vivent dans trois volumes Docker : `freellmapi-data` (clés chiffrées et
historique), `dsh-home` (sessions et profil du harness) et `dsh-workspace` (fichiers
sur lesquels l'agent travaille). Exemple de sauvegarde de FreeLLMAPI :

```bash
docker run --rm -v oracle_freellmapi-data:/data -v "$PWD":/backup busybox \
  tar czf /backup/freellmapi-$(date +%F).tgz -C /data .
```

## Sécurité

- Le harness **exécute des commandes** demandées par le modèle. Il tourne dans un
  conteneur, en utilisateur non-root, et seule sa zone `/workspace` persiste ; ne
  monte jamais de dossier sensible de la VM dedans.
- Ne retire jamais Cloudflare Access, et ne publie jamais les ports `3001` ou `3080`
  sur `0.0.0.0`.
- Dans Cloudflare, active *SSL/TLS → Edge Certificates → Always Use HTTPS* : le
  cookie de session du harness (`HttpOnly`, `SameSite=Strict`) n'a pas l'attribut
  `Secure`, car le harness sert du HTTP simple derrière le tunnel.
- N'utilise pas de modèle sans refus (voir `tools/skills/heretic`) sur ce serveur.
- Le fichier `.env` contient tous les secrets : il reste sur la VM, en `chmod 600`.
