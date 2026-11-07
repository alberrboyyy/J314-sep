# Hypothèses et expériences

Format :
```
## H<n> — <énoncé court>
- Statut : ouverte | confirmée | réfutée
- Fondée sur : traces/<dossier> (lignes / horodatages)
- Autres explications possibles :
- Expérience : … (AUTO via tools/ | EXPÉRIENCE HUMAINE)
- Si vraie : … / Si fausse : …
```

---

## Q0 — Question de sortie du jalon 1
- Statut : ouverte
- L'enrôlement et la vérification Touch ID dépendent-ils d'un état que seul macOS peut créer
  (keybags utilisateur, xART, credentials SCRD) ?
- Expériences prévues :
  1. Trace d'un boot complet (AUTO) → séquence d'init 0xFD / 0x13 / 0x12.
  2. Trace d'un déverrouillage Touch ID réussi (EXPÉRIENCE HUMAINE).
  3. Même chose avec un doigt non enrôlé (EXPÉRIENCE HUMAINE).
  4. Déverrouillage par mot de passe pour comparaison (EXPÉRIENCE HUMAINE).
  5. Single-user mode : SKS beaucoup moins bavard, utile pour isoler l'init (doc Asahi).
