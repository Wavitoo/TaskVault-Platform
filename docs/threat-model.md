# Modèle de menaces (STRIDE) : TaskVault-Platform

Périmètre : le déploiement et l'exécution de TaskVault (cluster, chaîne de livraison, secrets, GitOps).
Le modèle du code applicatif est dans le dépôt TaskVault. Statuts : **Atténuée** (contrôle en place et testé),
**Partielle** (réduit mais pas éliminé), **Acceptée** (choix assumé, documenté), **Ouverte** (reste à traiter).

| # | STRIDE | Menace | Contrôle | Preuve | Statut |
|---|---|---|---|---|---|
| 1 | Spoofing | Une image falsifiée est déployée à la place de celle de la CI | Cosign keyless + politique Kyverno : identité du signataire = `ci.yml` sur `main` | Test : une image GHCR signée par un autre signataire est refusée (« none of the expected identities matched ») | Atténuée |
| 2 | Tampering | L'image est modifiée après le build, ou un tag est déplacé | Signature sur le **digest**, déploiement par digest, `imagePullPolicy: Always` | `cosign verify` sur le digest ; Checkov CKV_K8S_43 | Atténuée |
| 3 | Tampering | Modification manuelle du cluster hors de Git | Argo CD `selfHeal` + `prune` | Test : 5 réplicas remis à 2 | Atténuée |
| 4 | Tampering | Un secret est commité dans Git | Aucun objet `Secret` versionné (références `ExternalSecret` seulement), Gitleaks, push protection | Test : aucun `kind: Secret` dans le dépôt ; Gitleaks en CI | Atténuée |
| 5 | Repudiation | On ne sait pas qui a exécuté une commande dans un conteneur | Falco alerte (shell, outil réseau, lecture de `/proc/*/environ`) | Tests de détection | Partielle : pas d'audit log Kubernetes activé ni d'identité de l'utilisateur dans les alertes |
| 6 | Information disclosure | Accès direct à la base depuis un autre pod | NetworkPolicy `default-deny`, seul le backend atteint PostgreSQL | Tests : client et autre namespace bloqués | Atténuée |
| 7 | Information disclosure | Vol des secrets du backend via `/proc/*/environ` | Postgres lit des fichiers montés ; Falco détecte la lecture | Test de détection | Partielle : le backend lit `process.env` (TaskVault non modifié), donc la prévention n'est pas possible |
| 8 | Information disclosure | Jeton Vault d'External Secrets réutilisé ailleurs | Rôle lié au ServiceAccount, au namespace **et à l'audience `vault`** ; politique en lecture seule sur `taskvault/*` et `argocd/*` | Tests : lecture hors périmètre refusée, écriture refusée, jeton sans audience rejeté (`invalid audience (aud) claim`) | Atténuée |
| 9 | Denial of service | Un pod ou un déploiement qui s'emballe épuise le nœud | Limites CPU/mémoire, `LimitRange` (valeurs par défaut et plafond), `ResourceQuota` du namespace, `PodDisruptionBudget` (au moins 1 backend) | Tests : valeurs par défaut appliquées, pod au-delà du quota refusé (`exceeded quota`), 2e éviction refusée par le PDB ; chaque test vérifié par suppression volontaire du contrôle | Atténuée |
| 10 | Denial of service | Panne de Kyverno : plus aucun pod ne peut être créé | `failurePolicy: Fail` limitée au namespace `taskvault` | Configuration | Acceptée : sécurité préférée à la disponibilité, portée réduite |
| 11 | Elevation of privilege | Pod privilégié ou root, évasion de conteneur | Pod Security `restricted`, `drop ALL`, non-root, FS en lecture seule, seccomp | Tests : pod privilégié et pod non durci refusés | Atténuée |
| 12 | Elevation of privilege | Une application Argo CD déploie hors de son périmètre | `AppProject` : un seul dépôt, un seul namespace, 2 types de ressources globales | Test : destination `kube-system` refusée | Atténuée |
| 13 | Elevation of privilege | Compromission d'Argo CD (droits étendus sur le cluster) | Clé de déploiement en lecture seule ; contrôleur Argo avec ses droits par défaut | n/a | Acceptée : cluster local de démonstration |
| 14 | Supply chain | Action GitHub compromise (tag mobile) | Toutes les actions épinglées par SHA, mises à jour par Dependabot | `actionlint`, revue | Atténuée |
| 15 | Supply chain | Quelqu'un modifie `ci.yml` pour signer une image malveillante | Protection de `main` (PR + 4 contrôles, y compris admin) ; l'identité de signature inclut le chemin du workflow et la branche | Configuration GitHub | Atténuée |
| 16 | Supply chain | Faille publiée **après** le build dans une dépendance déjà déployée | Rescan Trivy hebdomadaire de l'image déployée | Le rescan a trouvé 2 failles corrigeables (voir `docs/incidents.md`, n°9) | **Corrigée** : image reconstruite, signée et déployée |
| 17 | Supply chain | Image tierce non signée (PostgreSQL, Docker Hub) | Épinglée par digest | Checkov | Partielle : Kyverno ne vérifie que `ghcr.io/*` |
| 18 | Information disclosure | Fuite via l'état Terraform local | `.gitignore` sur l'état et les clés ; l'état ne contient pas de secret applicatif | Revue | Acceptée : état local, un seul opérateur |
| 19 | Elevation of privilege | Vault en mode dev (token root connu, en mémoire) | Aucun | n/a | Acceptée : démonstration locale uniquement, pas de production |
