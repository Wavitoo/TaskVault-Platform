# Politique de sécurité

Projet personnel de démonstration (plateforme de déploiement sécurisé de TaskVault sur un cluster local).
Il n'héberge aucune donnée réelle.

## Signaler une vulnérabilité

Utiliser le **signalement privé de vulnérabilité** de GitHub (onglet *Security* > *Report a vulnerability*) plutôt
qu'une issue publique, afin qu'un correctif puisse être préparé avant divulgation.

## Contrôles automatiques et seuils

| Contrôle | Où | Seuil |
|---|---|---|
| Checkov (Kubernetes, Terraform) | CI, chaque PR | Toute vérification échouée bloque ; les exceptions sont justifiées dans `docs/checkov-exceptions.md` |
| Gitleaks (historique complet) | CI, chaque PR | Tout secret détecté bloque |
| GitHub secret scanning + push protection | Dépôt | Bloque le push d'un secret connu |
| Trivy sur l'image déployée | Hebdomadaire (`scheduled-scan.yml`) | Faille CRITICAL/HIGH corrigeable : échec et e-mail |
| Signature Cosign + Kyverno | Merge sur `main` / admission | Image non signée par la CI : refusée |
| Dependabot | Hebdomadaire | PR de mise à jour des actions et providers Terraform |

`main` est protégée : PR obligatoire, 4 contrôles obligatoires, y compris pour l'administrateur.

## Limites assumées

Voir le modèle de menaces (`docs/threat-model.md`) et le journal d'incidents (`docs/incidents.md`).
