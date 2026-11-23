# Service sep-touchid : SEP + capteur Touch ID au démarrage de Linux

Fichiers : `driver/linux/service/` (script `sep-touchid-boot.sh`, unité `sep-touchid.service`, liste `SHA256SUMS`)
et l'installeur `pending/install_sep_touchid_service.sh`. Préparé le 2026-11-23, **jamais lancé**.

## Ce que fait le service

À chaque démarrage, il rejoue le chemin vérifié J8 (journal 2026-11-23 00:30 et 00:58, n=2) :
boot de SEPOS, xART servi par `sepd` depuis le store (lockers sans UUID), sbio ouvert tôt, init capteur complète
(patch, paramètres, calibration 0x5b, 2e passe). Ensuite `sepd` reste actif pour répondre au xART.
Il n'envoie jamais rien vers SKS (0x12), ni de 0x03 (enrôlement).

Avant le premier mot au SEP, il vérifie tout et s'arrête à la première incohérence :
- noyau : `sep_native` pas encore chargé dans ce boot, aucun `sepd` / `sbiod` en cours ;
- binaires : sha256 = `SHA256SUMS` (les binaires de J8), modules compilés pour le noyau courant ;
- `/etc/sepd/os_uuid` = `4c494e55580000000000000000000000` (l'UUID du seal qui a créé le store) ;
- store complet (`master_*.bin` + `locker_save_*.bin`) et égal au dernier état connu (voir plus bas) ;
- mailbox et DART du SEP déjà liées (sinon le démarrage du SEP pourrait se faire plus tard, sans `sepd`).

Le boot de Linux ne dépend pas du service : `Type=simple`, pas de relance automatique, pas de dépendance d'autres
unités. En cas d'échec, l'unité passe en « failed » et Linux continue normalement.

## Où sont les choses

| Quoi | Où |
|---|---|
| binaires, script, `SHA256SUMS` | `/usr/local/lib/sep-touchid/` |
| store xART (emplacement fixe) | `/var/lib/sepd/` (`sepd.log` de `sepd` y est aussi) |
| état anti-retour | `/var/lib/sep-touchid/state` et `/var/lib/sepd/sep-touchid.generation` |
| sauvegardes du store | `/var/lib/sep-touchid/backups/sepd-<date>-gen<N>/` (les 10 dernières) |
| store mis de côté par un seal frais | `/var/lib/sep-touchid/avant-seal-frais-<date>-gen<N>/` (jamais supprimé) |
| journaux | `journalctl -u sep-touchid` et `/var/log/sep-touchid/<date>/` (`run.log`, `sbiod.log`, `kernel.log` ; les 30 derniers) |
| statut du boot en cours | `systemctl status sep-touchid` ou `/run/sep-touchid/status` |
| désactiver | `/etc/sep-touchid/disabled` (fichier vide), ou `sep_touchid=off` sur la ligne de commande du noyau |

## Installer

Dans un boot où `sepd` ne tourne pas (après un `reboot`, sans lancer de run SEP), en root :

```
pending/install_sep_touchid_service.sh install            # installe, N'ACTIVE PAS
/usr/local/lib/sep-touchid/sep-touchid-boot.sh check      # revérifie, n'envoie rien au SEP
systemctl enable sep-touchid.service                      # ou : install --enable
reboot
```

L'installeur ne supprime rien. Il copie le store actuel (`/var/lib/sepd-run-20261122-230441` par défaut) vers
`/var/lib/sepd`. Il vérifie d'abord que ce store est identique à sa dernière copie `.avant-*`. Le `/var/lib/sepd`
déjà présent est **renommé** en `/var/lib/sepd.ancien-avant-service-<date>`. C'est un vieux store, du run J4 du
2026-11-22 à 18:38 : il ne faut pas le remettre en service.

Mettre à jour les binaires : recompiler, mettre à jour `driver/linux/service/SHA256SUMS` (après relecture), puis
`uninstall` et `install --reuse-store` (le store et l'état restent tels quels).

## Désinstaller

```
pending/install_sep_touchid_service.sh uninstall
```

Cette commande retire l'unité et `/usr/local/lib/sep-touchid`. Elle garde le store, l'état, les sauvegardes et les
journaux. Si `sepd` tourne déjà, il n'est pas arrêté : un `reboot` remet le SEP en ROM.

## Seal frais volontaire (efface l'enrôlement)

Un seal frais fait sceller au SEP un état neuf. Tout enrôlement lié à l'ancien état est perdu. Le service ne le
fait jamais seul : si le store est vide, il refuse de démarrer. Pour le faire à la main :

1. démarrer Linux sans le service (créer `/etc/sep-touchid/disabled`, ou `sep_touchid=off`), puis en root :
2. `/usr/local/lib/sep-touchid/sep-touchid-boot.sh fresh-seal --erase-enrollment`
   - l'ancien store est déplacé dans `/var/lib/sep-touchid/avant-seal-frais-…` (pas supprimé) ;
   - le SEP scelle un état neuf (chemin des runs J5c pass2 sur store vide : ouverture sbio tardive) ;
   - le script reste au premier plan tant que `sepd` tourne ; Ctrl-C pour finir ;
3. retirer `/etc/sep-touchid/disabled`, puis `reboot`.

## Ne jamais restaurer un vieux store

Le SEP met à jour son état scellé par des SAVE xART, que `sepd` écrit dans le store. Après un SAVE, les copies
d'avant ne correspondent plus à l'état du SEP. Rendre une vieille copie, c'est demander au SEP de revenir en arrière.
L'anti-rejeu du SEP le refuserait probablement (hypothèse, `docs/gigalocker.md`, `verification_status.md`
xART-CHAIN). Un cas proche a été vu : avec un coffre périmé (essai FOLLOW sous m1n1, `hypotheses.md` HV1-B), le SEP
a re-scellé au lieu de reprendre l'état. Un re-scellement ferait probablement perdre l'enrôlement (déduit, non testé).

Garde-fou : à chaque changement du store, le service augmente un compteur de génération. Il l'écrit dans `state`
(hors du store) puis dans le store. Au démarrage, il refuse :
- un store de génération plus ancienne (une sauvegarde remise en place) ;
- un contenu différent du dernier connu ;
- un store sans marqueur.

On peut restaurer la **dernière** sauvegarde si aucun SAVE n'a eu lieu depuis : elle a la même génération et le même
contenu, donc elle passe. Pour faire accepter un store réparé à la main :
`sep-touchid-boot.sh accept-store --i-understand-rollback-risk`.

Limite : si tout `/var/lib` est remis en arrière d'un coup (par exemple par un snapshot), l'état revient en arrière
avec le store et ce garde-fou ne voit rien. Les sauvegardes du store ne servent qu'en cas de fichier perdu ou abîmé.

## Arrêt et relance

- `systemctl stop sep-touchid` arrête `sepd` et éteint le capteur. Le SEP reste démarré. Un `start` dans le même
  boot est refusé : il faut faire un `reboot`. Un simple `reboot` suffit à remettre le SEP en ROM
  (`docs/sep_reconnect.md`, et J8 n=2 après un reboot). Aucun power-cycle n'est nécessaire.
- Mise à jour du noyau : les modules sont compilés pour une version précise du noyau. Avec un autre noyau, le
  service refuse de démarrer (vermagic). Il faut recompiler, puis réinstaller.
