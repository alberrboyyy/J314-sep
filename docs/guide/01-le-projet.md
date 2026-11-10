# 1. Le projet

## En bref
On essaie de faire parler **Linux** à la puce de sécurité d'un MacBook Pro, pour, à terme,
faire marcher **Touch ID** (le lecteur d'empreinte) sous Linux. C'est un projet perso,
privé, de rétro-ingénierie : personne ne nous a donné la notice, on l'apprend en observant.

## La machine
Un **MacBook Pro 14 pouces, puce M1 Max**. C'est un Mac Apple Silicon : tout est très
intégré, et Apple ne documente pas comment ses composants internes se parlent. Le projet
vit dans ce dépôt, sur le PC, et pilote le Mac à distance pour l'observer.

## Les deux acteurs de l'histoire
- **Le processeur principal** : c'est là que tourne le système (macOS, ou Linux). On l'appelle
  « le côté principal ». C'est le gros cerveau, mais il n'a pas le droit de tout voir.
- **La puce de sécurité (le « SEP »)** : un petit ordinateur séparé, enfermé, qui garde les
  secrets — empreintes, clés de chiffrement du disque, etc. Le côté principal ne peut pas
  entrer dedans ; il peut seulement lui **envoyer des messages** et attendre les réponses.

Touch ID, ce n'est pas « le capteur lit ton doigt et dit oui ». C'est : le capteur et la puce
de sécurité discutent **en secret**, la puce compare l'empreinte **chez elle**, et annonce juste
le verdict. Le doigt ne sort jamais en clair. C'est voulu : c'est ce qui rend Touch ID sûr.

## Le but, honnêtement
- **But idéal** : déverrouiller par l'empreinte sous Linux, comme sous macOS.
- **But réaliste déjà atteint** : faire que **Linux allume le capteur et lui parle**. ✅
- **Entre les deux** : un mur, qu'on décrit au chapitre 5. La bonne nouvelle, c'est qu'il
  reste **une seule vraie question** à trancher pour savoir si le but idéal est possible.

## Pourquoi c'est intéressant
- Sous Linux (projet Asahi), le Mac marche déjà très bien — mais **pas Touch ID**. Ce serait
  une première.
- En chemin, on apprend à parler à la puce de sécurité. Ça pourrait **servir à d'autres choses**
  que l'empreinte (on explore, voir les chapitres suivants).
- Et c'est un beau défi : comprendre un système fermé, juste en l'écoutant, sans jamais tricher.

## Ce qu'on s'interdit (le cadre)
Le projet a des **lignes rouges** strictes, détaillées au chapitre 7. En résumé : on observe
beaucoup, on n'abîme jamais le Mac, et toute action qui pourrait être risquée est préparée
puis lancée **à la main par le propriétaire**, jamais en automatique. Deux priorités absolues :
**ne jamais rendre le Mac inutilisable**, et **ne jamais perdre la partition Linux**.

---
Chapitre suivant : *Comment ça marche* — comment le côté principal et la puce de sécurité
se parlent, et où le capteur d'empreinte entre en jeu. (à venir)
