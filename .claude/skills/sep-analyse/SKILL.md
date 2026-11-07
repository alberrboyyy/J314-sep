---
name: sep-analyse
description: Analyser une ou plusieurs captures SEP (sep.log) avec analysis/parse_trace.py et diff_traces.py, et consigner les résultats dans docs/ en séparant VU et INTERPRÉTÉ. À utiliser après chaque capture ou pour comparer deux captures.
---

# Analyse de traces SEP

## Format (hv/trace_sep_filtered.py)
`<epoch PC> <dir> EP=0x.. TAG=0x.. TYPE=0x.. PARAM=0x.. DATA=0x.. [ool=m1:0x...]`
- `>` AP→SEP (INBOX), `<` SEP→AP (OUTBOX). Mot 0 du mailbox : bits 0-7 EP, 8-15 TAG, 16-23 TYPE, 24-31 PARAM, 32-63 DATA.
- Lignes `#` : en-tête, `# epname` (noms annoncés via EP 0xFD TYPE 0), `# end seen=.. logged=..`.
- Horloge = PC (time.time()), pas le Mac. `hv_uart.log` (logs kernel macOS) n'a pas d'horodatage PC.
- Le tracer ne voit PAS les buffers en mémoire partagée (OOL) : le contenu des requêtes est absent.
- `marks.txt` (si présent) : `<epoch> <étiquette>` posés par Albert avec `tools/mark.sh`.

## Outils
```
python3 analysis/parse_trace.py traces/<dossier> [--ep 0x08] [--json] [-o analysis/out/x.json]
python3 analysis/diff_traces.py traces/<A> traces/<B> [--ep 0x08] [--seq]
python3 -m unittest discover -s analysis/tests
```
Sorties uniquement dans `analysis/out/` (jamais `traces/`).

## Méthode
1. Stats globales, puis par EP, puis fenêtre temporelle autour des actions humaines (marks.txt).
2. Comparer avant d'interpréter : boot vs boot (C2a/C2b) pour isoler le non-déterministe ; doigt vs mot de passe ;
   bon vs mauvais doigt. Un pattern vu dans une seule trace = coïncidence possible.
3. Écrire : `docs/messages.md` (statut `hypothèse`, source `trace:<dossier>`, lignes citées), rapport détaillé dans
   `analysis/out/<capture>_report.md`, entrée `docs/journal.md`. Jamais `vérifié` sans expérience dédiée (rôle du sceptique).

## Repères acquis (hypothèses, C1 = traces/20261107-033436_c1-boot)
- Endpoints annoncés : 0x00 cntl, 0x08 sbio, 0x0a scrd, 0x0c sse, 0x0e hdcp, 0x10 xars, 0x12 sks, 0x13 xarm,
  0x14 hibe, 0x15 pnon, 0x17 skdl, 0x18 stac.
- EP 0x08 : paires `TAG=0xfc TYPE=X` requête/écho ; `TAG=0xfe/0xfd` + DATA=0x000N0000 (fragments ?) ;
  notifications SEP→AP TAG=0x01..0x04 avec DATA=0x1f5 (501 = uid ?).
