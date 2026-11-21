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

- [ ] 1. Cluster local reproductible
- [ ] 2. Déploiement durci de TaskVault (NetworkPolicy, Pod Security, RBAC)
- [ ] 3. CI : build, SBOM, signature de l'image, scan IaC
- [ ] 4. Kyverno : refus des images non signées
- [ ] 5. Gestion des secrets
- [ ] 6. GitOps avec Argo CD
- [ ] 7. Détection à l'exécution avec Falco
- [ ] 8. Terraform pour piloter le tout

## Démarrage

Prérequis : Docker, `kind`, `kubectl`.

```bash
./scripts/cluster-up.sh     # crée le cluster
./scripts/cluster-down.sh   # le supprime
```
