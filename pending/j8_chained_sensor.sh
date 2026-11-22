#!/usr/bin/env bash
# BUT : J8 = init capteur COMPLÈTE (patch, params, calib 0x5b, 2e passe = j5c UPTO=pass2, éprouvé n=2 sur seal frais)
#       sur un boot CHAÎNÉ (store servi, lockers SANS UUID = défaut de sepd, vérifié J7b n=2), sbio ouvert TÔT
#       (SBIO_OPEN=1, obligatoire en chaîné : J3/J3b). Premier pas vers un Touch ID qui survit au reboot : capteur au
#       « repos final de macOS » SANS re-sceller (l'enrôlement futur ne serait pas effacé au boot suivant).
# PRÉREQUIS : J7c a donné « VERDICT sbio : VIVANT » (ouverture de skdl/sks/scrd non nécessaire). Le module refuse
#       allow_sks avec le relais capteur : si J7c est MUET, NE PAS lancer J8 (il faudra d'abord étendre le module).
# ENDPOINTS TOUCHÉS : ceux de j5c UPTO=pass2 (0xFF/0xFE, 0x00, 0x13, 0x08 relais + params + 0x5b + 0x19/2e passe) ;
#       xART = store chaîné servi. Rien vers 0x12/0x17/0x0a. Pas de 0x03 (allow_sbio_bio=0).
# RISQUE : écriture SEP, SCRIPT NEUF = combinaison de deux chemins éprouvés (boot chaîné J7b + init capteur j5c pass2),
#       jamais faite ensemble. Inconnu : l'init capteur se comporte-t-elle pareil sur un état rechargé (patch, 0x63) ?
#       Fail-closed de sbiod/du noyau inchangé. SAVE possibles (acquittés) → store copié avant. Power-cycle = Albert.
# RÉSULTAT ATTENDU : sepd.log = J7b (4 lockers sans UUID, 0 SAVE) ; sbiod « VERDICT : 2e passe terminée, capteur au repos
#       final de macOS (… 0x63 ×2 = référence macOS) » ; sinon « arrêt (fail-closed) : <raison> » (à comparer au seal frais).
# PRÉPARÉ PAR : Claude (session ALARM), 2026-11-23. JAMAIS LANCÉ. 1er run = « go » d'Albert, et seulement après J7c VIVANT.
#
# Usage (root, après un power-cycle + boot normal avec alias sep) :
#   pending/j8_chained_sensor.sh STORE      (ex. /var/lib/sepd-run-20261122-230441)
# Binaires : ceux de j5c (dans $J5) ; $J5/sepd sha256 6ad1992f12b0d300b37b6b20ba2e9e3c0cc44d4e02bd7b74ce031cc958e37f4a
set -euo pipefail
J5=${J5:-/home/albert/kbuild/j5}
REPO=$(cd "$(dirname "$0")/.." && pwd)
WANT_SEPD=6ad1992f12b0d300b37b6b20ba2e9e3c0cc44d4e02bd7b74ce031cc958e37f4a
STORE=${1:?usage: $0 STORE (store xART d un seal frais reussi, non vide)}
[ "$(id -u)" = 0 ] || { echo "à lancer en root"; exit 1; }
[ -d "$STORE" ] && ls "$STORE"/master_*.bin >/dev/null 2>&1 && ls "$STORE"/locker_save_*.bin >/dev/null 2>&1 \
  || { echo "STORE $STORE : pas un store chaîné complet (master_*.bin + locker_save_*.bin)"; exit 1; }
[ "$(sha256sum "$J5/sepd" | cut -d' ' -f1)" = "$WANT_SEPD" ] || { echo "$J5/sepd n'est pas le binaire relu (sha256, défaut sans UUID)"; exit 1; }
[ -s /etc/sepd/os_uuid ] || { echo "/etc/sepd/os_uuid absent : un store chaîné exige l'UUID du run qui l'a scellé"; exit 1; }
BAK="${STORE%/}.avant-j8-$(date +%Y%m%d-%H%M%S)"; cp -a "$STORE" "$BAK"; echo "copie du store avant run : $BAK"
ALLOW_CHAINED=1 SBIO_OPEN=1 UPTO=pass2 exec "$REPO/pending/j5c_params_run.sh" "$STORE"
