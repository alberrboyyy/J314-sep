#!/usr/bin/env bash
# BUT : J9b = J9a (boot chaîné natif, lockers sans UUID = sepd par défaut, skdl/sks/scrd ouverts par le CNTL, UN
#       get_capabilities accepté par le SEP — J9a vérifié matériel 2026-11-23 : état 0, theirs 2 → v2) + UNE SECONDE
#       transaction SKS : `set_env` (TAG 0x2a), la 2e du bring-up macOS (6/6), `> EP 0x12 TAG 0x2a TYPE 0x02 PARAM 0
#       DATA 0x04700000`, OOL A12 = 0x470 o construits d'après docs/sks_protocol.md §1.7 (source: kext 13.5, NON
#       vérifié matériel) par `sks_setenv run` : en-tête v2 (version négociée), état 0, u64 1, blob 0x40c o {version 1,
#       cpx-encryption-mode (ADT = 2), mode 4, 0x400 o nuls}, condensé SHA-256/16 v2 recalculé. Le noyau n'envoie le
#       set_env qu'APRÈS avoir reçu la réponse 0xcd du get_capabilities et vérifié que la version négociée est 2.
#       Écoute de la réponse 0xaa, RIEN d'autre envoyé à 0x12 / 0x17 / 0x0a, aucune réponse du pilote à un mot reçu.
#       Puis le 0x73 sbio comme J9a. docs/sks_native_plan.md §7.
#       Tranche : (a) le SEP accepte-t-il un set_env v2 construit sous Linux (champs processus neutres, cpx de l'ADT) ?
#       (b) avec quoi : PARAM (statut), état de la réponse 0x58 (en-tête 0x54 + état, L = 0x50, SANS u64 ni blob) ;
#       (c) la suite (0x73 sbio) change-t-elle ?
# ENDPOINTS TOUCHÉS : 0xFF/0xFE (boot), 0x00 (CNTL : SECMODE + tampons 0x13, 0x08, 0x17, 0x12, 0x0a, comme J9a),
#       0x13 (xART : store servi par sepd, lockers SANS UUID, SAVE acquittés si demandés), **0x12 : DEUX mots** (portes
#       noyau `sks_ipc::GetcapGate` puis `sks_setenv::SetenvGate` : ces deux mots exacts, une fois chacun ; A12 contrôlé
#       à chaque fois : constantes, condensé, forme du cdhash), 0x08 (UN mot 0x73). AUCUN mot à 0x17/0x0a. Pas de relais
#       (allow_sbio_relay=0). Paramètre : allow_sks=3.
# RISQUE : écriture SEP vers SKS (EP 0x12) — set_env est une CLASSE DE MESSAGE JAMAIS TESTÉE sur matériel (2e type 0x12
#       après get_capabilities) → 1er run = « go » d'Albert. set_env pose l'environnement du keystore (un mode de
#       protection de contenu lu dans l'ADT + des constantes + du zéro) : aucune clé, aucun keybag, aucun mot de passe,
#       aucune donnée de stockage ; le kext macOS ignore même le code de retour de set_env (il n'exige que l'état 0 de la
#       réponse). Au pire : PARAM/état ≠ 0 (refus), silence, ou un SEP qui se fige / panique jusqu'au reboot (SEPOS est
#       relancé par un `reboot` Linux normal, VU n=7 ; power-cycle = Albert). Effet sur l'état scellé : non attendu
#       (set_env n'est pas une opération de stockage) ; le store servi peut quand même être modifié par un SAVE (xART) :
#       copie faite AVANT (STORE.avant-j9b-<date>). macOS déjà déclaré sacrifiable (Albert 2026-11-22) ; filet :
#       alarm_p5.img + backup perso + DFU.
#       ⚠️ SERVICE : le service sep-touchid tient le SEP à chaque boot. AVANT ce run : `touch /etc/sep-touchid/disabled`
#       puis `reboot` (le service ne démarre pas : ConditionPathExists=!/etc/sep-touchid/disabled). APRÈS : vérifier que
#       le store du service n'a pas divergé (voir la fin du script), `rm /etc/sep-touchid/disabled`, puis `reboot`.
#       Ce script REFUSE de tourner si le service est actif, si sepd tourne, ou si STORE = /var/lib/sepd (store du
#       service, jamais servi ici).
# RÉSULTAT ATTENDU : sepd.log = J9a (4 lockers sans UUID ×2, op 0x07, 0 SAVE) ; dmesg « 'sks' ouvert », « sks getcap :
#       requête acceptée », « VERDICT sks getcap : RÉPONDU (… theirs 2 → négociée v2 …) », puis « sks setenv : requête
#       acceptée », « sks setenv > EP 0x12 TAG 0x2a … », puis soit « sks setenv < réponse appariée : TAG 0xaa … DATA
#       0x00580000 » et « VERDICT sks setenv : ACCEPTÉ (PARAM 0, état 0 ; L 0x50, version d'en-tête 2 …) » (macOS :
#       réponse 1,1 ms après la requête, c12 L180-181), soit « VERDICT sks setenv : ERREUR (PARAM … / état …) » (le SEP
#       refuse notre set_env), soit « SILENCE », soit « NON ENVOYÉ » (get_capabilities non RÉPONDU ou v négociée ≠ 2).
#       sks_setenv.out = les deux verdicts décodés (getcap puis setenv) + instantané B12 (0x80 o) du set_env.
#       Puis « VERDICT sbio : VIVANT » attendu comme J9a (si MUET : à analyser, set_env a changé quelque chose).
# PRÉPARÉ PAR : agent driver (session ALARM), 2026-11-23. JAMAIS LANCÉ. 1er run = « go » d'Albert.
#
# Usage (root, boot normal SANS le service : /etc/sep-touchid/disabled présent, puis reboot) :
#   pending/j9b_sks_setenv_chained.sh STORE
#   STORE = store chaîné d'un seal frais réussi, ex. /var/lib/sepd-run-20261122-230441 (identique octet pour octet à
#           /var/lib/sepd le 2026-11-23 10:00, cmp des 5 .bin ; J7b/J8/J9a n'y ont fait 0 SAVE).
# Binaires attendus ($J10 = /home/albert/kbuild/j10) :
#   sep_native.ko     59bd81ff953182ab90c04c77f75774308cb4d0bc0bf572d9bbd01a8369aa07f3 (allow_sks=3)
#   sks_setenv        2e3cbf9f54c281d7f300ce2939f04f5bc0d7805acb3fee4fd27149224e6f439f
#   sepd              6ad1992f12b0d300b37b6b20ba2e9e3c0cc44d4e02bd7b74ce031cc958e37f4a (= j5/j9, défaut sans UUID)
#   sep_native_ovl.ko 02c1fcc2fb9b19363a89a8ad818422411eb968110720d039d3b822029ad517cd (= j5/j9)
#   sep-native.dtbo   8adbcb089a430fa63718c90a43dd5423afe0d52c8bfd0dc7eab0d60c51119771 (= j5/j9)
set -euo pipefail
J10=${J10:-/home/albert/kbuild/j10}
SERVICE_STORE=/var/lib/sepd
STORE=${1:-/var/lib/sepd-run-20261122-230441}
[ "$(id -u)" = 0 ] || { echo "à lancer en root"; exit 1; }
want() {  # want FICHIER SHA256
  [ "$(sha256sum "$J10/$1" | cut -d' ' -f1)" = "$2" ] || { echo "$J10/$1 n'est pas le binaire relu (sha256)"; exit 1; }
}
want sep_native.ko     59bd81ff953182ab90c04c77f75774308cb4d0bc0bf572d9bbd01a8369aa07f3
want sks_setenv        2e3cbf9f54c281d7f300ce2939f04f5bc0d7805acb3fee4fd27149224e6f439f
want sepd              6ad1992f12b0d300b37b6b20ba2e9e3c0cc44d4e02bd7b74ce031cc958e37f4a
want sep_native_ovl.ko 02c1fcc2fb9b19363a89a8ad818422411eb968110720d039d3b822029ad517cd
want sep-native.dtbo   8adbcb089a430fa63718c90a43dd5423afe0d52c8bfd0dc7eab0d60c51119771
modinfo -F parm "$J10/sep_native.ko" | grep -q "^allow_sks:.*3 (J9b)" || { echo "$J10/sep_native.ko sans allow_sks=3 (J9b)"; exit 1; }
# Le service ne doit PAS tenir le SEP pendant ce boot.
[ -e /etc/sep-touchid/disabled ] || { echo "/etc/sep-touchid/disabled absent : désactiver le service (touch) puis reboot d'abord"; exit 1; }
if systemctl is-active --quiet sep-touchid 2>/dev/null; then echo "service sep-touchid actif : refus"; exit 1; fi
pgrep -x sepd >/dev/null && { echo "un sepd tourne déjà : refus"; exit 1; }
lsmod | grep -q "^sep_native " && { echo "sep_native déjà chargé (SEP déjà touché depuis ce boot) : reboot d'abord"; exit 1; }
[ -e /dev/sep_native ] && { echo "/dev/sep_native existe déjà : refus"; exit 1; }
# STORE : chaîné, complet, et jamais celui du service.
[ "$(readlink -f "$STORE")" != "$(readlink -f "$SERVICE_STORE")" ] || { echo "STORE = store du service ($SERVICE_STORE) : refus (utiliser une copie, ex. /var/lib/sepd-run-20261122-230441)"; exit 1; }
[ -d "$STORE" ] && [ -n "$(ls -A "$STORE")" ] || { echo "STORE $STORE absent ou vide : ce test exige un store CHAÎNÉ"; exit 1; }
ls "$STORE"/master_*.bin >/dev/null 2>&1 || { echo "STORE $STORE sans master_*.bin : pas un boot chaîné"; exit 1; }
ls "$STORE"/locker_save_*.bin >/dev/null 2>&1 || { echo "STORE $STORE sans locker_save_*.bin : pas le store d'un seal complet"; exit 1; }
[ -s /etc/sepd/os_uuid ] || { echo "/etc/sepd/os_uuid absent : un store chaîné exige l'UUID du run qui l'a scellé"; exit 1; }
# Même contenu servi que le service (sinon un SAVE ici ou là ferait diverger les deux) : avertissement seulement.
same=1
for f in "$STORE"/master_*.bin "$STORE"/locker_save_*.bin; do
  cmp -s "$f" "$SERVICE_STORE/$(basename "$f")" || same=0
done
[ "$same" = 1 ] || echo "ATTENTION : $STORE diffère de $SERVICE_STORE (master/locker) ; continuer = servir un autre état que le service"
# Mailbox et DART du SEP liées avant l'insmod (sinon probe différé, hors de ce script), comme le service.
bound() { basename "$(readlink -f "$1/driver" 2>/dev/null)" 2>/dev/null || true; }
for i in $(seq 1 600); do
  [ "$(bound /sys/bus/platform/devices/396408000.mbox)" = apple-mailbox ] \
    && [ "$(bound /sys/bus/platform/devices/3952c0000.iommu)" = apple-dart ] && break
  sleep 0.1
done
[ "$(bound /sys/bus/platform/devices/396408000.mbox)" = apple-mailbox ] || { echo "mailbox SEP non liée : refus"; exit 1; }
[ "$(bound /sys/bus/platform/devices/3952c0000.iommu)" = apple-dart ] || { echo "DART SEP non liée : refus"; exit 1; }

LOG=/home/albert/Desktop/sep-touchid/logs/$(date +%Y%m%d-%H%M%S)_j9b-sks-setenv-chained
mkdir -p "$LOG"
echo "STORE = $STORE (servi tel quel) :" | tee "$LOG/store.txt"; ls -l "$STORE" | tee -a "$LOG/store.txt"
sha256sum "$STORE"/*.bin >> "$LOG/store.txt"
BAK="${STORE%/}.avant-j9b-$(date +%Y%m%d-%H%M%S)"; cp -a "$STORE" "$BAK"; echo "copie du store avant run : $BAK" | tee -a "$LOG/store.txt"
(cd "$J10" && sha256sum sep_native.ko sks_setenv sepd sep_native_ovl.ko sep-native.dtbo) > "$LOG/binaires.sha256"
cp "$J10/sep-native.dtbo" /lib/firmware/sep-native.dtbo
[ "$(sha256sum /lib/firmware/sep-native.dtbo | cut -d' ' -f1)" = 8adbcb089a430fa63718c90a43dd5423afe0d52c8bfd0dc7eab0d60c51119771 ] \
  || { echo "/lib/firmware/sep-native.dtbo ≠ binaire relu"; exit 1; }
insmod "$J10/sep_native_ovl.ko"
insmod "$J10/sep_native.ko" allow_boot=1 allow_xart=1 allow_xart_save_ack=1 allow_sbio=1 allow_sbio_relay=0 \
    sbio_open=1 allow_sks=3 &
for i in $(seq 1 300); do [ -e /dev/sep_native ] && break; sleep 0.1; done
if [ ! -e /dev/sep_native ]; then
    echo "/dev/sep_native absent après 30 s"
    journalctl -k -b --no-pager | grep sep_native > "$LOG/kernel.log" || true
    exit 1
fi
"$J10/sepd" --store "$STORE" --os-uuid-file /etc/sepd/os_uuid --dev /dev/sep_native 2> "$LOG/sepd.log" &
SEPD=$!
# sks_setenv : attend /dev/sep_sks, écrit le get_capabilities, puis (une fois sa réponse reçue et la v2 négociée) le
# set_env, lit les deux verdicts. cpx-encryption-mode forcé à 2 (valeur de notre ADT ; l'arbre Asahi n'exporte pas
# /defaults, donc la lecture auto tomberait sur 0).
set +e
"$J10/sks_setenv" run --dev /dev/sep_sks --wait-s 300 --cpx 2 --out-dir "$LOG" > "$LOG/sks_setenv.out" 2> "$LOG/sks_setenv.log"
SE=$?
set -e
echo "sks_setenv rc=$SE (0 = set_env ACCEPTÉ, 1 = autre verdict, 2 = rien écrit / erreur)" | tee -a "$LOG/sks_setenv.log"
# Fin du probe (insmod rendu : ligne « table de découverte »), puis journaux.
for i in $(seq 1 1800); do
    journalctl -k -b --no-pager | grep -q "sep_native.*table de découverte" && break
    sleep 0.1
done
sleep 2
journalctl -k -b --no-pager | grep -E "sep_native" > "$LOG/kernel.log" || true
echo "journaux : $LOG (sepd reste lancé, pid $SEPD : le SEP peut encore demander du xART ; reboot pour finir)"
grep -E "sks getcap|sks setenv|keystore|VERDICT|HALTED|annonce 0x1d|découverte : EP 0x12" "$LOG/kernel.log" || true
cat "$LOG/sks_setenv.out" || true
grep -E "locker|SAVE|STOP" "$LOG/sepd.log" | cut -c15- || true
# Divergence éventuelle avec le store du service (un SAVE pendant ce run) : à régler AVANT de réactiver le service.
diverged=0
for f in "$STORE"/master_*.bin "$STORE"/locker_save_*.bin; do
  cmp -s "$f" "$BAK/$(basename "$f")" || diverged=1
done
if [ "$diverged" = 1 ]; then
  echo "ATTENTION : $STORE a CHANGÉ pendant ce run (SAVE) ; le store du service ($SERVICE_STORE) est désormais PÉRIMÉ pour ce SEP."
  echo "            NE PAS réactiver le service avant décision d'Albert (copier le nouvel état dans le store du service ?)."
else
  echo "store inchangé (0 SAVE) : service réactivable (rm /etc/sep-touchid/disabled ; reboot)."
fi
