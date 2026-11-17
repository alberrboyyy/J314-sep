#!/usr/bin/env bash
# tools/catch_proxy.sh — attrape m1n1 dans sa fenêtre d'attente au boot pour le FIXER en mode PROXY.
#
# POURQUOI : depuis la réinstall Asahi (installeur « UEFI only »/option 5), le m1n1 installé a un
#   payload (il enchaîne m1n1 -> U-Boot -> GRUB -> ALARM). Avec la backdoor activée en 1TR par Albert
#   (csrutil disable + nvram boot-args=-v), m1n1 ATTEND quelques secondes au boot que l'hôte l'attrape ;
#   si personne ne l'attrape, il continue sur Linux. Avant la réinstall, un m1n1 SANS payload tombait
#   en proxy tout seul (il était posé sur le volume macOS 13.5, aujourd'hui effacé).
#
# CE QUE FAIT CE SCRIPT :
#   1. attend (scrutation rapide) que les ports USB du m1n1 apparaissent — c.-à-d. que TU power-cycles
#      le Mac pendant que ce script tourne ;
#   2. ouvre le 2e port (if02) pour tenir la fenêtre (déclencheur « 2e TTY ouvert », doc Asahi) ;
#   3. chainloade un m1n1 frais (EXACTEMENT comme tools/sep_peek.sh) -> le Mac reste alors sur
#      « Running proxy... » avec un m1n1 propre, prêt pour sep_peek / tethered_boot.
#
# NON DESTRUCTIF : chainload = m1n1 envoyé en RAM. AUCUNE écriture disque, AUCUNE écriture SEP,
#   aucune commande Apple (bputil/kmutil/nvram), aucun partitionnement. Un simple reboot annule tout.
#   Échec = sortie propre ; il suffit de relancer et de re-power-cycler (fenêtre ratée).
#
# USAGE :
#   ./tools/catch_proxy.sh        # puis POWER-CYCLE PHYSIQUE du Mac (bouton power)
#   WAIT_S=120 (défaut)           # délai max d'attente des ports
set -euo pipefail
source "$(dirname "$0")/env.sh"

[ -f "$M1N1_DIR/build/m1n1.bin" ] || die "m1n1 non compilé : ./tools/build_m1n1.sh"
WAIT_S="${WAIT_S:-120}"

echo "=== catch_proxy ==="
echo ">>> POWER-CYCLE le Mac MAINTENANT (bouton power). J'attends ses ports USB (max ${WAIT_S}s)…"

P00=""; P02=""
deadline=$(( $(date +%s) + WAIT_S ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  P00="$(m1n1_port if00 || true)"
  P02="$(m1n1_port if02 || true)"
  if [ -n "$P00" ]; then break; fi
  sleep 0.1
done
[ -n "$P00" ] || die "aucun port m1n1 apparu en ${WAIT_S}s (backdoor 1TR pas active ? Mac pas power-cyclé ? câble ?)."
echo ">>> Port proxy détecté : $P00"

# Tenir la fenêtre : ouvrir if02 en tâche de fond (déclencheur « 2e TTY ouvert »).
HOLD_PID=""
if [ -n "$P02" ]; then
  ( exec 3<>"$P02"; sleep 15 ) &
  HOLD_PID=$!
  echo ">>> if02 ouvert ($P02) pour tenir la fenêtre."
fi

cleanup_hold() { [ -n "$HOLD_PID" ] && kill "$HOLD_PID" 2>/dev/null || true; }
trap cleanup_hold EXIT

# Chainload d'un m1n1 frais, même invocation que sep_peek, sur le port détecté.
export M1N1DEVICE="$P00"
echo ">>> chainload d'un m1n1 frais…"
"$M1N1_PYTHON" "$M1N1_DIR/proxyclient/tools/chainload.py" -r "$M1N1_DIR/build/m1n1.bin" \
  || die "chainload a échoué (fenêtre ratée ?) — relance ./tools/catch_proxy.sh et re-power-cycle."

cleanup_hold; HOLD_PID=""

# Après chainload, le m1n1 frais re-énumère l'USB : attendre que le port proxy revienne.
echo ">>> chainload OK, attente de la ré-énumération du port proxy…"
for _ in $(seq 1 100); do
  refresh_ports
  if [ -n "${M1N1DEVICE:-}" ] && [ -e "${M1N1DEVICE:-/nonexistent}" ]; then
    echo "✅ Mac en PROXY (port : $M1N1DEVICE)."
    echo "   Prêt : ./tools/sep_peek.sh (lecture seule) ou ./tools/tethered_boot.sh."
    exit 0
  fi
  sleep 0.1
done
die "après chainload, le port proxy n'est pas revenu — relance et retente."
