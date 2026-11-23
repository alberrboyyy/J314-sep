#!/usr/bin/env bash
# sep-touchid-boot.sh : démarre le SEP depuis Linux au boot et initialise le capteur Touch ID (brique « J8 »).
#
# BUT : rejouer, sans variable de test, le chemin VÉRIFIÉ du 2026-11-23 (journal 00:30 et 00:58, n=2) :
#       pending/j8_chained_sensor.sh STORE → pending/j5c_params_run.sh (UPTO=pass2) → pending/j5_sensor_run.sh
#       (ALLOW_CHAINED=1, SBIO_OPEN=1). Boot SEPOS, xART servi par sepd depuis le store durable (lockers sans UUID),
#       sbio ouvert tôt, init capteur complète (patch, params, calibration 0x5b, 2e passe), puis sepd reste en service.
# ENDPOINTS TOUCHÉS : ceux de J8 : 0xFF/0xFE (boot), 0x00 (CNTL), 0x13 (xART : FETCH servis, SAVE acquittés),
#       0x08 (sbio : 0x73 puis la liste blanche du noyau, allow_sbio_params=3). Jamais 0x12, 0x17, 0x0a, ni 0x03.
#       Paramètres d'écriture SEP posés à insmod : allow_boot=1 allow_xart=1 allow_xart_save_ack=1 allow_sbio=1
#       allow_sbio_relay=1 allow_sbio_params=3 (tous désactivés par défaut dans le module).
# RISQUE : écriture SEP de la classe éprouvée J8 (n=2). Le SCRIPT est neuf : 1er run = « go » d'Albert.
#       Échec SEP = HALTED dans dmesg ; un simple `reboot` remet le SEP en ROM (docs/sep_reconnect.md n=6, puis J8 n=2).
#       Le boot de Linux n'est jamais bloqué : toute incohérence → sortie en erreur AVANT le moindre mot au SEP.
# RÉSULTAT ATTENDU : « VERDICT : 2e passe terminée, capteur au repos final de macOS » dans le journal, sepd actif.
#
# Commandes (root) :
#   sep-touchid-boot.sh boot                 utilisé par sep-touchid.service : boot chaîné, store /var/lib/sepd
#   sep-touchid-boot.sh check                vérifications seules (binaires, noyau, store, état) ; rien au SEP
#                                            (seule écriture possible : réparation du marqueur, cf. verify_state)
#   sep-touchid-boot.sh status               état, génération, sauvegardes, derniers journaux ; lecture seule
#   sep-touchid-boot.sh fresh-seal --erase-enrollment
#                                            seal FRAIS volontaire : le store actuel est mis de côté (pas supprimé),
#                                            le SEP re-scelle un état neuf. EFFACE tout enrôlement futur. Manuel.
#   sep-touchid-boot.sh accept-store --i-understand-rollback-risk
#                                            fait accepter le store actuel tel quel (après une réparation à la main)
# Voir docs/service.md.
set -euo pipefail
umask 077
export LC_ALL=C

readonly LIB=/usr/local/lib/sep-touchid          # binaires installés (pending/install_sep_touchid_service.sh)
readonly STORE=/var/lib/sepd                     # store xART durable, emplacement fixe
readonly STATEDIR=/var/lib/sep-touchid           # état anti-retour + sauvegardes (HORS du store)
readonly STATE=$STATEDIR/state
readonly BACKUPS=$STATEDIR/backups
readonly MARKER=$STORE/sep-touchid.generation    # ignoré par sepd (ni master_ ni locker_)
readonly LOGROOT=/var/log/sep-touchid
readonly OS_UUID_FILE=/etc/sepd/os_uuid
readonly OS_UUID=4c494e55580000000000000000000000  # UUID d'OS du seal qui a créé le store (J4/J5, vérifié)
readonly DISABLE_FLAG=/etc/sep-touchid/disabled
readonly KEEP_BACKUPS=10
readonly KEEP_LOGS=30
readonly BIOSENSOR=spi@39b108000/biosensor@0
readonly FILES="sep_native.ko sep_native_ovl.ko sep-native.dtbo sepd sbiod mesa_ovl.ko mesa-spi2.dtbo calib_0x5b.bin"

say() { echo "sep-touchid: $*"; }
die() { echo "sep-touchid: STOP : $*" >&2; status_set "arrêt : $*"; exit 1; }
status_set() {
  mkdir -p /run/sep-touchid 2>/dev/null && printf '%s %s\n' "$(date -Is)" "$*" > /run/sep-touchid/status 2>/dev/null || true
  [ -n "${NOTIFY_SOCKET:-}" ] && systemd-notify --status="$*" 2>/dev/null || true
}

# --- état anti-retour ---------------------------------------------------------------------------------------------
# Empreinte du contenu servi au SEP : sha256 de la liste « sha256 nom » des master_*.bin et locker_*.bin (sepd.log et
# le marqueur sont exclus). Le compteur de génération augmente à chaque changement observé (SAVE du SEP).
manifest() {
  ( cd "$1" && find . -maxdepth 1 -type f \( -name 'master_*.bin' -o -name 'locker_*.bin' \) -printf '%f\n' \
      | sort | xargs -r sha256sum -- ) | sha256sum | cut -d' ' -f1
}
kv() { sed -n "s/^$2=//p" "$1" 2>/dev/null | tail -n1; }
is_uint() { case "$1" in ''|*[!0-9]*) return 1;; *) return 0;; esac; }
write_durable() {   # write_durable FICHIER CONTENU : tmp + fsync + rename + fsync du dossier
  local f=$1 tmp=$1.tmp.$$
  printf '%s\n' "$2" > "$tmp"; sync "$tmp"; mv -f "$tmp" "$f"; sync "$(dirname "$f")"
}
record() {   # record GEN MANIFEST : l'état d'abord, puis le marqueur (crash entre les deux = rattrapé par verify_state)
  mkdir -p "$STATEDIR"
  write_durable "$STATE" "generation=$1
manifest=$2
updated=$(date -Is)"
  write_durable "$MARKER" "$1"
}
store_complete() {
  [ -d "$STORE" ] && compgen -G "$STORE/master_*.bin" >/dev/null && compgen -G "$STORE/locker_save_*.bin" >/dev/null
}
verify_state() {   # refuse tout store qui n'est pas le dernier connu
  [ -s "$STATE" ] || die "état $STATE absent : le service n'a pas été installé (pending/install_sep_touchid_service.sh)"
  [ -s "$MARKER" ] || die "marqueur $MARKER absent : $STORE ne vient pas du service (restauration à la main ?) ; voir docs/service.md"
  local sg sm mg m
  sg=$(kv "$STATE" generation); sm=$(kv "$STATE" manifest); mg=$(head -n1 "$MARKER")
  is_uint "$sg" && is_uint "$mg" && [ ${#sm} = 64 ] || die "état ou marqueur illisible ($STATE, $MARKER)"
  m=$(manifest "$STORE")
  if [ "$mg" = "$sg" ] && [ "$m" = "$sm" ]; then
    say "store = dernier état connu (génération $sg)"
  elif [ "$((mg + 1))" = "$sg" ] && [ "$m" = "$sm" ]; then
    say "marqueur en retard d'une génération (arrêt entre deux écritures) ; contenu = dernier état connu : marqueur réparé"
    write_durable "$MARKER" "$sg"
  elif [ "$mg" -lt "$sg" ]; then
    die "store PLUS ANCIEN que le dernier état connu (génération $mg < $sg) : restauration d'une vieille sauvegarde ? REFUS"
  elif [ "$mg" -gt "$sg" ]; then
    die "store de génération $mg > état $sg : incohérent (état restauré ?) ; REFUS"
  else
    die "contenu du store modifié hors service (empreinte $m ≠ $sm, génération $sg) ; REFUS"
  fi
}
track_store() {   # appelé pendant que sepd tourne : un SAVE du SEP = nouvelle génération
  local sg sm m
  sg=$(kv "$STATE" generation); sm=$(kv "$STATE" manifest)
  m=$(manifest "$STORE")
  if [ "$m" != "$sm" ]; then
    record "$((sg + 1))" "$m"
    say "store modifié par sepd (SAVE du SEP) : génération $((sg + 1)) ; les sauvegardes antérieures sont désormais PÉRIMÉES"
  fi
}

# --- vérifications sans matériel ------------------------------------------------------------------------------------
verify_binaries() {
  local f
  [ -s "$LIB/SHA256SUMS" ] || die "$LIB/SHA256SUMS absent"
  for f in $FILES; do
    grep -qE "^[0-9a-f]{64}  $f\$" "$LIB/SHA256SUMS" || die "$LIB/SHA256SUMS ne liste pas $f"
  done
  [ "$(grep -c . "$LIB/SHA256SUMS")" = "$(wc -w <<<"$FILES")" ] || die "$LIB/SHA256SUMS liste des fichiers inattendus"
  ( cd "$LIB" && sha256sum --quiet --strict -c SHA256SUMS ) || die "sha256 des binaires installés ≠ SHA256SUMS"
  local vm k
  for k in sep_native.ko sep_native_ovl.ko mesa_ovl.ko; do
    vm=$(modinfo -F vermagic "$LIB/$k" | cut -d' ' -f1)
    [ "$vm" = "$(uname -r)" ] || die "$k compilé pour $vm, noyau courant $(uname -r) : recompiler et réinstaller"
  done
  local parm usage
  parm=$(modinfo -F parm "$LIB/sep_native.ko")
  grep -q "^allow_sbio_params:.*3 = " <<<"$parm" || die "sep_native.ko sans allow_sbio_params niveau 3"
  grep -q "^sbio_open:" <<<"$parm" || die "sep_native.ko sans sbio_open"
  grep -q "^allow_sbio_relay:" <<<"$parm" || die "sep_native.ko sans allow_sbio_relay"
  usage=$("$LIB/sbiod" 2>&1 || true)
  grep -q -- "pass2" <<<"$usage" || die "sbiod sans --upto pass2"
  [ "$(tr -d ' \n' < "$OS_UUID_FILE" 2>/dev/null)" = "$OS_UUID" ] || die "$OS_UUID_FILE ≠ $OS_UUID (UUID du seal du store)"
}
verify_fresh_boot() {
  [ -d /sys/module/sep_native ] && die "sep_native déjà chargé : le SEP a déjà été démarré depuis ce boot ; redémarrer (reboot)"
  local m
  for m in mesa_probe mesa_statloop mesa_irqwatch; do
    [ -d "/sys/module/$m" ] && die "le module $m tient le capteur : redémarrer"
  done
  pgrep -x sepd >/dev/null && die "un sepd tourne déjà"
  pgrep -x sbiod >/dev/null && die "un sbiod tourne déjà"
  return 0
}

# --- rotation ---------------------------------------------------------------------------------------------------------
prune() {   # prune GARDER CHEMIN... (chemins triés du plus ancien au plus récent) : retire les plus anciens
  local keep=$1; shift
  local n=$(( $# - keep ))
  while [ "$n" -gt 0 ]; do
    rm -rf -- "$1"; say "rotation (garder $keep) : retiré $1"
    shift; n=$((n - 1))
  done
}
backup_store() {   # copie horodatée AVANT chaque démarrage ; garde les $KEEP_BACKUPS plus récentes
  local g b
  g=$(kv "$STATE" generation)
  mkdir -p "$BACKUPS"
  b=$BACKUPS/sepd-$(date +%Y%m%d-%H%M%S)-gen$g
  cp -a "$STORE" "$b"
  [ "$(manifest "$b")" = "$(manifest "$STORE")" ] || die "copie $b ≠ store"
  sync
  say "sauvegarde du store : $b"
  shopt -s nullglob
  prune "$KEEP_BACKUPS" "$BACKUPS"/sepd-*      # glob trié (LC_ALL=C) : horodatage croissant
  shopt -u nullglob
}
rotate_logs() {
  shopt -s nullglob
  prune "$KEEP_LOGS" "$LOGROOT"/2*
  shopt -u nullglob
}

# --- matériel : séquence de pending/j5_sensor_run.sh (SBIO_PARAMS=3, --upto pass2) ------------------------------------
SEPD=
OUT=
on_exit() {
  local rc=$?
  [ -n "$SEPD" ] && kill "$SEPD" 2>/dev/null
  [ -n "$SEPD" ] && [ -s "$STATE" ] && track_store || true
  [ -n "$OUT" ] && "$LIB/sbiod" power-off --log "$OUT/sbiod.log" >/dev/null 2>&1 || true
  exit "$rc"
}
bound() { basename "$(readlink -f "$1/driver" 2>/dev/null)" 2>/dev/null || true; }
spidev_node() {
  local d
  for d in /sys/bus/spi/devices/*; do
    case "$(readlink -f "$d/of_node" 2>/dev/null)" in *"$BIOSENSOR") basename "$d"; return 0;; esac
  done; return 1
}
run_sep() {   # run_sep SBIO_OPEN
  local sbio_open=$1 i DEV D CTRL INSMOD RC
  OUT=$LOGROOT/$(date +%Y%m%d-%H%M%S)
  mkdir -p "$OUT"
  exec > >(tee -a "$OUT/run.log") 2>&1
  say "journal : $OUT ; store $STORE ; sbio_open=$sbio_open"
  trap on_exit EXIT
  trap 'exit 143' TERM INT HUP

  # 1. capteur côté Linux, AVANT tout mot au SEP
  status_set "capteur (spi2)"
  if ! spidev_node >/dev/null; then
    cp "$LIB/mesa-spi2.dtbo" /lib/firmware/mesa-spi2.dtbo
    [ "$(sha256sum /lib/firmware/mesa-spi2.dtbo | cut -d' ' -f1)" = "$(sed -n 's/  mesa-spi2.dtbo$//p' "$LIB/SHA256SUMS")" ] \
      || die "/lib/firmware/mesa-spi2.dtbo ≠ SHA256SUMS"
    insmod "$LIB/mesa_ovl.ko"
  fi
  for i in $(seq 1 300); do spidev_node >/dev/null && break; sleep 0.1; done   # au boot : spi-apple peut arriver tard
  DEV=$(spidev_node) || die "pas de device SPI sur $BIOSENSOR après l'overlay"
  D=/sys/bus/spi/devices/$DEV
  [ -e "$D/driver" ] && [ "$(basename "$(readlink -f "$D/driver")")" != spidev ] && die "$DEV lié à $(basename "$(readlink -f "$D/driver")")"
  echo spidev > "$D/driver_override"
  if [ -d /sys/module/spidev ]; then
    [ "$(cat /sys/module/spidev/parameters/bufsiz)" -ge 65536 ] || die "spidev déjà chargé avec bufsiz < 65536 : redémarrer"
  else
    modprobe spidev bufsiz=65536
  fi
  [ -e "$D/driver" ] || echo "$DEV" > /sys/bus/spi/drivers/spidev/bind
  [ "$(basename "$(readlink -f "$D/driver")")" = spidev ] || die "$DEV non lié à spidev"
  CTRL=$(readlink -f "$D/..")
  [ -w "$CTRL/power/control" ] && echo on > "$CTRL/power/control"
  say "capteur : $DEV, contrôleur $(basename "$CTRL") power/control=$(cat "$CTRL/power/control" 2>/dev/null)"
  "$LIB/sbiod" preflight --log "$OUT/sbiod.log"

  # 2. SEP : boot, xART (sepd), sbio (0x73), relais d'init capteur
  status_set "boot SEP"
  # Au boot, la mailbox et la DART du SEP doivent être liées AVANT l'insmod : sinon le probe serait différé et
  # pourrait démarrer le SEP plus tard, hors de ce script (sans sepd). On attend, puis on refuse.
  for i in $(seq 1 600); do
    [ "$(bound /sys/bus/platform/devices/396408000.mbox)" = apple-mailbox ] \
      && [ "$(bound /sys/bus/platform/devices/3952c0000.iommu)" = apple-dart ] && break
    sleep 0.1
  done
  [ "$(bound /sys/bus/platform/devices/396408000.mbox)" = apple-mailbox ] || die "mailbox SEP (396408000.mbox) non liée à apple-mailbox"
  [ "$(bound /sys/bus/platform/devices/3952c0000.iommu)" = apple-dart ] || die "DART SEP (3952c0000.iommu) non liée à apple-dart"
  cp "$LIB/sep-native.dtbo" /lib/firmware/sep-native.dtbo
  [ "$(sha256sum /lib/firmware/sep-native.dtbo | cut -d' ' -f1)" = "$(sed -n 's/  sep-native.dtbo$//p' "$LIB/SHA256SUMS")" ] \
    || die "/lib/firmware/sep-native.dtbo ≠ SHA256SUMS"
  insmod "$LIB/sep_native_ovl.ko"
  insmod "$LIB/sep_native.ko" allow_boot=1 allow_xart=1 allow_xart_save_ack=1 allow_sbio=1 allow_sbio_relay=1 \
    sbio_open="$sbio_open" allow_sbio_params=3 &
  INSMOD=$!
  for i in $(seq 1 300); do [ -e /dev/sep_native ] && break; sleep 0.1; done
  [ -e /dev/sep_native ] || { journalctl -k -b --no-pager | grep sep_native | tail -20; die "/dev/sep_native absent après 30 s"; }
  "$LIB/sepd" --store "$STORE" --os-uuid-file "$OS_UUID_FILE" --dev /dev/sep_native &
  SEPD=$!
  for i in $(seq 1 1800); do
    [ -e /dev/sep_sbio ] && break
    kill -0 "$INSMOD" 2>/dev/null || break
    sleep 0.1
  done
  sleep 0.5
  if [ ! -e /dev/sep_sbio ]; then
    journalctl -k -b --no-pager | grep -E 'sbio|VERDICT|HALTED' | tail -30
    die "/dev/sep_sbio absent (sbio non VIVANT ou Halted) : rien relayé ; sepd arrêté"
  fi
  status_set "init capteur (sbiod)"
  set +e
  "$LIB/sbiod" run --dev /dev/sep_sbio --log "$OUT/sbiod.log" --upto pass2 --calib "$LIB/calib_0x5b.bin"
  RC=$?
  set -e
  journalctl -k -b --no-pager | grep sep_native > "$OUT/kernel.log" || true
  grep -E 'VERDICT|HALTED' "$OUT/kernel.log" | tail -5 || true
  track_store
  if [ "$RC" = 0 ]; then
    status_set "prêt : capteur initialisé, sepd actif (pid $SEPD)"
    say "sbiod rc=0 : capteur au repos final de macOS. sepd reste actif (pid $SEPD)."
  else
    status_set "init capteur en échec (sbiod rc=$RC) ; sepd reste actif"
    say "sbiod rc=$RC : init capteur NON terminée (voir $OUT/sbiod.log). sepd reste actif pour le xART."
  fi
  # sepd doit continuer à servir le xART (le SEP peut encore demander un SAVE). On suit le store toutes les 5 s.
  while kill -0 "$SEPD" 2>/dev/null; do
    track_store
    sleep 5 & wait $! || true
  done
  set +e; wait "$SEPD"; i=$?; set -e
  SEPD=
  track_store
  journalctl -k -b --no-pager | grep sep_native > "$OUT/kernel.log" || true
  die "sepd s'est arrêté (rc=$i) : plus aucune réponse xART ; redémarrer pour relancer le SEP"
}

with_lock() {
  mkdir -p /run/sep-touchid
  exec 9>/run/sep-touchid/lock
  flock -n 9 || die "une autre instance de sep-touchid-boot.sh tourne"
}

cmd_boot() {
  [ -e "$DISABLE_FLAG" ] && { say "$DISABLE_FLAG présent : rien fait"; exit 0; }
  grep -qw "sep_touchid=off" /proc/cmdline && { say "sep_touchid=off sur la ligne de commande du noyau : rien fait"; exit 0; }
  with_lock
  verify_fresh_boot
  verify_binaries
  store_complete || die "store $STORE vide ou incomplet (master_*.bin + locker_save_*.bin) : pas de seal frais automatique (il effacerait l'enrôlement) ; voir « fresh-seal » dans docs/service.md"
  verify_state
  mkdir -p "$LOGROOT"; rotate_logs
  backup_store
  run_sep 1
}

cmd_check() {
  verify_binaries; say "binaires : OK (SHA256SUMS, noyau $(uname -r))"
  store_complete || die "store $STORE vide ou incomplet"
  verify_state; say "store : OK"
  [ -d /sys/module/sep_native ] && say "note : sep_native déjà chargé dans ce boot (un « boot » serait refusé)"
  say "check OK (rien n'a été envoyé au SEP)"
}

cmd_status() {
  echo "store       : $STORE"; ls -l "$STORE" 2>/dev/null || echo "  (absent)"
  echo "empreinte   : $( [ -d "$STORE" ] && manifest "$STORE" )"
  echo "marqueur    : $(cat "$MARKER" 2>/dev/null || echo absent)"
  echo "état        :"; sed 's/^/  /' "$STATE" 2>/dev/null || echo "  (absent)"
  echo "sauvegardes : $BACKUPS"; ls -1d "$BACKUPS"/* 2>/dev/null | sed 's/^/  /' || true
  echo "journaux    : $LOGROOT (dernier : $(ls -1d "$LOGROOT"/2* 2>/dev/null | sort | tail -n1))"
  echo "statut      : $(cat /run/sep-touchid/status 2>/dev/null || echo 'aucun run dans ce boot')"
}

cmd_fresh_seal() {
  [ "${1:-}" = --erase-enrollment ] || die "fresh-seal exige --erase-enrollment (un seal frais EFFACE tout enrôlement ; docs/service.md)"
  with_lock
  verify_fresh_boot
  verify_binaries
  local g=0 aside
  [ -s "$STATE" ] && { g=$(kv "$STATE" generation); is_uint "$g" || die "état illisible"; }
  if [ -d "$STORE" ] && [ -n "$(ls -A "$STORE")" ]; then
    aside=$STATEDIR/avant-seal-frais-$(date +%Y%m%d-%H%M%S)-gen$g
    mkdir -p "$STATEDIR"
    mv "$STORE" "$aside"; sync
    say "ancien store mis de côté (NON supprimé, à ne JAMAIS remettre en service) : $aside"
  fi
  mkdir -p "$STORE"
  record "$((g + 1))" "$(manifest "$STORE")"
  say "store vide, génération $((g + 1)) : seal frais (ouverture sbio tardive, chemin des runs J5c pass2)"
  mkdir -p "$LOGROOT"
  run_sep 0
}

cmd_accept_store() {
  [ "${1:-}" = --i-understand-rollback-risk ] || die "accept-store exige --i-understand-rollback-risk (docs/service.md)"
  with_lock
  pgrep -x sepd >/dev/null && die "sepd tourne : redémarrer avec sep_touchid=off d'abord"
  store_complete || die "store $STORE vide ou incomplet"
  local g=0 mg=0
  [ -s "$STATE" ] && g=$(kv "$STATE" generation)
  [ -s "$MARKER" ] && mg=$(head -n1 "$MARKER")
  is_uint "$g" || g=0; is_uint "$mg" || mg=0
  [ "$mg" -gt "$g" ] && g=$mg
  say "état précédent : $(tr '\n' ' ' < "$STATE" 2>/dev/null || echo absent)"
  record "$((g + 1))" "$(manifest "$STORE")"
  say "store $STORE accepté tel quel : génération $((g + 1)), empreinte $(manifest "$STORE")"
}

[ "$(id -u)" = 0 ] || { echo "sep-touchid: à lancer en root" >&2; exit 1; }
case "${1:-}" in
  boot) cmd_boot ;;
  check) cmd_check ;;
  status) cmd_status ;;
  fresh-seal) shift; cmd_fresh_seal "$@" ;;
  accept-store) shift; cmd_accept_store "$@" ;;
  *) echo "usage: $0 boot|check|status|fresh-seal --erase-enrollment|accept-store --i-understand-rollback-risk" >&2; exit 64 ;;
esac
