# Configuration commune, sourcée par les autres scripts. À adapter par Albert.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
M1N1_DIR="$REPO_ROOT/m1n1"
TRACES_DIR="$REPO_ROOT/traces"

# Ports série exposés par m1n1 en mode proxy. On ne se fie PAS à ttyACM0/1 : un autre appareil
# CDC-ACM (ex. téléphone Android, vu le 2026-11-07) peut prendre ttyACM0. On passe par /dev/serial/by-id :
#   interface if00 = proxy, if02 = UART virtuel de l'hyperviseur.
# Le nom contient la version de m1n1 (change après chainload d'un autre build) → résolution à la demande.
m1n1_port() {  # $1 = if00 | if02 ; affiche le chemin, ou rien si absent / ambigu
  local m=(/dev/serial/by-id/usb-Asahi_Linux_m1n1_uartproxy_*-"$1")
  [ ${#m[@]} -eq 1 ] && [ -e "${m[0]}" ] && echo "${m[0]}"
}
M1N1DEVICE_FIXED="${M1N1DEVICE:-}"   # surcharge explicite éventuelle
HV_UART_FIXED="${HV_UART:-}"
refresh_ports() {
  export M1N1DEVICE="${M1N1DEVICE_FIXED:-$(m1n1_port if00)}"
  HV_UART="${HV_UART_FIXED:-$(m1n1_port if02 || true)}"
}
refresh_ports

# Kernel macOS 13.5 extrait (img4tool -e -o macos/kernel.macho macos/kernelcache)
MACOS_KERNEL="${MACOS_KERNEL:-$REPO_ROOT/macos/kernel.macho}"

# Script de tracing passé à run_guest.py (-m). L'agent tracer doit renseigner le bon chemin
# après avoir localisé/adapté le tracer SEP dans m1n1/proxyclient/hv/.
TRACE_SCRIPT="${TRACE_SCRIPT:-$REPO_ROOT/hv/trace_sep_filtered.py}"

# Bootargs macOS sous hyperviseur (repris de la doc Asahi)
MACOS_BOOTARGS="${MACOS_BOOTARGS:-debug=0x14e serial=3 apcie=0xfffffffe -enable-kprintf-spam wdt=-1 clpc=0}"

# Durée max d'une capture (secondes) avant arrêt automatique
TRACE_TIMEOUT="${TRACE_TIMEOUT:-900}"

# Kernel Linux (phase 2+)
LINUX_DIR="${LINUX_DIR:-$REPO_ROOT/linux}"

# Python du proxyclient : il faut asn1 (importé par m1n1/hv). Venv recommandé dans SETUP-ARCH.md.
if [ -z "${M1N1_PYTHON:-}" ]; then
  if [ -x "$HOME/.venvs/m1n1/bin/python" ]; then M1N1_PYTHON="$HOME/.venvs/m1n1/bin/python"; else M1N1_PYTHON=python3; fi
fi

die() { echo "ERREUR: $*" >&2; exit 1; }

require_mac() {
  refresh_ports
  [ -n "$M1N1DEVICE" ] && [ -e "$M1N1DEVICE" ] || die "port proxy m1n1 introuvable dans /dev/serial/by-id (Mac pas en mode proxy, câble débranché, ou plusieurs m1n1 branchés)."
}
