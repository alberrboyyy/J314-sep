#!/usr/bin/env bash
# BUT : J3, comme j4_xart_run.sh (boot SEPOS + service xART 0x13 par sepd), puis, xART scellé et calme, ouvrir sbio
#       (EP 0x08 : A8/B8 0x4000 par 4 CNTL PARAM 0x08) et envoyer UNE poignée 0x73 (gt_packet capturé, sans doigt).
# ENDPOINTS TOUCHÉS : 0xFF/0xFE (boot), 0x00 (CNTL : SECMODE + tampons 0x13, puis tampons 0x08), 0x13 (xART, SAVE
#       acquittés), 0x08 (sbio : UN seul mot, TAG 0xfc TYPE 0x73). Jamais 0x12 (sks), jamais 0x17/0x15/0x16.
# RISQUE : écriture SEP ; compteur scellé avancé par les SAVE (comme J4, accepté) ; Touch ID macOS invalidé (accepté).
#       Le 0x73 est un « bonjour » rejouable, sans doigt ni enrôlement. Échec = HALTED dans dmesg, power-cycle (Albert).
# RÉSULTAT ATTENDU : dmesg « VERDICT sbio : VIVANT » (B8 +0x00=1 +0x14=0x73, ou mot 0x08 TAG 0xfc TYPE 0x73 / TAG 0x04),
#       sinon « VERDICT sbio : MUET » (on diagnostique, on ne force pas). Spec : docs/j3_sbio_open.md.
# PRÉPARÉ PAR : Claude (session ALARM, agent driver), 2026-11-22. Go d'Albert donné ; lancé 3× le 2026-11-22 (18:56, 19:04, 19:20 = VIVANT sur seal frais).
#
# Usage (root, après un reboot normal avec alias sep) : pending/j3_sbio_run.sh [STORE]
#   STORE = dossier du store xART servi par sepd. Défaut : dossier NEUF et vide /var/lib/sepd-run-<horodatage>.
#   Passer /var/lib/sepd (store du run J4, non vide) = servir l'état scellé existant : QUESTION OUVERTE, à trancher
#   avec l'orchestrateur avant le run (SEP_NATIVE.md). Le script ne décide pas : il affiche ce qu'il utilise.
set -euo pipefail
J=/home/albert/kbuild/j2
STORE=${1:-/var/lib/sepd-run-$(date +%Y%m%d-%H%M%S)}
lsmod | grep -q "^sep_native" && { echo "sep_native déjà chargé : redémarrer d'abord (SEP déjà démarré sur ce boot)"; exit 1; }
modinfo -F parm $J/sep_native.ko | grep -q "^allow_sbio:1 = once xART is sealed" \
  || { echo "$J/sep_native.ko n'a pas allow_sbio (copier le module J3 compilé)"; exit 1; }
mkdir -p /etc/sepd "$STORE"
[ -s /etc/sepd/os_uuid ] || echo 4c494e55580000000000000000000000 > /etc/sepd/os_uuid
if [ -z "$(ls -A "$STORE")" ]; then
  echo "STORE = $STORE (vide : tout FETCH → ABSENT, scellement frais comme J4)"
else
  echo "STORE = $STORE (NON vide, sera servi tel quel) :"; ls -l "$STORE"
fi
cp $J/sep-native.dtbo /lib/firmware/
insmod $J/sep_native_ovl.ko
# insmod reste en arrière-plan : le probe attend sbio (≤ 120 s), l'ouvre, envoie le 0x73, écoute 6 s.
# Module J5+ : sbio_open vaut 1 (précoce) par défaut ; ce script garde l'ouverture TARDIVE éprouvée (J3 19:20).
OPEN=$(modinfo -F parm $J/sep_native.ko | grep -q "^sbio_open:" && echo sbio_open=0 || true)
insmod $J/sep_native.ko allow_boot=1 allow_xart=1 allow_xart_save_ack=1 allow_sbio=1 $OPEN &
for i in $(seq 1 300); do [ -e /dev/sep_native ] && break; sleep 0.1; done
[ -e /dev/sep_native ] || { echo "/dev/sep_native absent après 30 s"; journalctl -k -b --no-pager | grep sep_native | tail -20; exit 1; }
echo "verdict : journalctl -k -b | grep -E 'sbio|VERDICT|HALTED'"
exec $J/sepd --store "$STORE" --os-uuid-file /etc/sepd/os_uuid --dev /dev/sep_native
