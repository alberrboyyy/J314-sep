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

## uart_timeline.py — chronologie fusionnée hv_uart.log + sep.log

    python3 analysis/uart_timeline.py traces/<capture>/ [--ep08-only] [-o analysis/out/x.txt]

Ancrages primaires (correspondances uniques et monotones) : CRC xART, TAG xART, et rang à rang
« Sending lock change X for handle H value V » ↔ `< EP=0x12 TAG=X TYPE=V DATA=H` (utilisé seulement si les deux suites
concordent entièrement). Ancrages secondaires : horloge du Mac (`IOConsoleUsers … now <epoch>`, `ACMTRM … now=N(boot)`)
corrigée d'un décalage PC−Mac mesuré + dérive linéaire (±1 s). Chaque ligne uart reçoit l'intervalle [ancrage
précédent ; suivant] ; seul cet intervalle compte, l'heure interpolée sert à intercaler. Lignes uart filtrées (ACMTRM,
AppleSEPKeyStore lock/unlock, xART, apfs keybag, biométrie, `SEP EP n`) ; sep : EP 0x08, EP 0x12 notifications, EP 0x13.

## sbio_latency.py — latence requête → réponse 0xfc

    python3 analysis/sbio_latency.py traces/<A>/ [traces/<B>/ ...] [--ep 0x08] [--fast-ms 10] [-o analysis/out/x.txt]

Paires `> 0xfc X` / premier `< 0xfc X` suivant ; médiane, moyenne, moyenne des paires < 50 ms (définition qui redonne
les chiffres C3 2.35 / C6 7.36 / C7 ~2.5 ms), et tableau par TYPE comparé entre captures. Horloge PC du tracer.

## attempt_compare.py — tentatives doigt vs séquence de référence

    python3 analysis/attempt_compare.py traces/<capture>/ [--ref traces/<C3>/ --ref-line 2147 --ref-n 25] [-o ...]

Découpage de `lock_cycles.attempts()`, comparaison mot à mot (dir/TAG/TYPE/PARAM/DATA) à N messages EP 0x08 d'une
capture de référence (défaut : la séquence succès de C3 L2147), différences difflib avec numéros de ligne.

## ool_index.py — lecture OOL ↔ message

    python3 analysis/ool_index.py traces/<capture>/ [--ep 0x08] [-o analysis/out/x.txt]

Rattache chaque `# ool` au message qui le précède et au .bin (ou au dernier .bin du buffer si `changed=none`) ; fin du
contenu non nul. `from ool_index import load_index`.

## ool_attempts.py — comparaison octet par octet des charges OOL par tentative

    python3 analysis/ool_attempts.py traces/<capture>/ [--dump-dir analysis/out/<x>/] [-o analysis/out/x.txt]

Classe chaque tentative (abort / good / bad selon la marque fp_good*/fp_bad* — à recouper avec notes.txt), recolle
les morceaux 0xfc/0xfd selon l'en-tête observé de 0x1c octets, puis par (dir, buf, TYPE) : octets constants,
discriminants good/bad, variables, entropie par 64 octets. `--dump-dir` écrit les charges recollées.

## Tests

    python3 -m unittest discover -s analysis/tests -v

`analysis/tests/fake_a/`, `fake_b/` et `fake_ool/` (dumps .bin) sont des données **inventées** (pas des captures) ;
ne jamais les citer comme source.

## kext/ — phase 2 : lecture du kernelcache (source: kext)

    python3 analysis/kext/macho_fileset.py macos/kernel.macho [BUNDLE_ID]
    VENV/bin/python analysis/kext/kdis.py macos/kernel.macho BUNDLE_ID strrefs|vcallers SLOT|callers ADDR|func ADDR
    python3 analysis/kext/mesa_cmd_map.py macos/kernel.macho      # après `kdis.py ... vcallers 0x9e0/0x9d8`
    python3 analysis/kext/ksyms.py macos/kernel.macho [REGEX] | --at ADDR...   # table de symboles du kernelcache
    python3 analysis/slice_crc.py analysis/out/c8_payloads/*inA_65.bin          # trames/CRC-16 des tranches 0x65
    python3 analysis/kext/mesa_case_reach.py macos/kernel.macho   # après `kdis.py ... func 0xfffffe000977eecc > analysis/out/kext/f_psc.txt`

`kdis.py` demande capstone (venv hors repo). Les listings (`func`) et index vont dans `analysis/out/kext/` (ignoré) :
ne jamais les commiter ni les recopier dans docs/ ou driver/ (CLAUDE.md phase 2). Adresses codées en dur dans
`mesa_cmd_map.py` / `mesa_case_reach.py` : valables pour le kernelcache 13.5 de `macos/` uniquement.
