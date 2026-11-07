# Configuration commune, sourcée par les autres scripts. À adapter par Albert.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
M1N1_DIR="$REPO_ROOT/m1n1"
TRACES_DIR="$REPO_ROOT/traces"

# Ports série exposés par m1n1 en mode proxy
export M1N1DEVICE="${M1N1DEVICE:-/dev/ttyACM0}"   # proxy
HV_UART="${HV_UART:-/dev/ttyACM1}"                 # UART virtuel de l'hyperviseur

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

die() { echo "ERREUR: $*" >&2; exit 1; }

require_mac() {
  [ -e "$M1N1DEVICE" ] || die "$M1N1DEVICE absent : le Mac n'est pas en mode proxy m1n1 (ou câble débranché)."
}
