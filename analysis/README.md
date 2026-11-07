# analysis/

Scripts Python (stdlib uniquement) de l'agent analyste : parsing des logs de `traces/`,
stats par endpoint/type, extraction de séquences, diff entre captures.

Ils lisent `traces/` et écrivent leurs sorties dans `analysis/out/` — jamais dans `traces/`.
