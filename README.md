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
- [ ] 3. CI : build, SBOM, signature de l'image, scan IaC
- [ ] 4. Kyverno : refus des images non signées
- [ ] 5. Gestion des secrets
- [ ] 6. GitOps avec Argo CD
- [ ] 7. Détection à l'exécution avec Falco
- [ ] 8. Terraform pour piloter le tout

## Démarrage

Prérequis : Docker, `kind`, `kubectl`.

```bash
./scripts/cluster-up.sh            # crée le cluster
./scripts/build-load-image.sh      # construit l'image TaskVault et la charge dans kind
./scripts/create-dev-secrets.sh    # secrets aléatoires (jamais écrits sur disque ni dans git)
kubectl apply -k k8s/base          # déploie
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
