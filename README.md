# taskvault-platform

Plateforme de déploiement sécurisé pour [TaskVault](https://github.com/Wavitoo/devsecops-security-pipeline).

TaskVault prouve que le **code** est sécurisé avant fusion (SAST, SCA, secrets, conteneur, DAST).
Ce dépôt prouve que le **déploiement et l'exécution** le sont aussi : Kubernetes durci, chaîne
d'approvisionnement signée, secrets gérés, déploiement GitOps et détection à l'exécution.

> En construction. Tout tourne en local et gratuitement (cluster [kind](https://kind.sigs.k8s.io/)).

## Stack (100 % gratuite)

| Besoin | Outil |
|---|---|
| Cluster local | kind |
| Infrastructure as Code | Terraform (+ scan Checkov) |
| Politiques d'admission | Kyverno |
| Signature d'images, SBOM | Cosign, Syft |
| Secrets | HashiCorp Vault (mode dev) / External Secrets |
| GitOps | Argo CD |
| Détection à l'exécution | Falco |
| Registre d'images | GitHub Container Registry |

## Feuille de route

- [x] 1. Cluster local reproductible
- [x] 2. Déploiement durci de TaskVault (NetworkPolicy, Pod Security, RBAC)
- [x] 3. CI : build, SBOM, signature de l'image, scan IaC
- [x] 4. Kyverno : refus des images non signées
- [x] 5. Gestion des secrets
- [x] 6. GitOps avec Argo CD
- [ ] 7. Détection à l'exécution avec Falco
- [ ] 8. Terraform pour piloter le tout

## Chaîne d'approvisionnement (CI)

À chaque PR : scan **Checkov** des manifestes (bloquant) et build de l'image. À chaque merge sur `main` :
build de l'image TaskVault (commit épinglé dans `taskvault.ref`), push sur GHCR, **SBOM** (Syft, SPDX),
**signature Cosign sans clé** (identité = ce workflow, via OIDC GitHub) sur le *digest*, puis
vérification de la signature dans le pipeline lui-même. Les exceptions Checkov sont justifiées
dans [docs/checkov-exceptions.md](docs/checkov-exceptions.md). Toutes les actions sont épinglées par SHA.

## Admission : seules les images signées entrent

Une politique Kyverno (`k8s/policies/verify-images.yaml`) refuse tout pod du namespace `taskvault` dont
l'image GHCR n'est pas signée par le workflow `ci.yml` de ce dépôt sur `main`. Vérifié par des tests :
l'image du backend signée par la CI est admise, une image GHCR signée par un autre signataire est refusée
avec le motif « identité non reconnue ».

**Limites connues** : la politique ne couvre que les images de `ghcr.io/*` (l'image Postgres de Docker Hub est
seulement épinglée par digest) ; une liste blanche de registres serait l'étape suivante. Avec `failurePolicy: Fail`,
une panne de Kyverno bloque les créations de pods dans `taskvault` (choix sécurité > disponibilité, limité à ce namespace).

## Secrets : Vault + External Secrets

Plus aucun secret dans git ni créé à la main. Les valeurs sont générées aléatoirement dans **Vault**
(`scripts/configure-vault.sh`), et **External Secrets Operator** les copie dans des Secrets Kubernetes.
ESO s'authentifie auprès de Vault avec le jeton de son ServiceAccount (aucun token statique) et sa politique
est en **lecture seule sur `secret/taskvault/*`** uniquement. Seules des *références* (`ExternalSecret`) sont versionnées.
Postgres lit ses identifiants depuis des fichiers montés, pas depuis des variables d'environnement.

**Limites connues** : Vault tourne en **mode dev** (en mémoire, token root connu, aucune persistance) : c'est
une démonstration locale, pas une configuration de production (il faudrait stockage Raft, unseal automatique, TLS).
Le backend lit ses secrets en variables d'environnement (on ne modifie pas TaskVault), donc un changement dans Vault
n'atteint les pods qu'au redémarrage.

## GitOps : Git est la source de vérité

**Argo CD** déploie le cluster depuis ce dépôt (`main`). On n'exécute plus `kubectl apply` : on fait une PR.
Une seule ressource est appliquée à la main (l'application racine) ; elle déploie le reste
(*app of apps*), dans un ordre imposé par des *sync-waves* : namespace, puis politiques Kyverno, puis secrets,
puis application. Les politiques passent donc **avant** l'application.

- `selfHeal` : une modification manuelle du cluster est annulée (testé : 5 réplicas remis à 2).
- `prune` : une ressource supprimée de Git est supprimée du cluster.
- Un **AppProject** limite les applications à ce dépôt, au namespace `taskvault` et à deux types de ressources
  globales. Argo CD lit le dépôt avec une **clé de déploiement en lecture seule**, stockée dans Vault et livrée par ESO.
- Accès à l'interface : `kubectl -n argocd port-forward svc/argocd-server 8080:443`.

**Limites connues** : l'application racine et la clé de déploiement sont posées par un script de bootstrap (poule et œuf :
Argo ne peut pas se déployer lui-même avant d'avoir accès au dépôt). Le digest de l'image est mis à jour à la main dans
`k8s/base/backend.yaml`. Une automatisation (Argo CD Image Updater ou PR automatique) serait la suite.

## Démarrage

Prérequis : Docker, `kind`, `kubectl`.

```bash
./scripts/cluster-up.sh            # crée le cluster
./scripts/install-kyverno.sh       # Kyverno (moteur de politiques)
./scripts/install-secrets.sh       # Vault (dev) + External Secrets + secrets aléatoires
./scripts/install-argocd.sh        # Argo CD : déploie tout le reste depuis ce dépôt (GitOps)
./scripts/verify-hardening.sh      # prouve que les protections bloquent bien
./scripts/cluster-down.sh          # supprime le cluster
```

## Ce que le déploiement durci applique

| Contrôle | Effet |
|---|---|
| Pod Security Standards `restricted` | Un pod privilégié, root ou sans durcissement est refusé à la création |
| NetworkPolicy `default-deny` + règles ciblées | Seul le backend parle à la base ; la base n'est joignable de nulle part ailleurs |
| `runAsNonRoot`, `readOnlyRootFilesystem`, `drop ALL`, seccomp | Un conteneur compromis a très peu de pouvoir |
| ServiceAccount sans token | Aucun pod ne peut parler à l'API Kubernetes |
| Limites CPU/mémoire | Un pod ne peut pas affamer le nœud |
| Services `ClusterIP` uniquement | Rien n'est exposé hors du cluster (contrairement au `5432` du compose d'origine) |

`verify-hardening.sh` joue les bons **et** les mauvais cas : un contrôle jamais vu bloquer quelque chose
n'est pas une preuve.
