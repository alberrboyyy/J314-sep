#!/usr/bin/env bash
# BUT : J13 = J9b (boot chaîné natif, lockers sans UUID = sepd par défaut, skdl/sks/scrd ouverts par le CNTL, UN
#       get_capabilities ACCEPTÉ — J9a vérifié matériel : état 0, theirs 2 → v2 — puis UN set_env ACCEPTÉ, J9b)
#       + un BALAYAGE de `create_keybag` (TAG fil 0x01, TYPE 0x03), en SAUTANT perform_operation (TAG 0x22),
#       null_d_key (TAG 0x0a) ET load_keybag (TAG 0x03) :
#         - l'outil `sks_setenv run --sweep` écrit des `create_keybag` UN PAR UN dans /dev/sep_sks, chacun avec un
#           couple (class, field2) tiré d'une liste de balayage (class ∈ {1,2,3,4} ; field2 ∈ {-10,-11,-12,-13, 1,2,3,4,
#           -1,-2}, 40 couples ; motifs négatifs d'abord car indice reverse « ≤ -10 », docs/applekeystored_identity.md
#           §6.4). create_keybag ne porte PAS d'uuid (il prend une classe) → AUCUNE valeur secrète requise ;
#         - pour chaque enregistrement : la porte noyau `sks_keybag::check_createkeybag` le valide (constantes,
#           discriminant 4, blobs vides, condensé v2, cdhash), on l'ENVOIE (`> EP 0x12 TAG 0x01 TYPE 0x03 PARAM 0
#           DATA 0x00800000`, A12 = 0x80 o), on lit la réponse appariée (instantané B12), puis :
#             * PARAM ≠ 0 (échec, p.ex. -0xb) ou SILENCE → ré-armement pour le couple SUIVANT (aucun SAVE) ;
#             * PARAM == 0 (SUCCÈS) → lecture du handle (OOL B +0x6c), STOP du balayage : PAS de ré-armement, PAS de
#               make_system (JAMAIS plus d'UN keybag créé). C'est le verrou de sûreté clé.
#       POURQUOI J13 (journal 2026-11-23/24, docs/applekeystored_identity.md §6/§8/§9) : class et field2 (les deux u32 à
#       OOL 0x60/0x64 de create_keybag) sont des valeurs userland LIBRES — la porte `check_createkeybag` ne les contraint
#       pas (établi J14). Leurs vraies valeurs sont INCONNUES (posées par le Swift `AKSIdentity`, absentes du
#       kernelcache). On balaie donc un petit ensemble plausible pour voir si l'un fait passer create_keybag de -0xb
#       (BadArgument) à PARAM 0 + handle. Un create échoué est BÉNIN (0 SAVE, état intact, VU J9-J12).
# ENDPOINTS TOUCHÉS : 0xFF/0xFE (boot), 0x00 (CNTL : SECMODE + tampons 0x13, 0x08, 0x17, 0x12, 0x0a, comme J9b),
#       0x13 (xART : store servi par sepd, lockers SANS UUID, SAVE acquittés si demandés), **0x12 : getcap + set_env +
#       JUSQU'À 40 create_keybag** (portes noyau `GetcapGate`, `SetenvGate`, puis `CreatekeybagGate` ré-armée à neuf pour
#       chaque couple ; A12 contrôlé à chaque fois : constantes/discriminant 4/blobs vides/condensé v2/cdhash ; class et
#       field2 sont libres, non contrôlés en valeur), 0x08 (UN mot 0x73). AUCUN mot à 0x17/0x0a. AUCUN perform_operation,
#       null_d_key NI load_keybag, NI make_system. Pas de relais. Paramètre : allow_sks=8.
# RISQUE : écriture SEP vers SKS (EP 0x12). create_keybag EST une classe déjà émise sur matériel (J10/J11 : refus -0xb,
#       0 SAVE, bénin) ; ce run la renvoie jusqu'à 40 fois avec des class/field2 variés — chaque échec reste bénin. LE
#       CAS NEUF est un SUCCÈS (PARAM 0) : il voudrait dire qu'un keybag est CRÉÉ côté SEP (classe d'écriture jamais vue —
#       création/persistance d'identité, territoire gigalocker). C'est exactement pour ça que le balayage STOPPE au 1er
#       PARAM 0 et n'enchaîne RIEN (jamais plus d'UN keybag). Au pire : PARAM/état inattendu, silence, SEP figé/panique
#       jusqu'au reboot (SEPOS relancé par un `reboot` Linux normal, VU n=7 ; power-cycle = Albert) ; ou, si un create
#       réussit, un SAVE (xART) peut survenir : copie du store faite AVANT (STORE.avant-j13-<date>) et comparaison APRÈS.
#       macOS déjà déclaré sacrifiable (Albert 2026-11-22) ; filet : alarm_p5.img + backup perso + DFU.
#       ⚠️ SERVICE : le service sep-touchid tient le SEP à chaque boot. AVANT ce run : `touch /etc/sep-touchid/disabled`
#       puis `reboot` (le service ne démarre pas : ConditionPathExists=!/etc/sep-touchid/disabled). APRÈS : vérifier que
#       le store du service n'a pas divergé (voir la fin du script), `rm /etc/sep-touchid/disabled`, puis `reboot`.
#       Ce script REFUSE de tourner si le service est actif, si sepd tourne, ou si STORE = /var/lib/sepd (store du
#       service, jamais servi ici).
# RÉSULTAT ATTENDU : sepd.log = J9a/J9b (4 lockers sans UUID ×2, op 0x07, 0 SAVE) ; dmesg « 'sks' ouvert », getcap
#       « VERDICT sks getcap : RÉPONDU (… theirs 2 → négociée v2 …) », set_env « VERDICT sks setenv : ACCEPTÉ », puis
#       « sks create_keybag BALAYAGE : … » et, par couple, « create sweep (class=…, field2=0x…) → PARAM=… » (ÉCHEC) —
#       tant que tous échouent, finit par « BALAYAGE : plus d'écriture … terminé, N essai(s), aucun keybag créé » ; si UN
#       réussit : « create sweep SUCCÈS class=… field2=… handle=0x… ; STOP ». sks_setenv imprime les verdicts par couple
#       (rc 0 = un handle rendu, 1 = tous échoués, 2 = rien écrit/erreur) ; fichiers sks_sweep_NN_*.bin dans le log. Puis
#       « VERDICT sbio : VIVANT » attendu comme J9b (si MUET : à analyser).
# PRÉPARÉ PAR : agent driver (session ALARM), 2026-11-24 (J13). JAMAIS LANCÉ.
#       1er run = « go » d'Albert : SCRIPT NEUF, et un éventuel SUCCÈS = classe d'écriture jamais testée (keybag créé).
#       Les re-runs (après un 1er run propre) sont autonomes, comme les autres scripts éprouvés.
#
# Usage (root, boot normal SANS le service : /etc/sep-touchid/disabled présent, puis reboot) :
#   [HANDLE_Y=<u64>] pending/j13_sks_create_sweep.sh [STORE]
#   (ou en arguments : pending/j13_sks_create_sweep.sh [STORE] [--handle-y <u64>])
#   AUCUNE valeur secrète requise (create_keybag ne porte pas d'uuid ; class/field2 sont balayés par l'outil).
#   HANDLE_Y (OOL 0x58) a un défaut 0. PAS de --uuid, PAS de --class, PAS de --type.
#   STORE = store chaîné d'un seal frais réussi (défaut /var/lib/sepd-run-20261122-230441 : J7b/J8/J9a/J9b, 0 SAVE).
# Binaires attendus ($J17 = /home/albert/kbuild/j17) :
#   sep_native.ko     6b749ee9cf48178156fd8bb22b938c9ce6f33e7494d677f6a33d52a8dc6f2239 (allow_sks=8, balayage create_keybag)
#   sks_setenv        0e1f69de3dbfcb0bf9c03ca83d164e84b37c2b077ac4156ff0574093e27152c6 (run --sweep)
#   sepd              6ad1992f12b0d300b37b6b20ba2e9e3c0cc44d4e02bd7b74ce031cc958e37f4a (= j5..j15, source inchangée)
#   sep_native_ovl.ko 02c1fcc2fb9b19363a89a8ad818422411eb968110720d039d3b822029ad517cd (= j5..j15)
#   sep-native.dtbo   8adbcb089a430fa63718c90a43dd5423afe0d52c8bfd0dc7eab0d60c51119771 (= j5..j15)
#   (Albert peuple $J17 avec le sep_native.ko + sks_setenv fraîchement compilés sur ALARM cette session, et réutilise le
#    sepd/ovl/dtbo de j16 — sources inchangées. Les deux sha256 ci-dessus sont ceux des binaires relus ce jour.)
set -euo pipefail
J17=${J17:-/home/albert/kbuild/j17}
SERVICE_STORE=/var/lib/sepd

# --- Valeur userland optionnelle (env ou argument). Avec défaut 0 : HANDLE_Y. AUCUN secret requis ---
HANDLE_Y=${HANDLE_Y:-0}
STORE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --handle-y) HANDLE_Y=$2; shift 2 ;;
    --*)        echo "argument inconnu : $1"; exit 2 ;;
    *)          [ -z "$STORE" ] && { STORE=$1; shift; } || { echo "argument en trop : $1"; exit 2; } ;;
  esac
done
STORE=${STORE:-/var/lib/sepd-run-20261122-230441}

[ "$(id -u)" = 0 ] || { echo "à lancer en root"; exit 1; }
want() {  # want FICHIER SHA256
  [ "$(sha256sum "$J17/$1" | cut -d' ' -f1)" = "$2" ] || { echo "$J17/$1 n'est pas le binaire relu (sha256)"; exit 1; }
}
want sep_native.ko     6b749ee9cf48178156fd8bb22b938c9ce6f33e7494d677f6a33d52a8dc6f2239
want sks_setenv        0e1f69de3dbfcb0bf9c03ca83d164e84b37c2b077ac4156ff0574093e27152c6
want sepd              6ad1992f12b0d300b37b6b20ba2e9e3c0cc44d4e02bd7b74ce031cc958e37f4a
want sep_native_ovl.ko 02c1fcc2fb9b19363a89a8ad818422411eb968110720d039d3b822029ad517cd
want sep-native.dtbo   8adbcb089a430fa63718c90a43dd5423afe0d52c8bfd0dc7eab0d60c51119771
modinfo -F parm "$J17/sep_native.ko" | grep -q "8 (J13 create_keybag SWEEP" || { echo "$J17/sep_native.ko sans allow_sks=8 (J13)"; exit 1; }
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

LOG=/home/albert/Desktop/sep-touchid/logs/$(date +%Y%m%d-%H%M%S)_j13-sks-create-sweep
mkdir -p "$LOG"
echo "valeur userland : HANDLE_Y=$HANDLE_Y (aucun secret requis ; class/field2 balayés par l'outil)" | tee "$LOG/userland.txt"
echo "STORE = $STORE (servi tel quel) :" | tee "$LOG/store.txt"; ls -l "$STORE" | tee -a "$LOG/store.txt"
sha256sum "$STORE"/*.bin >> "$LOG/store.txt"
BAK="${STORE%/}.avant-j13-$(date +%Y%m%d-%H%M%S)"; cp -a "$STORE" "$BAK"; echo "copie du store avant run : $BAK" | tee -a "$LOG/store.txt"
(cd "$J17" && sha256sum sep_native.ko sks_setenv sepd sep_native_ovl.ko sep-native.dtbo) > "$LOG/binaires.sha256"
cp "$J17/sep-native.dtbo" /lib/firmware/sep-native.dtbo
[ "$(sha256sum /lib/firmware/sep-native.dtbo | cut -d' ' -f1)" = 8adbcb089a430fa63718c90a43dd5423afe0d52c8bfd0dc7eab0d60c51119771 ] \
  || { echo "/lib/firmware/sep-native.dtbo ≠ binaire relu"; exit 1; }
insmod "$J17/sep_native_ovl.ko"
insmod "$J17/sep_native.ko" allow_boot=1 allow_xart=1 allow_xart_save_ack=1 allow_sbio=1 allow_sbio_relay=0 \
    sbio_open=1 allow_sks=8 &
for i in $(seq 1 300); do [ -e /dev/sep_native ] && break; sleep 0.1; done
if [ ! -e /dev/sep_native ]; then
    echo "/dev/sep_native absent après 30 s"
    journalctl -k -b --no-pager | grep sep_native > "$LOG/kernel.log" || true
    exit 1
fi
"$J17/sepd" --store "$STORE" --os-uuid-file /etc/sepd/os_uuid --dev /dev/sep_native 2> "$LOG/sepd.log" &
SEPD=$!
# sks_setenv run --sweep : attend /dev/sep_sks, écrit le get_capabilities, puis (v2 négociée) le set_env, puis (set_env
# ACCEPTÉ) balaie create_keybag couple par couple (un write + un read par couple, STOP au 1er PARAM 0). AUCUNE valeur
# secrète requise. cpx-encryption-mode forcé à 2 (valeur de notre ADT).
set +e
"$J17/sks_setenv" run --sweep --handle-y "$HANDLE_Y" \
    --dev /dev/sep_sks --wait-s 300 --cpx 2 --out-dir "$LOG" > "$LOG/sks_sweep.out" 2> "$LOG/sks_sweep.log"
SE=$?
set -e
echo "sks_setenv rc=$SE (0 = un create_keybag a rendu un handle [PARAM 0], 1 = tous échoués, 2 = rien écrit / erreur)" | tee -a "$LOG/sks_sweep.log"
# Fin du probe (insmod rendu : ligne « table de découverte »), puis journaux.
for i in $(seq 1 1800); do
    journalctl -k -b --no-pager | grep -q "sep_native.*table de découverte" && break
    sleep 0.1
done
sleep 2
journalctl -k -b --no-pager | grep -E "sep_native" > "$LOG/kernel.log" || true
echo "journaux : $LOG (sepd reste lancé, pid $SEPD : le SEP peut encore demander du xART ; reboot pour finir)"
grep -E "sks getcap|sks setenv|create_keybag|create sweep|BALAYAGE|keystore|VERDICT|HALTED|annonce 0x1d|découverte : EP 0x12" "$LOG/kernel.log" || true
cat "$LOG/sks_sweep.out" || true
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
