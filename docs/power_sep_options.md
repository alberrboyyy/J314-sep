# Veille / hibernation et le SEP : ce que ça donnerait

But : répondre à « le SEP peut-il régler la batterie qui se vide la nuit en veille ? ». Analyse hors ligne (nos traces
+ doc publique). Aucune action matérielle. Rien ne sort vers Asahi (projet privé) ; on ne fait que lire le public.

## Le vrai symptôme d'Albert
Charge la nuit, retrouve ~50 % le matin. C'est la **veille (s2idle) qui consomme trop**, pas un défaut d'hibernation.

## Ce que dit le public (sources en bas)
- Asahi Linux n'a que **s2idle** (veille légère) : elle consomme ~1,3 à 2 W, donc **vide la batterie en une nuit** (rapports
  utilisateurs M1 Pro/M2/M3 : 3-4 %/h, ou 30 %→0 % en une nuit). C'est exactement le symptôme d'Albert.
- Les Mac Apple Silicon **ont** un vrai sommeil profond (type S3) que macOS utilise ; **Asahi ne l'a pas encore implémenté**.
  Le blocage est la **gestion d'alimentation des périphériques** (historiquement le Wi-Fi), **pas le SEP**. Un contributeur
  Fedora le dit clairement : « suspend vs s2idle est un faux problème ; le vrai prérequis est la bonne gestion d'alimentation
  des périphériques ». Le noyau Asahi 7.0 a déjà gagné ~20 % d'autonomie au repos (économies PMP, pas encore activées par défaut).
- **Hibernation (suspend-to-disk)** : autre fonction, absente elle aussi d'Asahi. Sur Apple Silicon, le SEP génère la clé de
  chiffrement de volume (VEK) + le jeton anti-rejeu (xART) par volume APFS. Mais **aucune source publique** ne décrit comment la
  clé de l'image d'hibernation est scellée sur Apple Silicon, ni ce que fait l'endpoint `hibe`.

## Ce que nos traces disent de `hibe` (EP 0x14)
- `hibe` est **annoncé** au boot (7 EP présents même sans le coffre xART — donc PAS bloqué par le mur du Touch ID, c'était la
  bonne intuition). **Mais** : dans nos 23 captures, `hibe` n'a **jamais** échangé un seul message (juste l'annonce de nom).
  macOS n'a pas hiberné pendant nos captures → **on ne sait rien de son protocole**.

## Verdict honnête
1. **Pour TON problème (batterie la nuit), le SEP n'est probablement pas le bon levier.** Le vrai fix, c'est le **sommeil
   profond (S3) / la gestion d'alimentation des périphériques** dans le noyau Asahi — un sujet de *power management*, pas de SEP.
   C'est activement travaillé en amont (gains déjà là, pas encore par défaut). Ça ne passe pas par ce projet.
2. **Le SEP/`hibe` pour une vraie hibernation** reste possible sur le papier (pas derrière le coffre xART, contrairement au
   Touch ID), mais c'est un **pari** : zéro donnée sur `hibe`, il faudrait d'abord le capturer pendant une vraie hibernation
   macOS (écoute, lecture seule), et l'utiliser voudrait dire **écrire vers le SEP** (ligne rouge → `pending/` + Albert).
3. Donc : si l'objectif est « ne plus perdre 50 % la nuit », le chemin rapide et réaliste **n'est pas** le SEP. Le SEP n'aiderait
   que pour une hibernation complète, qui est un plus gros chantier et spéculatif.

## Si on veut quand même creuser le SEP côté hibernation (ordre sûr)
- [ ] Capturer `hibe` pendant une **vraie hibernation macOS** sous hyperviseur (lecture seule, comme la voie B xART ; demande
      l'USB + Albert, et savoir déclencher une hibernation macOS, ce que macOS Apple Silicon ne fait quasiment jamais tout seul).
- [ ] Lire ce qu'Asahi/m1n1 disent déjà de `hibe` dans leur code public (hors ligne).
- [ ] Rien d'autre tant qu'on n'a pas vu un échange `hibe`.

## Sources (publiques)
- Asahi Linux, rapport nov. 2022 (s2idle, S3 possible mais non fait) : https://asahilinux.org/2022/11/november-2022-report/
- Asahi, Apple Silicon Platform Security (VEK/xART par volume) : https://asahilinux.org/docs/platform/security/
- Noyau 7.0, −20 % de conso au repos : https://ostechnix.com/linux-kernel-7-m1-pro-battery-drain-fix/
- Rapports utilisateurs de conso en veille (anecdotiques) : discussion Fedora et issues GitHub (s2idle ~1,3-2 W).
