import os
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TRACES = os.path.join(ROOT, "traces")


def trace_dir(prefix):
    """Dossier traces/<prefix>* (ex. '20261108-025802' ou 'c11')."""
    for d in sorted(os.listdir(TRACES)):
        if d.startswith(prefix) or ("_" + prefix) in d:
            return os.path.join(TRACES, d)
    raise unittest.SkipTest("trace absente : " + prefix)

C8 = "20261108-004657"
C11 = "20261108-025802"
C12 = "20261108-032454"
BOOTS = ["20261107-043309", "20261107-043828", "20261107-045400", C8, "20261108-010915", "20261108-012015", C11, C12]
