# hv/

Scripts de tracing passés à `run_guest.py -m`. Première tâche de l'agent **tracer** :

1. Trouver le tracer SEP existant dans `m1n1/proxyclient` (`SEPTracer`).
2. Écrire `trace_sep_filtered.py` ici : n'active que le tracing du mailbox SEP,
   filtre par endpoint (`SEP_EPS=0x08,0x12,0x13`), écrit un message par ligne dans un fichier,
   sans spammer la console.

Observation pure : jamais de modification, blocage ou injection de messages.
