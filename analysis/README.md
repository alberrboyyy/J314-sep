# analysis/

Scripts Python (stdlib uniquement) de l'agent analyste : parsing des logs de `traces/`,
stats par endpoint/type, extraction de séquences, diff entre captures.

Ils lisent `traces/` et écrivent leurs sorties dans `analysis/out/` — jamais dans `traces/`.

## Format d'entrée

Une ligne par message (défini dans `.claude/agents/tracer.md`) :

    <timestamp> <dir> EP=0x.. TAG=0x.. TYPE=0x.. PARAM=0x.. DATA=0x.. [ool=...]

`dir` : `>` AP→SEP, `<` SEP→AP. Timestamp entier ou flottant. `ool=` optionnel, gardé en
chaîne opaque (tout le reste de la ligne). Les lignes vides et `#...` sont comptées comme
commentaires ; toute autre ligne hors format (ou champ hors plage : EP/TAG/TYPE/PARAM > 0xff,
DATA > 0xffffffff) est comptée comme invalide, les 5 premières sont affichées avec leur numéro.

## parse_trace.py — stats d'une capture

    python3 analysis/parse_trace.py traces/<capture>/            # lit <capture>/trace.log
    python3 analysis/parse_trace.py traces/<capture>/trace.log --ep 0x08,0x12
    python3 analysis/parse_trace.py traces/<capture>/ --json -o analysis/out/<capture>.json
    python3 analysis/parse_trace.py traces/<capture>/ --between doigt_pose doigt_leve   # fenêtre marks.txt (tools/mark.sh)

Stats par endpoint, par (ep, dir, type) et par (ep, dir, type, param) : count, premier/dernier
timestamp et numéro de ligne (pour citer la trace), nombre de DATA distincts.
`-o` n'accepte qu'un chemin sous `analysis/out/` (refus explicite ailleurs, en particulier `traces/`).
Réutilisable : `from parse_trace import parse_file` → `(messages, bad_lines)`.

## diff_traces.py — comparaison de deux captures

    python3 analysis/diff_traces.py traces/<A>/ traces/<B>/ [--ep 0x08] [--seq] [-o analysis/out/diff.txt]

Clés (ep, dir, type, param) seulement dans A, seulement dans B, et communes avec des comptes
différents. `--seq` : diff difflib de la séquence ordonnée (dir, type, param) par endpoint,
TAG et DATA ignorés, blocs différents affichés avec les numéros de ligne d'origine.
Une différence est une observation, pas une interprétation.

## sbio_transactions.py — transactions et rafales d'un endpoint

    python3 analysis/sbio_transactions.py traces/<capture>/ [--ep 0x08] [--gap 2.0] [-o analysis/out/x.txt]

Regroupe `> TAG=0xfc TYPE=X` / `< TAG=0xfc TYPE=X` en transactions (durée, lignes), rattache les 0xfe/0xfd de même
TYPE (« pendant » ou « après » la réponse), liste à part les autres messages. Modèle tiré de C1, pas une spécification.

## align_uart.py — ancrages sep.log ↔ hv_uart.log

    python3 analysis/align_uart.py traces/<capture>/ [-o analysis/out/x.txt]

Rapproche les lignes noyau de `hv_uart.log` (sans horodatage) des messages de `sep.log` : TAG xART (« Replied to xART
app »), CRC (« with CRC »), handles SKS (« handle -N » ↔ `< EP=0x12 TAG=0x00 DATA`), et liste les epochs écrits par macOS.
Numéros de ligne uart = `grep -n` (découpage sur `\n`).

## ool_view.py — dumps de buffers OOL (SEP_OOL_EPS du tracer)

    python3 analysis/ool_view.py traces/<capture>/            # trouve l'unique sep.log.ool/
    python3 analysis/ool_view.py traces/<capture>/sep.log.ool/ --ep 0x08 --buf A [--max-rows 32]

Par (ep, buf) : liste des `<seq>_<ep>_<buf>.bin` (taille, sha256[:8], octets non nuls), puis plages modifiées
et hexdump (`-` ancien / `+` nouveau / `^^`) entre deux dumps consécutifs. Le tracer n'écrit un .bin que si le
contenu change : deux dumps consécutifs ne sont pas forcément deux messages consécutifs (voir `# ool` dans sep.log).
Lecture seule, sortie stdout.

## Tests

    python3 -m unittest discover -s analysis/tests -v

`analysis/tests/fake_a/`, `fake_b/` et `fake_ool/` (dumps .bin) sont des données **inventées** (pas des captures) ;
ne jamais les citer comme source.
