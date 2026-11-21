# Journal d'incidents

Problèmes réellement rencontrés en construisant ce dépôt, avec cause et correction. Les causes **non établies** sont
indiquées comme telles : une cause supposée n'est pas une cause démontrée.

## 1. Le `default-deny` bloquait aussi les clients (étape 2)
- **Symptôme** : 4 tests sur 8 échouaient dès la première exécution de `verify-hardening.sh`.
- **Cause** : la politique `default-deny` couvrait aussi la sortie ; aucune règle n'autorisait un client à joindre le backend.
- **Correction** : politique `client-to-backend`. Deux tests passaient aussi **pour la mauvaise raison** (blocage par la
  mauvaise politique) : le cas « intrus » a été déplacé dans un autre namespace pour que seul l'ingress du backend puisse le bloquer.
- **Leçon** : un test négatif doit échouer *pour le motif attendu*.

## 2. Un test Pod Security cassé par `pipefail` (étape 2)
- **Cause** : `grep -q` ferme le tube, `kubectl` reçoit SIGPIPE, le pipeline retourne un code non nul sous `pipefail`.
- **Correction** : capturer la sortie dans une variable avant de la tester.

## 3. Checkov : 9 constats réels sur des manifestes que je croyais durcis (étape 3)
- Corrigés : image Postgres sans digest, sonde de liveness absente, UID trop bas. Les autres sont des exceptions
  justifiées une à une dans `docs/checkov-exceptions.md`. Les annotations de skip doivent être sur la ressource, pas sur le template du pod.

## 4. Kyverno : API dépréciée et nom d'attestor invalide (étape 4)
- `ClusterPolicy` est dépréciée en v1.20 au profit de `ImageValidatingPolicy` (CEL) ; utilisation de la nouvelle API.
- Un tiret dans le nom de l'attestor (`ci-keyless`) était lu comme une soustraction par CEL : renommé `ciKeyless`.

## 5. Falco : règle invalide, puis faux positif (étape 7)
- Un deux-points dans la description d'une règle faisait planter le démon (`LOAD_ERR_YAML_PARSE`) : le `helm upgrade --wait` échouait.
- Les sondes de santé PostgreSQL (`sh -c pg_isready`) déclenchaient la règle « shell » toutes les quelques secondes
  (alert fatigue). Exclusion par **égalité stricte** sur la ligne de commande complète (un préfixe permettrait de camoufler une commande).
- Le premier démarrage de PostgreSQL (`initdb`) lance aussi des `sh` légitimes : alertes attendues une fois à l'initialisation.

## 6. `terraform destroy` expirait sur External Secrets (étape 8)
- **Cause** : Argo CD et External Secrets créent des ressources (applications, `ExternalSecret` avec finalizers) hors de
  Terraform. Désinstaller External Secrets d'abord supprime le contrôleur qui doit les finaliser : la désinstallation
  expire et laisse les CRD bloquées en suppression. Le `apply` suivant échouait alors (« resource not found »).
- **Correction** : `scripts/teardown.sh`, exécuté par Terraform avant la désinstallation des releases. Vérifié par un cycle
  complet `destroy` puis `apply`, y compris depuis un état cassé.

## 7. Tests Falco en échec juste après une reconstruction (étape 8) : cause non établie
- **Symptôme** : à deux reprises, les 3 tests de détection échouaient (21/24) dans les minutes suivant une reconstruction ;
  les relances suivantes passaient (24/24).
- **Hypothèses testées** : métadonnées Kubernetes en retard sur un pod neuf (réfutée : détection immédiate sur un pod redémarré) ;
  sélection d'un pod en cours de suppression après le test de dérive (non reproduite sur 4 essais).
- **Action** : sélection de la cible durcie (attendre exactement 2 backends prêts, aucun en suppression) ; cycle complet
  rejoué ensuite avec 24/24. **La cause exacte reste inconnue.**

## 8. La CI ne démarrait pas, ou échouait pour une permission manquante
- Après un `push` sur une PR ouverte, GitHub n'a parfois lancé aucun run (PR n°8 et n°9). Fermer puis rouvrir la PR le
  redéclenche. Cause non établie.
- Gitleaks échouait avec `Resource not accessible by integration` : l'action liste les commits de la PR et exige
  `pull-requests: read`. Permission ajoutée à ce seul job (moindre privilège).

## 9. Le rescan a trouvé 2 failles corrigeables dans l'image déjà déployée
- **Constat** : au premier rescan Trivy de l'image déployée, `proxy-addr` 2.0.7 (CVE-2026-90711, CRITICAL, usurpation d'IP,
  corrigé en 2.0.8) et `body-parser` 2.3.0 (CVE-2026-111181, HIGH, déni de service, corrigé en 2.4.0). Ces dépendances sont dans le
  code de TaskVault et sont apparues après sa construction.
- **Intérêt** : un contrôle effectué une seule fois à la construction n'aurait rien vu. C'est la raison d'être du rescan planifié.
- **Statut** : **ouvert**. La correction se fait dans le dépôt TaskVault (mise à jour des dépendances), puis nouvelle image
  et mise à jour du digest ici.

## 10. Argo CD : correction de dérive parfois différée
- Après des changements manuels répétés et rapprochés, le retour à l'état de Git a pris plus longtemps que d'habitude
  (réplicas restés à 5 un moment, application `OutOfSync`) avant de se corriger seul. Cause non investiguée.
