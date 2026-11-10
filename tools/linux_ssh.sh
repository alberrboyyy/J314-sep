#!/usr/bin/env bash
# Accès au Linux de test (root@10.0.200.4 UNIQUEMENT), exception décrite dans CLAUDE.md.
# Usage : ./tools/linux_ssh.sh run "<commande>"      exécute une commande sur le Linux de test
#         ./tools/linux_ssh.sh put <local> <distant>  copie un fichier/dossier vers le Linux de test
#         ./tools/linux_ssh.sh get <distant> <local>  rapatrie un fichier/dossier
# Journal de tout ce qui est lancé : logs/linux_ssh.log
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="root@10.0.200.4"
OPTS=(-o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new)
mkdir -p logs
log() { printf '%s %s\n' "$(date +%F\ %T)" "$*" >> logs/linux_ssh.log; }
# Interdits même en root sur le Linux de test (voir CLAUDE.md) : disques, boot, m1n1, SEP.
DENY='(^|[^a-z])(dd|parted|fdisk|sfdisk|gdisk|mkfs[.a-z0-9]*|wipefs|asahi-bless|bputil|kmutil|csrutil|nvram|efibootmgr|m1n1|update-m1n1)([^a-z]|$)|/dev/(nvme|disk|sd|mmcblk)|sep|xart|gigalocker|0x1[0235]\b'
case "${1:-}" in
  run) shift; CMD="$*"
       if grep -Eqi "$DENY" <<<"$CMD"; then log "REFUSÉ: $CMD"; echo "Refusé par la règle de CLAUDE.md : $CMD" >&2; exit 2; fi
       log "run: $CMD"; ssh "${OPTS[@]}" "$HOST" "$CMD" ;;
  put) log "put: $2 -> $3"; scp -r "${OPTS[@]}" "$2" "$HOST:$3" ;;
  get) log "get: $2 -> $3"; scp -r "${OPTS[@]}" "$HOST:$2" "$3" ;;
  *) echo "usage: $0 run|put|get ..." >&2; exit 1 ;;
esac
