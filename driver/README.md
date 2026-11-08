# driver/ : banc de rejeu hors ligne (phase 2, étapes 1 à 5 de docs/driver_plan.md §4)

Python pur (stdlib), `python3 -m unittest discover -s driver/tests` depuis la racine du repo.
**Aucun matériel, aucun `tools/*.sh`, aucune écriture SEP, aucun `/dev/ttyACM*`.** `traces/` est lu, jamais écrit.
Rien n'est copié ni déduit d'un binaire Apple ; tout vient de `docs/verification_status.md` (statuts *proposés*,
la décision revient à Albert) et des traces.

## Statut des messages utilisés
- Découpage du mot (EP/TAG/TYPE/PARAM/DATA) : hypothèse (cohérent), très solide en lecture.
- Encodage GT (fc/fd/fe, compteur) : vérifié (côté macOS). En-tête OOL : vérifié (lecture).
- **Seulement « proposé »** (vérifié (proposé), pas encore tranché par Albert) : séquence d'init de 57 commandes (K6),
  structure 0x65 / CRC (K4), boucle 0x6c -> 0x6d (HO), `<03` => `>21` (K5).
- **Hypothèse, utilisé seulement comme étiquette** : noms d'endpoints/tailles FD (hypothèse selon verification_status),
  statut capteur `80 20 ...` (hypothèse ; trame `80 op idx len`).
Chaque module le répète dans sa docstring.

## Modules
- `sepreplay/mailbox.py` : étape 1, mot 64 bits + lecteur de `sep.log` (+ lignes `# ool`).
- `sepreplay/discovery.py` : étape 2, table 0xFD (nom -> EP, tailles) + lecteur des ouvertures CNTL. L'ordre d'annonce varie
  d'un boot à l'autre (3 ordres sur 8) : toujours chercher par nom.
