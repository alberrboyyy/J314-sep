# pending/

Scripts qui **écrivent** vers le SEP ou modifient l'état du Mac. Un agent les prépare, **Albert les relit et les lance**.

Chaque script commence par :
```
# BUT : …
# ENDPOINTS TOUCHÉS : …
# RISQUE : … (ex. panic SEP jusqu'au reboot / risque sur l'état macOS)
# RÉSULTAT ATTENDU : …
# PRÉPARÉ PAR : <agent>, <date>
```

Jamais d'écriture vers les gigalockers / xART (0x13) / SKS (0x12) sans en comprendre l'effet sur macOS :
ces stockages servent aussi à FileVault et à la Data Protection de macOS.
