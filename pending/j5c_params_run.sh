#!/usr/bin/env bash
# BUT : J5c, depuis un reboot : tout J5 v2 (boot SEPOS, xART, sbio 0x73, relais 0x17 … 0x5f, patch capteur chargé)
#       PUIS la fin de la 1re passe d'init macOS (docs/j5_params_protocol.md) :
#       0x5d, 0x5c (trames SPI 0x55 + CRC16, état lu UNE fois après l'IRQ 195) ; 0x6a (vide) ; 0x31 → trame 0x55 →
#       réponse 0x75 → 0x32 (n° de série module) ; 0x01 ; 0x1f ; 0x31/0x32 encore ; et avec UPTO=calib (explicite)
#       0x5b = blob de calibration capturé (c12, 64665 o, sha256 d5a6117d…ddda), fragmenté AP→SEP par le noyau en
#       4 morceaux, puis 0x63. STOP après 0x63 (UPTO=params|calib) ; avec UPTO=pass2 (explicite) la 2e passe macOS
#       (docs/j5_params_protocol.md §8) : capteur coupé 40 ms puis rallumé, 2 lectures d'état = macOS, 0x19, identité
#       (80 70, sans 80 78), 0x17 0x15 0x16 0x42 0x18 0x5f (patch n°2, 0x70ce o, même push), 0x5d 0x5c 0x6a 0x6f
#       (trames 0x55 de 0x40/0x40/0x4d/0x56), 0x31/0x32, 0x01, 0x1f, 0x63 ×2 ; STOP au repos final de macOS (avant son
#       0x7c). Jamais : 0x6c 0x6d 0x65 0x09 0x23 0x06 0x7c 0x6b 0x79, rien sur enrôlement/match.
# ENDPOINTS TOUCHÉS : ceux de pending/j5_sensor_run.sh, plus sur 0x08 : 0x5d 0x5c 0x6a 0x31 0x32 0x01 0x1f 0x31 0x32
#       (UPTO=params et calib) et 0x5b (+ 3 × `> fd`) 0x63 (UPTO=calib), dans cet ordre, une fois chacun (liste blanche
#       du noyau, paramètre allow_sbio_params=1 ou 2) ; UPTO=pass2 : en plus, une fois chacun et à leur rang seulement
#       (allow_sbio_params=3) : 0x19 0x17 0x15 0x16 0x42 0x18 0x5f 0x5d 0x5c 0x6a 0x6f 0x31 0x32 0x01 0x1f 0x63 0x63.
#       Jamais 0x12. Capteur : trames 0x55 (4, +5 en pass2), 0x72/0x73/0x60/bloc (pass2 : 2e fois), 0x10, 0x13,
#       lectures ; gpio0 196 (pass2 : coupure puis rallumage entre les deux passes).
# RISQUE : classe NEUVE d'écriture SEP : paramètres capteur et surtout 0x5b (setCalibrationData, rejeu d'un blob
#       capturé dans une session neuve : jamais fait, sbio10 jamais lancé). Le SEP peut refuser → Halted (power-cycle,
#       Albert). Le blob n'est envoyé que si : sha256 = capture, n° de série capteur vivant = celui du blob (offset 91),
#       n° de série module rendu par 0x32 = celui du blob (offset 889) ; le noyau revérifie longueur + CRC-32. Le capteur
#       est éteint dans tous les chemins. Effet persistant possible côté SEP (calibration retenue) : inconnu.
#       Aucun doigt, aucun enrôlement, aucune image.
#       UPTO=pass2 : classe NEUVE (0x19 HandleReset + 2e session capteur, jamais faits hors macOS) ; incertains : durée
#       de coupure (40 ms ici, 11 ms sous macOS), absence du 80 78 (calqué sur macOS), le SEP peut refuser un 2e
#       0x17/0x5f → Halted (power-cycle, Albert). Côté capteur, tout écart d'état → arrêt avant la commande SEP suivante.
# RÉSULTAT ATTENDU : « VERDICT : capteur initialisé et calibré (1re passe ; 0x5b acquitté, 0x63 = référence macOS) »
#       (UPTO=calib) ou « VERDICT : patch chargé + paramètres … » (UPTO=params) ou « VERDICT : 2e passe terminée, capteur
#       au repos final de macOS (… 0x63 ×2 = référence macOS) » (UPTO=pass2) ; sinon « arrêt (fail-closed) : <raison> »
#       de sbiod, ou HALTED dans dmesg.
# PRÉPARÉ PAR : agent driver (session ALARM), 2026-11-22. UPTO=params et UPTO=calib : lancés (calib 21:41, 0x63 =
#       macOS) ; UPTO=pass2 : JAMAIS LANCÉ, 1er run = « go » d'Albert. Défaut inchangé : UPTO=params.
#
# Usage (root, après un reboot) : UPTO=params|calib|pass2 pending/j5c_params_run.sh [STORE]
#   Fichiers : ceux de j5_sensor_run.sh dans $J5 (sep_native.ko J5c : paramètre allow_sbio_params ; sbiod J5c :
#   --upto). Le fichier de calibration $J5/calib_0x5b.bin est fabriqué ici depuis traces/ (sbiod calib-prepare) s'il
#   manque, et sa sha256 est toujours revérifiée.
set -euo pipefail
J5=${J5:-/home/albert/kbuild/j5}
UPTO=${UPTO:-params}   # défaut prudent : sans 0x5b
REPO=$(cd "$(dirname "$0")/.." && pwd)
C12=$REPO/traces/20261108-032454_c12-boot-ho/sep.log.ool
CALIB=$J5/calib_0x5b.bin
SHA=d5a6117dc8b5482320ab4d86c94148f190a7b08530c6235735636b9abd23ddda
die() { echo "STOP : $*" >&2; exit 1; }
case "$UPTO" in
  params) LEVEL=1 ;;
  calib) LEVEL=2 ;;
  pass2) LEVEL=3 ;;
  *) die "UPTO=$UPTO (params, calib ou pass2)" ;;
esac
USAGE=$("$J5/sbiod" 2>&1 || true)
grep -q -- "--upto" <<<"$USAGE" || die "$J5/sbiod sans --upto (binaire J5c ?)"
if [ "$UPTO" = pass2 ]; then
  grep -q -- "pass2" <<<"$USAGE" || die "$J5/sbiod sans --upto pass2 (binaire 2e passe ?)"
  modinfo -F parm "$J5/sep_native.ko" | grep -q "^allow_sbio_params:.*3 = " || die "$J5/sep_native.ko sans le niveau 3"
fi
modinfo -F parm "$J5/sep_native.ko" | grep -q "^allow_sbio_params:" || die "$J5/sep_native.ko sans allow_sbio_params"
if [ "$UPTO" = calib ] || [ "$UPTO" = pass2 ]; then
  [ -e "$CALIB" ] || "$J5/sbiod" calib-prepare --from "$C12" --out "$CALIB"
  [ "$(sha256sum "$CALIB" | cut -d' ' -f1)" = "$SHA" ] || die "$CALIB : sha256 ≠ $SHA"
  ARGS="--upto $UPTO --calib $CALIB"
else
  ARGS="--upto params"
fi
echo "J5c : UPTO=$UPTO (allow_sbio_params=$LEVEL), sbiod $ARGS"
SBIO_PARAMS=$LEVEL SBIOD_ARGS=$ARGS exec "$REPO/pending/j5_sensor_run.sh" "$@"
