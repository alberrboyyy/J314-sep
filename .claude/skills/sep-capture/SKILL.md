---
name: sep-capture
description: Lancer une capture SEP sur le Mac (macOS 13.5 sous hyperviseur m1n1) de façon sûre et autonome via tools/boot_and_trace.sh, la surveiller et la valider. À utiliser pour toute capture ou reboot du Mac.
---

# Capture SEP — procédure

Règles de CLAUDE.md d'abord (observation pure, hardware uniquement via `tools/*.sh`, `traces/` en lecture seule).
Une seule capture à la fois : c'est l'orchestrateur (session principale) qui touche au Mac, jamais deux processus.

## Avant
1. Ports : `ls -l /dev/serial/by-id/` doit montrer `usb-Asahi_Linux_m1n1_uartproxy_*-if00` (proxy) et `-if02` (UART HV).
   Ne JAMAIS se fier à `ttyACM0/1` : un téléphone Android branché prend `ttyACM0` (vu le 2026-11-07, réponses `+CME Error`).
   `tools/env.sh` résout les ports via by-id (`refresh_ports`).
2. Personne d'autre sur les ports :
   `for p in /proc/[0-9]*; do ls -l $p/fd 2>/dev/null | grep -q ttyACM && echo "$(basename $p) $(tr '\0' ' ' < $p/cmdline)"; done`
   Un `cat /dev/ttyACM*` d'Albert ou un vieux `run_guest.py` → lui demander de l'arrêter (ne pas le tuer soi-même).
3. Ne pas modifier `tools/boot_and_trace.sh` ni `tools/env.sh` pendant qu'une capture tourne (bash lit le script
   au fil de l'eau) : écrire `*.new` puis `mv` après.

## Lancer
```
TRACE_TIMEOUT=300 [SEP_EPS=0x08,0x12] ./tools/boot_and_trace.sh <nom> > <scratchpad>/<nom>-run.log 2>&1   # run_in_background
```
- Mode auto (défaut) : fin par SIGINT → shell HV → `reboot()` (via FIFO) → attente du retour de m1n1 (`proxy_back_after_reboot` dans meta.txt).
- `TRACE_SCRIPT=none` : sans tracer. `--interactive` : stdin = terminal d'Albert (il fait Ctrl-C puis `reboot()`).
- Surveiller avec Monitor sur le run.log, filtre couvrant succès ET échecs :
  `Capture ->|Proxy is alive|trace_sep_filtered|Jumping to entrypoint|Entering hypervisor shell|>> |ATTENTION|Terminé|Traceback|Error|Timeout|panic`
  (`Error getting cpu-uttdbg-reg property` est bénin, présent à chaque boot.)

## Après
- `meta.txt` : `end_reason`, `sep_lines`, `proxy_back_after_reboot: yes`.
- `sep.log` non vide, `python3 analysis/parse_trace.py traces/<dossier>` → 0 ligne invalide attendu.
- Entrée dans `docs/journal.md` (date, trace, actions humaines avec heures, incidents).

## Pannes connues
- `chainload.py` bloqué après « Reloading into stub » sans déconnexion USB : vu après un redémarrage à chaud depuis
  macOS ; un démarrage à froid (appui long power) a réglé. Non vérifié comme cause.
- `SerialException: device reports readiness to read but returned no data` : déconnexion USB du Mac ; regarder
  `journalctl -k | grep "usb 1-1"`. macOS peut continuer à tourner sans client → seul Albert peut rebooter.
- Mac injoignable : ne pas insister, noter dans le journal, demander UNE action physique claire à Albert.
