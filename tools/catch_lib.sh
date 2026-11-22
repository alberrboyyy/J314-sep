# tools/catch_lib.sh — logique « attraper m1n1 en proxy » réutilisable (à sourcer).
# Pur transport, aucun accès SEP. Sourcé par tools/catch_proxy.sh et par les scripts pending/ natifs
# pour faire catch + run d'un coup. Prérequis : env.sh déjà sourcé (m1n1_port, refresh_ports, die,
# M1N1_DIR, M1N1_PYTHON).
#
# ─── v2 (2026-11-22) — fiabilité 100 % visée. Pourquoi v1 ratait par moments : ──────────────────
#   1. LATENCE UDEV. v1 attendait le lien /dev/serial/by-id/...-if02, créé par udev APRÈS le vrai
#      nœud /dev/ttyACM* (créé par le noyau à l'énumération). Cette latence (variable, parfois >1-2 s)
#      grignotait la fenêtre de 5 s de m1n1 -> saisie parfois trop tardive. v2 guette le NŒUD BRUT.
#   2. PORTS FANTÔMES. v1 exigeait exactement 1 match by-id : un vieux lien if02 (proxy précédent)
#      faisait soit rater (2 matches), soit saisir un port mort. v2 fait une BASELINE des ports
#      présents AVANT l'allumage et n'agit QUE sur un port NEUF.
#   3. MAUVAIS PORT. Un autre CDC-ACM (le téléphone Android d'Albert) peut aussi créer un ttyACM.
#      v2 vérifie la chaîne produit/fabricant USB en sysfs : on ne saisit qu'un vrai m1n1.
#   m1n1 reste en proxy dès qu'on ouvre if00 OU if02 (src/main.c : iodev_can_write(proxy)||...(vuart)),
#   donc on saisit le 1er des deux qui apparaît.
#
# ⚠️ ModemManager : s'il tourne, il SONDE les nouveaux ttyACM (ouverture concurrente) -> c'est le
#   suspect n°1 du plantage « multiple access on port / device disconnected » vu en plein run
#   (trace 20261121-164403). S'il est présent, le masquer AVANT (côté PC, pas le Mac — Albert) :
#       systemctl mask --now ModemManager
#   (réversible : systemctl unmask ModemManager). Non bloquant : on saisit le port au plus vite.

_acm_ifnum() {  # $1 = ttyACMN -> "00" / "02" / ... ou vide
  local f="/sys/class/tty/$1/device/bInterfaceNumber"
  [ -r "$f" ] && { local v; v="$(<"$f")"; printf '%s' "${v//[^0-9a-fA-F]/}"; }
}
_acm_usbinfo() {  # $1 = ttyACMN -> "produit\nfabricant" (vide si sysfs pas encore prêt)
  cat "/sys/class/tty/$1/device/../product" "/sys/class/tty/$1/device/../manufacturer" 2>/dev/null
}
_acm_is_m1n1() {  # $1 = ttyACMN -> 0 si m1n1, 1 si pas m1n1, 2 si sysfs pas encore lisible
  local info; info="$(_acm_usbinfo "$1")"
  [ -z "$info" ] && return 2
  case "$info" in *m1n1*|*Asahi*|*uartproxy*) return 0 ;; *) return 1 ;; esac
}
_find_m1n1_if00_node() {  # affiche le nœud brut du port proxy (if00) d'un m1n1, ou rien
  local d b
  for d in /dev/ttyACM*; do
    [ -e "$d" ] || continue
    b="${d#/dev/}"
    [ "$(_acm_ifnum "$b")" = "00" ] || continue
    _acm_is_m1n1 "$b" && { echo "$d"; return 0; }
  done
  return 1
}

catch_proxy_run() {
  # Attend qu'un NOUVEAU port m1n1 apparaisse (= TU power-cycles le Mac pendant l'attente),
  # saisit if00/if02 à l'instant du nœud brut (tient la fenêtre), chainloade un m1n1 frais, et
  # laisse le Mac en « Running proxy ». Succès = le port proxy est présent À LA FIN (UartTimeout
  # de ré-énumération après chainload = TOLÉRÉ, cosmétique).
  local WAIT_S="${WAIT_S:-120}"
  [ -f "$M1N1_DIR/build/m1n1.bin" ] || die "m1n1 non compilé : ./tools/build_m1n1.sh"
  export M1N1TIMEOUT="${M1N1TIMEOUT:-20}"   # cf. CLAUDE.md RTFM : reconnexion lente > défaut 3 s
  echo "=== catch_proxy v2 (nœud brut, baseline, vérif m1n1) ==="

  # 1. BASELINE : ports ACM déjà là avant l'allumage -> à ignorer (anti port-fantôme).
  local -A seen=()
  local d b
  for d in /dev/ttyACM*; do [ -e "$d" ] && seen["$d"]=1; done
  [ "${#seen[@]}" -gt 0 ] && echo ">>> ports ACM préexistants (ignorés) : ${!seen[*]}"

  echo ">>> POWER-CYCLE / allume le Mac MAINTENANT. Je saisis le 1er port m1n1 neuf (if00/if02), fenêtre ${WAIT_S}s…"
  local deadline grab_dev="" grab_if="" HOLD_PID="" t_start ifn
  t_start=$(date +%s); deadline=$(( t_start + WAIT_S ))

  # 2. Boucle serrée sur les NŒUDS BRUTS (pas les liens udev).
  while [ "$(date +%s)" -lt "$deadline" ]; do
    # Un port de baseline qui DISPARAÎT (ancien proxy coupé au power-cycle) sort de la baseline,
    # pour que sa réapparition (même nom ttyACMx) soit bien vue comme NEUVE et saisie.
    for k in "${!seen[@]}"; do [ -e "$k" ] || unset 'seen[$k]'; done
    for d in /dev/ttyACM*; do
      [ -e "$d" ] || continue
      [ -n "${seen[$d]:-}" ] && continue
      b="${d#/dev/}"
      _acm_is_m1n1 "$b"
      case $? in
        2) continue ;;                                   # sysfs pas prêt : réessayer (ne PAS marquer vu)
        1) seen["$d"]=1; echo ">>> port NON-m1n1 ignoré : $d" ; continue ;;
      esac
      ifn="$(_acm_ifnum "$b")"
      case "$ifn" in
        00|02) ;;                                        # proxy (00) / vuart (02) : saisissables
        *) seen["$d"]=1; continue ;;                     # 01/03 = interfaces data, pas de tty pilotable
      esac
      # Ouvrir le port DÈS que les droits udev le permettent : le nœud brut peut rester root-only
      # ~quelques ms avant qu'udev pose le groupe uucp (-> "Permission denied"). On RÉESSAIE
      # l'ouverture jusqu'à ~3 s au lieu d'abandonner au 1er refus (= le bug qui ratait la fenêtre).
      local opened=""
      for _ in $(seq 1 200); do
        if ( exec 3<>"$d" ) 2>/dev/null; then opened=1; break; fi
        sleep 0.015
      done
      if [ -z "$opened" ]; then
        seen["$d"]=1; echo ">>> $d vu mais pas ouvrable à temps (droits udev) — ignoré."; continue
      fi
      ( exec 3<>"$d"; sleep 30 ) &                       # droits OK -> on TIENT le port ouvert
      HOLD_PID=$!; grab_dev="$d"; grab_if="$ifn"
      echo ">>> SAISI $d (if$ifn) à t+$(( $(date +%s) - t_start ))s — m1n1 tenu en proxy."
      break
    done
    [ -n "$grab_dev" ] && break
    sleep 0.01
  done
  [ -n "$HOLD_PID" ] || die "fenêtre ratée : aucun port m1n1 neuf en ${WAIT_S}s (Mac pas allumé ? câble ? backdoor pas active ? ModemManager ?)."

  # 3. Résoudre le port proxy (if00) pour le chainload.
  local P00=""
  if [ "$grab_if" = "00" ]; then
    P00="$grab_dev"
  else
    local i
    for i in $(seq 1 200); do P00="$(_find_m1n1_if00_node || true)"; [ -n "$P00" ] && break; sleep 0.01; done
  fi
  # Préférer le lien by-id stable s'il est déjà prêt (udev a eu le temps pendant la saisie), sinon nœud brut.
  local P00_byid; P00_byid="$(m1n1_port if00 || true)"
  [ -n "$P00_byid" ] && P00="$P00_byid"
  [ -n "$P00" ] || die "if00 (proxy) introuvable après saisie — relance et re-power-cycle."
  echo ">>> Port proxy : $P00"
  export M1N1DEVICE="$P00"

  echo ">>> chainload d'un m1n1 frais…"
  "$M1N1_PYTHON" "$M1N1_DIR/proxyclient/tools/chainload.py" -r "$M1N1_DIR/build/m1n1.bin" \
    > "${OUT:-/tmp}/catch_chainload.log" 2>&1 || true   # TOLÈRE le UartTimeout de ré-énumération (cosmétique)
  [ -n "$HOLD_PID" ] && { kill "$HOLD_PID" 2>/dev/null || true; }

  echo ">>> attente de la ré-énumération du port proxy…"
  local i
  for i in $(seq 1 150); do
    refresh_ports
    if [ -n "${M1N1DEVICE:-}" ] && [ -e "${M1N1DEVICE:-/nonexistent}" ]; then
      echo "✅ Mac en PROXY (port : $M1N1DEVICE)."
      return 0
    fi
    sleep 0.1
  done
  die "après chainload, le port proxy n'est pas revenu — relance et re-power-cycle."
}
