#!/usr/bin/env bash
# BUT : installer la brique « SEP + capteur au boot » (driver/linux/service/) sur le Linux principal (ALARM) :
#       binaires vérifiés (sha256 = driver/linux/service/SHA256SUMS, ceux de J8 n=2) dans /usr/local/lib/sep-touchid/,
#       store actuel COPIÉ vers l'emplacement fixe /var/lib/sepd, état anti-retour initialisé, unité systemd
#       installée SANS être activée (sauf --enable explicite). `uninstall` retire unité + binaires, garde les données.
# ENDPOINTS TOUCHÉS : AUCUN pendant l'installation (rien n'est chargé, rien n'est démarré, aucun mot au SEP).
#       Une fois activé, le service fait à chaque boot les écritures SEP de J8 (classe éprouvée, n=2) :
#       0xFF/0xFE, 0x00, 0x13 (SAVE acquittés), 0x08 (liste blanche, allow_sbio_params=3). Jamais 0x12.
# RISQUE : action sur le système principal d'Albert (fichiers dans /usr/local/lib, /etc/systemd/system, /var/lib,
#       /etc/sep-touchid). Rien n'est supprimé : un /var/lib/sepd existant (ancien store J4 du 2026-11-22 18:38)
#       est RENOMMÉ en /var/lib/sepd.ancien-avant-service-<horodatage>. Le service est neuf : son 1er boot = « go »
#       d'Albert. Le boot de Linux n'en dépend pas (Type=simple, pas de relance, erreurs = sortie avant le SEP).
# RÉSULTAT ATTENDU : « installation terminée » + `sep-touchid-boot.sh check` = OK ; unité « disabled » sans --enable.
# PRÉPARÉ PAR : agent driver (session ALARM), 2026-11-23. JAMAIS LANCÉ. Lancé par Albert, en root.
#
# Usage (root, dans un boot où sepd ne tourne PAS, c.-à-d. après un reboot sans run SEP) :
#   pending/install_sep_touchid_service.sh install [--enable] [--from-store DIR] [--bin-dir DIR] [--reuse-store]
#       DIR store défaut : /var/lib/sepd-run-20261122-230441 (store de J7b/J7c/J8, inchangé depuis 23:04)
#       DIR binaires défaut : /home/albert/kbuild/j5
#       --reuse-store : réinstallation (après uninstall) : garde /var/lib/sepd et l'état tels quels, ne copie rien
#   pending/install_sep_touchid_service.sh uninstall
#       retire l'unité et /usr/local/lib/sep-touchid ; GARDE /var/lib/sepd, /var/lib/sep-touchid, /var/log/sep-touchid
set -euo pipefail
export LC_ALL=C
umask 022
REPO=$(cd "$(dirname "$0")/.." && pwd)
SRC=$REPO/driver/linux/service
LIB=/usr/local/lib/sep-touchid
UNIT=/etc/systemd/system/sep-touchid.service
STORE=/var/lib/sepd
STATEDIR=/var/lib/sep-touchid
FILES="sep_native.ko sep_native_ovl.ko sep-native.dtbo sepd sbiod mesa_ovl.ko mesa-spi2.dtbo calib_0x5b.bin"
TS=$(date +%Y%m%d-%H%M%S)

die() { echo "STOP : $*" >&2; exit 1; }
manifest() {   # même définition que sep-touchid-boot.sh
  ( cd "$1" && find . -maxdepth 1 -type f \( -name 'master_*.bin' -o -name 'locker_*.bin' \) -printf '%f\n' \
      | sort | xargs -r sha256sum -- ) | sha256sum | cut -d' ' -f1
}
[ "$(id -u)" = 0 ] || die "à lancer en root"

do_install() {
  local enable=0 reuse=0 from=/var/lib/sepd-run-20261122-230441 bin=/home/albert/kbuild/j5 f
  while [ $# -gt 0 ]; do
    case "$1" in
      --enable) enable=1 ;;
      --reuse-store) reuse=1 ;;
      --from-store) from=${2:?}; shift ;;
      --bin-dir) bin=${2:?}; shift ;;
      *) die "option inconnue : $1" ;;
    esac
    shift
  done
  # 1. vérifications, AVANT toute écriture
  for f in sep-touchid-boot.sh sep-touchid.service SHA256SUMS; do [ -s "$SRC/$f" ] || die "$SRC/$f absent"; done
  [ -s "$REPO/docs/service.md" ] || die "$REPO/docs/service.md absent"
  bash -n "$SRC/sep-touchid-boot.sh" || die "sep-touchid-boot.sh : erreur de syntaxe"
  ( cd "$bin" && sha256sum --quiet --strict -c "$SRC/SHA256SUMS" ) || die "binaires de $bin ≠ $SRC/SHA256SUMS (ceux de J8)"
  pgrep -x sepd >/dev/null && die "un sepd tourne (il peut écrire dans le store pendant la copie) : redémarrer d'abord, sans run SEP"
  pgrep -x sbiod >/dev/null && die "un sbiod tourne : redémarrer d'abord"
  [ "$(tr -d ' \n' < /etc/sepd/os_uuid 2>/dev/null)" = 4c494e55580000000000000000000000 ] \
    || die "/etc/sepd/os_uuid absent ou ≠ 4c494e55… (UUID du seal du store) : rien installé"
  if [ "$reuse" = 0 ]; then
    [ -d "$from" ] && compgen -G "$from/master_*.bin" >/dev/null && compgen -G "$from/locker_save_*.bin" >/dev/null \
      || die "$from : pas un store complet (master_*.bin + locker_save_*.bin)"
    local m_from
    m_from=$(manifest "$from")
    # Le store source doit être le DERNIER état : identique à sa copie la plus récente faite avant un run (0 SAVE depuis).
    local last
    # copies « <store>.avant-<run>-AAAAMMJJ-HHMMSS » : la plus récente = plus grand horodatage final
    last=$(ls -1d "${from%/}".avant-* 2>/dev/null | sed -n 's/^\(.*-\([0-9]\{8\}-[0-9]\{6\}\)\)$/\2 \1/p' \
      | sort | tail -n1 | cut -d' ' -f2- || true)
    if [ -n "$last" ]; then
      [ "$(manifest "$last")" = "$m_from" ] || die "$from ≠ sa dernière copie $last : un SAVE a eu lieu ? vérifier à la main"
      echo "store source $from = sa copie $last (empreinte $m_from)"
    fi
    [ -e "$STATEDIR/state" ] && die "$STATEDIR/state existe déjà (installation précédente) : --reuse-store pour garder le store en service"
  else
    [ -s "$STATEDIR/state" ] && [ -s "$STORE/sep-touchid.generation" ] || die "--reuse-store : pas d'état/store du service à réutiliser"
  fi
  [ -e "$UNIT" ] && die "$UNIT existe déjà : uninstall d'abord"

  # 2. binaires + script + doc
  install -d -m 0755 "$LIB"
  for f in $FILES; do install -m 0644 "$bin/$f" "$LIB/$f"; done
  chmod 0755 "$LIB/sepd" "$LIB/sbiod"
  install -m 0644 "$SRC/SHA256SUMS" "$LIB/SHA256SUMS"
  install -m 0755 "$SRC/sep-touchid-boot.sh" "$LIB/sep-touchid-boot.sh"
  install -m 0644 "$REPO/docs/service.md" "$LIB/service.md"
  ( cd "$LIB" && sha256sum --quiet --strict -c SHA256SUMS ) || die "copie dans $LIB ≠ SHA256SUMS"
  echo "binaires installés dans $LIB"

  # 3. store : copie vers /var/lib/sepd (rien supprimé) ; --reuse-store : store et état gardés tels quels
  if [ "$reuse" = 1 ]; then
    echo "store $STORE et état $STATEDIR/state réutilisés (vérifiés par « check » ci-dessous)"
  else
    if [ -e "$STORE" ]; then
      mv "$STORE" "$STORE.ancien-avant-service-$TS"
      echo "ancien $STORE renommé en $STORE.ancien-avant-service-$TS (NON supprimé ; ne pas le remettre en service)"
    fi
    cp -a "$from" "$STORE"
    [ "$(manifest "$STORE")" = "$m_from" ] || die "copie $STORE ≠ $from"
    # 4. état anti-retour : génération 1 (état d'abord, marqueur ensuite, comme le script)
    install -d -m 0700 "$STATEDIR" "$STATEDIR/backups"
    printf 'generation=1\nmanifest=%s\nupdated=%s\nsource=%s\n' "$m_from" "$(date -Is)" "$from" > "$STATEDIR/state"
    echo 1 > "$STORE/sep-touchid.generation"
    sync
    echo "store $STORE = copie de $from (génération 1, empreinte $m_from) ; $from laissé intact"
  fi
  install -d -m 0755 /etc/sep-touchid /var/log/sep-touchid

  # 5. unité (non activée par défaut)
  install -m 0644 "$SRC/sep-touchid.service" "$UNIT"
  systemctl daemon-reload
  if [ "$enable" = 1 ]; then
    systemctl enable sep-touchid.service
    echo "unité ACTIVÉE : le SEP sera démarré au PROCHAIN boot (pas maintenant)"
  else
    echo "unité installée, NON activée (systemctl enable sep-touchid.service pour l'activer)"
  fi
  "$LIB/sep-touchid-boot.sh" check
  echo "installation terminée (rien n'a été démarré)"
}

do_uninstall() {
  if [ -e "$UNIT" ]; then
    systemctl disable sep-touchid.service 2>/dev/null || true
    rm -f "$UNIT"
    systemctl daemon-reload
    echo "unité retirée"
  fi
  if [ -d "$LIB" ]; then rm -rf -- "$LIB"; echo "$LIB retiré"; fi
  echo "GARDÉS : $STORE (store), $STATEDIR (état + sauvegardes), /var/log/sep-touchid, /etc/sep-touchid, /etc/sepd,"
  echo "         /lib/firmware/{sep-native,mesa-spi2}.dtbo (déjà là avant le service). Un sepd déjà lancé n'est pas arrêté :"
  echo "         redémarrer pour remettre le SEP en ROM."
}

case "${1:-}" in
  install) shift; do_install "$@" ;;
  uninstall) do_uninstall ;;
  *) die "usage : $0 install [--enable] [--from-store DIR] [--bin-dir DIR] [--reuse-store] | uninstall" ;;
esac
