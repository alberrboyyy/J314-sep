#!/usr/bin/env bash
# BUT : J5, depuis un reboot : boot SEPOS + xART (sepd) + ouverture sbio + 0x73 (comme J3), puis relais d'init capteur
#       par sbiod : identité SPI → 0x17 (n° de série) → 0x15/0x72/0x16 (échange de clés) → 0x42/0x73/0x18 (compteur) →
#       0x5f (patch, réassemblé par le noyau) → push au capteur (prélude 80 60 00 07 00 00 00 + bloc en UN transfert,
#       PIO noyau spi-apple via spidev) → attente de l'état corps[8] == 0x29 (sbiod lib.rs:269). STOP là (pas de 0x5d/0x5c/0x6a/0x5b).
# ENDPOINTS TOUCHÉS : 0xFF/0xFE (boot), 0x00 (CNTL : SECMODE + tampons 0x13 et 0x08), 0x13 (xART, SAVE acquittés),
#       0x08 (sbio : 0x73 puis 0x17, 0x15, 0x16, 0x42, 0x18, 0x5f (+ 0xfe fragment suivant), dans cet ordre, une fois
#       chacun : liste blanche du noyau). Jamais 0x12. Capteur : spi2 (trames 0x78 0x10 0x70 0x13 0x72 0x73 0x60 + bloc),
#       gpio0 196 (alimentation), gpio0 195 (lecture).
# RISQUE : écriture SEP (comme J3/J4 : compteur scellé avancé, Touch ID macOS invalidé, accepté). NOUVEAU : relais
#       sbio depuis Linux et 1er push du patch par le PIO du noyau (sous m1n1 : jamais chargé, FIFO 2,2 s). Le capteur
#       peut rester mi-patché : il est éteint (gpio0 196 = 0) dans tous les chemins (trap). Échec SEP = HALTED dans
#       dmesg (plus aucun envoi), power-cycle (Albert). Aucun doigt, aucun enrôlement, aucune image.
# RÉSULTAT ATTENDU : ligne « VERDICT : patch chargé (0x29 …) » de sbiod ; sinon « patch refusé » / « IRQ absente »
#       (informatifs, cf. docs/sbio_session.md §3b) ou « arrêt (fail-closed) : <raison> ».
# PRÉPARÉ PAR : Claude (agent driver, session ALARM), 2026-11-22. Run v1 (go d'Albert) : 20:16, patch refusé
#       (logs/20261122-201601_j5-sensor-native). v2 = sbiod modifié (push « comme macOS » : lecture d'état ENTRE prélude
#       et bloc, aucune lecture pendant le chargement, attente IRQ 195, cf. journal 21:00) → 1er run v2 = go d'Albert.
#
# Variables (défauts = run J5 v2 inchangé) : SBIO_PARAMS (0) = paramètre allow_sbio_params de sep_native (1 = params,
#   2 = params + calibration, cf. docs/j5_params_protocol.md) ; SBIOD_ARGS ("") = arguments ajoutés à `sbiod run`
#   (--upto params|calib --calib FICHIER). Utilisés par pending/j5c_params_run.sh ; ne pas les poser à la main.
# Usage (root, après un reboot normal avec alias sep) : pending/j5_sensor_run.sh [STORE]
#   STORE défaut = dossier NEUF /var/lib/sepd-run-<horodatage> (scellement frais : seul cas où l'ouverture TARDIVE de
#   sbio est éprouvée, J3 19:20). SBIO_OPEN=0 par défaut ici (ouverture tardive éprouvée) ; SBIO_OPEN=1 = précoce.
# Fichiers attendus dans $J5 (défaut /home/albert/kbuild/j5, préparés à la main) :
#   sep_native.ko (driver/rust/build.sh), sep_native_ovl.ko + sep-native.dtbo (comme J3), sepd et sbiod
#   (cargo build --release --offline), mesa_ovl.ko (driver/linux, make -C <arbre> M=…) + mesa-spi2.dtbo
#   (dtc -@ -I dts -O dtb driver/linux/mesa-spi2-overlay.dts). Phandles du dtbo (0x13 AIC, 0x31 horloge, 0x48 gpio0)
#   relus sur le DT vivant d'ALARM le 2026-11-22 : identiques à ceux du Linux de test.
set -euo pipefail
J5=${J5:-/home/albert/kbuild/j5}
SBIO_OPEN=${SBIO_OPEN:-0}
SBIO_PARAMS=${SBIO_PARAMS:-0}
SBIOD_ARGS=${SBIOD_ARGS:-}
case "$SBIO_PARAMS" in 0|1|2) ;; *) echo "STOP : SBIO_PARAMS=$SBIO_PARAMS (0, 1 ou 2)" >&2; exit 1;; esac
TS=$(date +%Y%m%d-%H%M%S)
STORE=${1:-/var/lib/sepd-run-$TS}
OUT=/var/log/j5-$TS
BIOSENSOR=spi@39b108000/biosensor@0

die() { echo "STOP : $*" >&2; exit 1; }
for f in sep_native.ko sep_native_ovl.ko sep-native.dtbo sepd sbiod mesa_ovl.ko mesa-spi2.dtbo; do
  [ -e "$J5/$f" ] || die "$J5/$f absent"
done
lsmod | grep -q "^sep_native " && die "sep_native déjà chargé : redémarrer d'abord"
lsmod | grep -qE "^mesa_(probe|statloop|irqwatch) " && die "un module mesa_* tient le capteur : redémarrer"
modinfo -F parm "$J5/sep_native.ko" | grep -q "^allow_sbio_relay:" || die "sep_native.ko sans allow_sbio_relay (module J5 ?)"
modinfo -F parm "$J5/sep_native.ko" | grep -q "^sbio_open:" || die "sep_native.ko sans sbio_open"
PARAMS_ARG=   # absent si 0 : le script reste utilisable avec le module J5 v2 (sans ce paramètre)
if [ "$SBIO_PARAMS" != 0 ]; then
  PARAMS_ARG="allow_sbio_params=$SBIO_PARAMS"
  modinfo -F parm "$J5/sep_native.ko" | grep -q "^allow_sbio_params:" || die "sep_native.ko sans allow_sbio_params (module J5c ?)"
fi
mkdir -p "$OUT" /etc/sepd "$STORE"
[ -s /etc/sepd/os_uuid ] || echo 4c494e55580000000000000000000000 > /etc/sepd/os_uuid
if [ -z "$(ls -A "$STORE")" ]; then echo "STORE = $STORE (vide : scellement frais)"; else
  echo "STORE = $STORE (NON vide) :"; ls -l "$STORE"
  # Boot chaîné : ouverture tardive refusée (J3/J3b, n=2) et 0x73 muet même tôt (J3d) → sbio gated derrière SKS.
  [ "${ALLOW_CHAINED:-0}" = 1 ] || die "STORE non vide = boot chaîné : sbio ne répond pas sans SKS (J3d). ALLOW_CHAINED=1 pour forcer"
fi
exec > >(tee -a "$OUT/run.log") 2>&1
echo "journal : $OUT"

# --- 1. capteur côté Linux, AVANT tout mot au SEP (un échec ici n'envoie rien au SEP) ---------------------------
spidev_node() {   # spiX.Y dont l'of_node est le capteur
  for d in /sys/bus/spi/devices/*; do
    case "$(readlink -f "$d/of_node" 2>/dev/null)" in *"$BIOSENSOR") basename "$d"; return 0;; esac
  done; return 1; }
if ! spidev_node >/dev/null; then
  cp "$J5/mesa-spi2.dtbo" /lib/firmware/
  insmod "$J5/mesa_ovl.ko"
fi
for i in $(seq 1 50); do spidev_node >/dev/null && break; sleep 0.1; done
DEV=$(spidev_node) || die "pas de device SPI sur $BIOSENSOR après l'overlay"
D=/sys/bus/spi/devices/$DEV
[ -e "$D/driver" ] && [ "$(basename "$(readlink -f "$D/driver")")" != spidev ] && die "$DEV lié à $(basename "$(readlink -f "$D/driver")")"
echo spidev > "$D/driver_override"
if lsmod | grep -q "^spidev "; then
  [ "$(cat /sys/module/spidev/parameters/bufsiz)" -ge 65536 ] || die "spidev déjà chargé avec bufsiz < 65536 : redémarrer"
else
  modprobe spidev bufsiz=65536
fi
[ -e "$D/driver" ] || echo "$DEV" > /sys/bus/spi/drivers/spidev/bind
[ "$(basename "$(readlink -f "$D/driver")")" = spidev ] || die "$DEV non lié à spidev"
# Contrôleur spi2 gardé alimenté pendant toute la session (équivalent de mesa_acquire : pm_runtime_resume_and_get).
CTRL=$(readlink -f "$D/..")
[ -w "$CTRL/power/control" ] && echo on > "$CTRL/power/control"
echo "capteur : $DEV ($(ls "$D/spidev")), contrôleur $(basename "$CTRL") power/control=$(cat "$CTRL/power/control" 2>/dev/null)"
"$J5/sbiod" preflight --log "$OUT/sbiod.log"
SEPD=
cleanup() { [ -n "$SEPD" ] && kill "$SEPD" 2>/dev/null; "$J5/sbiod" power-off --log "$OUT/sbiod.log" || true; }
trap cleanup EXIT

# --- 2. SEP : boot, xART (sepd en fond), sbio (0x73), relais ----------------------------------------------------
cp "$J5/sep-native.dtbo" /lib/firmware/
insmod "$J5/sep_native_ovl.ko"
# insmod reste en fond : le probe attend sbio, l'ouvre, envoie le 0x73, écoute 6 s, puis crée /dev/sep_sbio si VIVANT.
# shellcheck disable=SC2086 # PARAMS_ARG vide ou un seul mot
insmod "$J5/sep_native.ko" allow_boot=1 allow_xart=1 allow_xart_save_ack=1 allow_sbio=1 allow_sbio_relay=1 sbio_open="$SBIO_OPEN" $PARAMS_ARG &
INSMOD=$!
for i in $(seq 1 300); do [ -e /dev/sep_native ] && break; sleep 0.1; done
[ -e /dev/sep_native ] || { journalctl -k -b --no-pager | grep sep_native | tail -20; die "/dev/sep_native absent après 30 s"; }
"$J5/sepd" --store "$STORE" --os-uuid-file /etc/sepd/os_uuid --dev /dev/sep_native &
SEPD=$!
for i in $(seq 1 1800); do
  [ -e /dev/sep_sbio ] && break
  kill -0 "$INSMOD" 2>/dev/null || break   # probe fini sans /dev/sep_sbio (MUET, Halted, délai)
  sleep 0.1
done
sleep 0.5
if [ ! -e /dev/sep_sbio ]; then
  journalctl -k -b --no-pager | grep -E 'sbio|VERDICT|HALTED' | tail -30
  die "/dev/sep_sbio absent (sbio non VIVANT ou Halted) : rien relayé ; sepd arrêté"
fi
set +e
# shellcheck disable=SC2086 # SBIOD_ARGS = liste d'options (pas d'espace dans les chemins de $J5)
"$J5/sbiod" run --dev /dev/sep_sbio --log "$OUT/sbiod.log" $SBIOD_ARGS
RC=$?
set -e
journalctl -k -b --no-pager | grep sep_native > "$OUT/kernel.log" || true
grep -E 'VERDICT|HALTED' "$OUT/kernel.log" | tail -5 || true
echo "sbiod rc=$RC (0 = cible atteinte : patch chargé, ou params / calibration selon SBIOD_ARGS). Logs : $OUT. sepd continue (pid $SEPD) ; Ctrl-C pour finir ; power-cycle ensuite (Albert)."
wait "$SEPD"
