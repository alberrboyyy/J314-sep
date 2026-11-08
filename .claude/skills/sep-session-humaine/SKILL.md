---
name: sep-session-humaine
description: Préparer et mener une capture qui demande Albert (doigt sur le capteur, mot de passe, mauvais doigt, action physique) : protocole avec marqueurs horaires, consignes courtes, suivi en direct. À utiliser pour toute EXPÉRIENCE HUMAINE.
---

# Session humaine (Touch ID)

Albert veut que tout ce qui peut être automatisé le soit ; ne lui demander que ce que le PC ne peut pas faire,
en étapes courtes et numérotées, une action par ligne.

## Préparer
0. Pour appeler Albert (à chaque fois qu'il doit agir) : `./tools/appel_albert.sh "consigne courte"` — fenêtre
   animée et drôle sur le bureau 2 (Hyprland) + ding + notification. C'est sa demande (2026-11-08).
1. Protocole écrit dans `docs/hypotheses.md` (section « EXPÉRIENCE HUMAINE ») par le sceptique : étapes, étiquettes,
   résultat attendu de chaque étape.
2. Vérifier les ports (skill `sep-capture`), lancer la capture en mode auto avec un `TRACE_TIMEOUT` assez long
   pour tout le protocole + boot (~3 min de boot sous HV, le Mac est lent).
3. Donner à Albert :
   - le moment où commencer (écran de connexion visible) ;
   - pour chaque action : `./tools/mark.sh <étiquette>` sur le PC, PUIS l'action sur le Mac ;
   - quoi suivre en direct : `tail -F traces/<dossier>/sep.log` (ou le résumé live affiché par le script).

## Rappels macOS
- Après un boot, le 1er login exige le mot de passe (Touch ID refusé tant que l'utilisateur n'a pas tapé son mot de passe).
- Mauvais doigt : après plusieurs échecs, macOS exige le mot de passe — prévoir l'étiquette correspondante.

## Après
- Noter dans `docs/journal.md` ce qu'Albert rapporte (succès/échec de chaque essai, ressenti de lenteur), avec les
  heures des marques. Lui demander ce qui manque plutôt que de supposer.
- Lancer l'analyse (skill `sep-analyse`) avec `--between` sur les marques.
