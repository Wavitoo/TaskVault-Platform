# Exceptions Checkov

Chaque exception est une annotation `checkov.io/skip` dans le manifeste concerné, avec sa justification.
Une exception sans justification écrite est une vulnérabilité cachée.

| Règle | Ressource | Pourquoi | Quand ça disparaît |
|---|---|---|---|
| CKV_K8S_43 (image par digest) | backend | Image locale de dev dans kind | Étape 4 : digest signé depuis GHCR |
| CKV_K8S_15 (pull policy Always) | backend | Idem : l'image est chargée dans kind, pas tirée | Étape 4 |
| CKV_K8S_35 (secrets en fichiers) | backend, postgres | Le backend lit `process.env`, et on ne modifie pas TaskVault | Étape 5 : gestionnaire de secrets |
| CKV_K8S_40 (UID élevé) | postgres | L'image exige l'UID 70 (utilisateur présent dans `/etc/passwd`) pour `initdb` | Permanente (risque limité : non-root, pas de capabilities, FS en lecture seule) |

## Corrigées grâce à Checkov

- `postgres` : image épinglée par digest, `imagePullPolicy: Always`, sonde de liveness ajoutée.
- `backend` : UID 1000 -> 10001.
