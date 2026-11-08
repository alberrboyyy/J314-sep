# Journal

Une entrée par observation, capture ou décision. Plus récent en haut.

Format :
```
## AAAA-MM-JJ HH:MM — <agent ou Albert> — <titre>
- Trace : traces/<dossier> (ou —)
- Fait : ce qui a été fait
- Vu : ce qui a été observé (faits bruts)
- Interprété : ce qu'on en pense (hypothèses → docs/hypotheses.md)
- Incidents : gels, timeouts, reboots
```

---

## 2026-11-08 — Claude (session principale) — C10b : contrôle de persistance (HI/HO)
- Trace : traces/20261108-012015_c10b-boot-ool-stable (TRACE_TIMEOUT=300, config OOL de C9, aucun humain, aucun boot natif entre C9 et C10b).
- Vu : boot complet (hv_uart 2168 lignes, sep.log 779, 0 ool_error). `analysis/init_persist.py --ref C9` : réponses d'init 0x54 (0xbf4 o),
  0x6e, 0x7a = 0 octet différent de C9. Les 4 lectures `# ool` du `> A 0x6d` d'init ont les mêmes sha/nz que C9 (e87ef868, 7e50186d, fa51f810, 791868ac).
- Interprété (hypothèse) : sans succès entre deux boots, macOS renvoie le même blob 0x6d et le SEP rend la même 0x54 → cohérent avec HO
  (blob exporté par 0x6c après succès, conservé par macOS, renvoyé au boot). Ne distingue pas encore « 0x54 dérivée du blob » de « état SEP propre » :
  il faudrait un boot où macOS ne renvoie pas le blob, ce qu'on ne peut pas provoquer en phase 1 sans écriture.
- Incidents : aucun.

## 2026-11-08 — analyste — Correctif ool_index, test HO sur C9, invariants d'en-tête C5-C9
- Trace : traces/20261108-004657_c8-doigt-ool, traces/20261108-010915_c9-boot-ool-persist ; C5, C6, C7 pour les invariants.
- Fait : `analysis/ool_index.py` : les lignes `changed=none` sont maintenant rattachées au dernier .bin de même (buffer,
  longueur), comme la comparaison du tracer ; contrôle sha256[:8] de chaque contenu rattaché (`sha_ok`). Ancienne version :
  15 rattachements faux dans C8 (L1684, 2209, 2361, 2430, 2840, 2978, 3001, 3493, 3631, 3833, 3836, 3866, 4089, 4227, 4383),
  0 dans C5/C6/C7/C9 ; nouvelle : 0 faux sur C5-C9. Test synthétique ajouté (25/25 OK). `c8_ool_index.txt` régénéré ;
  `c8_ool_attempts.txt` inchangé (les charges des tentatives n'étaient pas touchées). docs/messages.md corrigé : en-tête
  TYPE 430/430 sans exception, `<fe` = B entièrement nul (14/14), répartition des notifications refaite.
  Nouveau `analysis/ool_invariants.py` → `analysis/out/c5_c9_ool_invariants.txt`.
- Vu (HO) : `> A 0x6d` d'init identique dans C5-C8 et **changé dans C9** : petit blob (0xf4) = export `< B 0x6c` de C8 L3250
  (même sha), gros blob 0x9317 o = longueur de l'export C8 L3226 (fp_good_3), 0x3e4 premiers octets identiques (seuls lus
  dans C8). `> A 0x5b` (0xfc99 o) identique C5-C9. `< B 0x5f` différent à chaque boot. Blobs 0x6c/0x6d : magic `LTFC`,
  u32 0x0a, uid, puis ~8 bits/octet.
- Vu (invariants C5-C9, 1695 lectures) : 0 violation sur `+0x00` ∈ {0,1} ⇔ nul, TYPE, longueur de morceau, `+0x0c`/`+0x10`=0 ;
  51 cas d'octets au-delà de la fin du morceau, tous = reste de la lecture précédente du même buffer.
- Vu (`+0xc24`, C6+C8) : pas une fonction de `+0x48`/`+0x07` de 0x06 ni de `+0x24` de 0x07 (C6, `+0x48`=0 : 5, 0x1b, 6, 0x1b).
  1er flottant de 0x07 (`+0x18`) : 0.040-0.048 pour les 3 mauvais doigts, 0.103-0.146 pour les 12 autres tentatives à 0x09 ou
  abandonnées (C6+C8) — confondu avec `+0x44`=5 / fin de session (réserve du sceptique).
- Interprété (hypothèse) : HO soutenue — le SEP exporte un blob chiffré par uid après chaque succès (0x6c), macOS le stocke
  et le renvoie au boot (0x6d) ; l'enregistrement 0x54 (HI) en dérive. Conséquence pour un futur driver : il devrait
  conserver et renvoyer ce blob. 1 boot, export lu tronqué : à confirmer (0x6c en lecture complète, C10/C11).
- Incidents : aucun (aucune action hardware).

## 2026-11-08 — Claude (session principale) — C10 : boot de contrôle bloqué
- Trace : traces/20261108-011515_c10-boot-ool-stable (TRACE_TIMEOUT=200, même config OOL que C9).
- Vu : hv_uart.log s'arrête à 806 lignes (C9 : 2631), dernière ligne `IOPort::registerService(): [Port-MagSafe 3@1] Regi` tronquée ;
  sep.log 256 lignes, 5 messages EP 0x08, aucune réponse 0x54/0x6e/0x7a ; 0 ool_error ; aucun panic dans l'uart. end_reason=timeout, proxy revenu.
- Interprété : boot de macOS bloqué ou très ralenti avant l'init SBIO ; cause inconnue. Capture inutilisable pour HI.
- Fait : relance (C10b) avec TRACE_TIMEOUT=300.
- Incidents : blocage de boot ci-dessus.

## 2026-11-08 — tracer — Script de session humaine C11 (outillage, aucune action hardware)
- Trace : — (protocole : docs/hypotheses.md « Revue sceptique de C8 », section « C10 — Session doigt », renommée C11 ;
  C10 = boot de contrôle traces/20261108-011515_c10-boot-ool-stable)
- Fait : `tools/guide_doigt_c11.sh` (forme de `guide_doigt.sh`). Étiquettes : loginwin, pw_login, lock_m1, fp_bad_1, fp_good_1,
  lock_m2, fp_tap_1..3, fp_good_2, lock_m3, fp_tip_1, fp_good_3, fp_app_prompt, fp_app_good, fp_app_quit, fp_app_prompt2,
  fp_app_bad, uid_check, end. Notes : res_* , uid_id_u, uid_generateduid, fin. Invite session ouverte : Réglages Système >
  Mots de passe (reverrouillée en quittant Réglages Système ; non vérifié sur ce Mac, repli = marque `anomalie`).
  Config recommandée en en-tête : SEP_OOL_EPS=0x08, SEP_OOL_BYTES=0x400, SEP_OOL_SPLIT_DIR=1,
  SEP_OOL_FULL_TYPES=0x09,0x21,0x45,0x54,0x5b,0x5f,0x65,0x6c,0x6d, TRACE_TIMEOUT=1500. `bash -n` OK. Non commité.
- Vu (lecture seule de hv/trace_sep_filtered.py) : 0x6c est accepté : SEP_OOL_FULL_TYPES passe par `_parse_eps` (toute valeur
  0..0xff) et `_ool_dump` teste `typ in full_types` ; seul EP 0x08 est concerné (SEP_OOL_EPS). Coût : 3 lectures B de 0x4000
  par succès ; plafond SEP_OOL_MAX_MB=64 non menacé (C8 : 2,7 Mo de .bin).
- Interprété : — . Point ouvert : la fin par `stop_capture.sh` = reboot() HV (arrêt non propre, piège (a) de HO) ; un arrêt
  propre de macOS avant le boot de test de persistance (C12 ?) est à décider par Albert.
- Incidents : aucun.

## 2026-11-08 — analyste — C9 : test HI (réponse 0x54 d'init après la session C8)
- Trace : traces/20261108-010915_c9-boot-ool-persist (boot sans humain, même config OOL que C7/C8, 0 `ool_error`, aucune
  tentative doigt) ; références : C5, C6, C7, C8 (init) et réponses 0x09/0x21 des 3 succès de C8.
- Fait : `analysis/init_persist.py` → `analysis/out/c9_init_persist.txt` (diff octet par octet, offsets dans la charge).
- Vu : requête `> A 0x54` (L554) identique à C5-C8. Réponse `< B 0x54` (L556, 0xbf4 o) : 24 octets différents de l'init
  C5/C6/C7/C8 ; 6 différents de la copie dans 0x09 de fp_good_3 ; **0 différent** de la copie dans la réponse 0x21 de
  fp_good_3 (C8 L3054 ; offsets 0x06-0x2d de l'enregistrement non comparables, recouverts dans 0x21). Même chaîne dans C8 :
  0x21 du succès N = 0x09 du succès N+1 (2/2). Les 3 essais mauvais doigt n'ont rien changé. Réponses d'init 0x6e (L572) et
  0x7a (L576) : identiques à C5-C8 (l'identifiant 16 o ne change pas).
- Interprété (hypothèse HI, une seule observation de boot) : l'enregistrement est conservé par le SEP au reboot et mis à jour
  à chaque succès ; 0x09 donne l'état avant, 0x21 l'état après. Lieu de stockage (xART ?) et sens des champs : inconnus.
  Ne passe pas en `vérifié` : à confirmer par le sceptique (ex. 2e boot sans succès : 0x54 doit rester égal à C9).
- Incidents : aucun.

## 2026-11-08 — lecteur-logs (intégré par l'analyste) — C8 : alignement hv_uart ↔ sep.log, chemins SKS doigt / mot de passe
- Trace : traces/20261108-004657_c8-doigt-ool (hv_uart.log, sep.log, marks.txt) ; recoupements C3 (traces/20261107-035930_c3-touchid)
  et C1 (traces/20261107-033436_c1-boot).
- Fait (lecteur-logs) : `analysis/uart_timeline.py` → `analysis/out/c8_uart_timeline.txt` ; rapport `analysis/out/c8_uart_align.md`.
  98 ancrages primaires (24 CRC xART, 45 TAG xART, 29 lock change SKS), monotones, 0 rejeté ; horloge Mac : PC − Mac ≈ +71546 s,
  dérive ~0.8 s/100 s (17 points), donc ±1 s pour les lignes ACMTRM.
- Fait (analyste) : recompte indépendant des points repris dans docs/messages.md (section « SKS (0x12) et xART (0x13) — C8 ») ;
  correction d'une ligne citée (2e déverrouillage mot de passe : L4287, pas L4288) ; `analysis/lock_cycles.py` lit maintenant
  `now=N(B)` (epoch = N + B ; C8 = secondes + base) et ramène l'heure Mac à l'heure PC (`--mac-offset auto`, via
  uart_timeline ; ignoré si < 2 s → sortie C3 inchangée) ; tests 24/24 ; `analysis/out/c8_lock_cycles.txt` régénéré (états
  écran enfin rattachés : LOCKED/UNLOCKED autour de chaque tentative).
- Vu : uart « Sending lock change X for handle H value V » ↔ `< EP=0x12 TAG=X TYPE=V DATA=H`, rang à rang : C8 29/29, C3 34/34,
  C1 6/6 (TAG=0x01 = verrouillage, 0x00 = déverrouillage). 2 « Saving USER-xART with CRC » (`< EP=0x13 TYPE=0x01 PARAM=0x9c`)
  par tentative atteignant 0x09, succès comme échec (6/6 ; C3 19/20), aucun dans les abandons. Le 2e `<01/09` d'un
  verrouillage suit de 1-4 ms le verrouillage keybag/volume (`> EP=0x12 TAG=0x2f` → 3 × `< TAG=0x01`) : C8 4/4, C3 3/4.
  Doigt : aucune requête AP 0x12 ; notif -501 émise par le SEP pendant 0x09, dans les 3 succès seulement (recoupe la
  réponse OOL 0x09 de l'analyste). Mot de passe : `> TAG=0x41 DATA=0x01c80000` puis `> TAG=0x18 DATA=0x007c0000` → -501.
  Échec doigt : aucune ligne noyau (ni erreur biométrique, ni keybag). Aucune ligne `AppleBiometric*`/`AppleMesa*` pendant
  les essais. `lock_g1` posée ~26 s avant le verrouillage réel.
- Interprété (hypothèses) : le SEP déverrouille lui-même le keybag 501 quand la comparaison réussit ; USER-xART = état
  sauvegardé à chaque comparaison (compteur d'essais ?), indépendant du résultat.
- Incidents : aucun (aucune action hardware).

## 2026-11-08 01:07 — analyste — Analyse C8 (session doigt, OOL allégé) : contenu des réponses 0x09/0x21/0x07
- Trace : traces/20261108-004657_c8-doigt-ool (sep.log, sep.log.ool/, marks.txt, notes.txt). Comparaisons :
  traces/20261107-035930_c3-touchid (séquences), traces/20261107-043828_c6-doigt-ool (OOL, 5 refus bon doigt),
  C5/C7 (réponse 0x54 de l'init).
- Fait : nouveaux scripts `analysis/sbio_latency.py`, `attempt_compare.py`, `ool_index.py`, `ool_attempts.py`
  (+ `analysis/tests/test_c8_tools.py`, synthétique ; 22/22 tests OK). Sorties : `analysis/out/c8_latency.txt`,
  `c8_attempts.txt`, `c8_lock_cycles.txt`, `c8_ool_index.txt`, `c8_ool_attempts.txt`, `c8_payloads/`, `c8_stats.txt`,
  `c3_c8_diff_ep08.txt`, `c6_ool_attempts.txt`, `c6_payloads/`. Table : `docs/messages.md` section C8.
- Vu (latence) : `# ool_stats` L4480 : 480 lectures, 0.45 ms moy. (max 1.50), 216 ms au total, 0 `ool_error`.
  Requête→réponse 0xfc : moyenne des paires < 50 ms = 3.62 ms (même définition : C3 2.35, C7 2.47) ; médiane 1.59 ms ;
  sur les seuls TYPE présents dans C7 : 2.17 ms (C7 2.21). L'écart vient des commandes doigt longues (0x07 ~20 ms,
  0x23 ~6.6 ms) absentes de C7 ; TYPE par TYPE, C8 ≈ C7.
- Vu (séquences) : séquence « succès » de 25 mots de C3 L2147 reproduite bit à bit dans fp_good_2 (L2399) et fp_good_3
  (L2968) ; fp_good_1 (L1698) : mêmes mots, `<03/00` avant `<fc 70`. 3 abandons `23 06 65 07 22` avant un succès
  (L1674, L2351, L2375). Mauvais doigt : 3 tentatives (L3621, L3687, L4217) = séquence échec de C3, + `2b` après `<fc 70`
  dans 2/3. 0x09 : succès 235-250 ms, échecs 277-303 ms.
- Vu (OOL) : en-tête commun de 0x1c octets (1, longueur totale, offset du morceau, 0, 0, TYPE, longueur du morceau).
  Réponse 0x09 (0xca2 o, 6/6) : succès 3/3 = 0x1f5 + 16 octets fixes `fe6003d8…371b` + copie de la réponse 0x54 de
  l'init (L556 ; 0xbf4 o, identique dans C5/C6/C7/C8) ; échecs 3/3 C8 + 5/5 C6 = 0xffffffff + zéros sur 0x40-0xbff.
  Réponse 0x21 = même contenu que 0x09 réarrangé. Réponse 0x07 : `+0x06..07` = `01 01` dans les 11 tentatives suivies
  de 0x09, `00 00` dans les 4 abandons (C8+C6). Requête 0x65 = 12 blocs de 0x980 o, en-tête de 0x17 o avec compteurs,
  corps à ~8 bits/octet, incompressible. Réponse 0x70 = magic `HRLB` + 0x48 octets à haute entropie. Le 0x1f répond `05 05`
  partout. Aucune notification n'a de contenu OOL propre.
- Interprété (hypothèses HE-HJ dans docs/hypotheses.md) : le résultat de la comparaison est dans la réponse 0x09
  (uid/identifiant/enregistrement si correspondance, -1/zéros sinon), le mot mailbox ne le porte pas ; `+0xc24` est un
  code ou un score (succès 2, 2, 1 ; mauvais doigt 0x2e ×3 ; C6 5, 5, 0x1b, 6, 0x1b) ; 0x07 décide abandon/comparaison ;
  0x65 = trames capteur chiffrées ou compressées (contenu non interprété).
- Limites : `lock_cycles.py` colonne « état écran » inutilisable dans C8 (horloge du Mac `now=504…992`, pas un epoch) :
  rattachement fait par les marques + notes.txt. Un seul utilisateur et un seul doigt enrôlé (supposé) : l'identifiant
  16 o ne peut pas être attribué (utilisateur, gabarit, appareil). 3 succès / 3 échecs mauvais doigt : petits nombres.
- Incidents : aucun (aucune action hardware).

## 2026-11-07 — tracer — Lecture OOL allégée (SEP_OOL_BYTES=0x400, types complets, une direction, cache IOVA→PA)
- Trace : — (aucune action hardware). Chiffres tirés de traces/20261107-043309_c5-ool-boot et
  traces/20261107-043828_c6-doigt-ool (sep.log lignes `# ool`, fichiers sep.log.ool/*.bin), et de C3
  (traces/20261107-035930_c3-touchid) pour la référence.
- Constat (mesuré par la session principale) : latence requête→réponse SBIO 2.35 ms (C3, ASYNC, sans OOL) →
  7.36 ms (C6, SYNC + SEP_OOL_EPS=0x08). Dans C6 le seul essai bon doigt a échoué (0x22 = abandon puis reprise,
  0x09 sans notif 01/08, puis 01/45), puis macOS s'est mis en veille (cause non établie). Lien avec la lenteur :
  possible, non établi.
- Vu (C5/C6, ce que j'ai recompté) : `elapsed_ms` = 1.83-1.94 ms par buffer (max 2.44), identique pour A et B,
  = 4 commandes de traduction + 1 readmem 0x4000 ; 2 buffers par message → ~3.7 ms, dont ~3.7 ms côté `>`
  avant que le message n'atteigne le SEP. Taille de contenu (dumps C6, mesure session principale) : 136 vides,
  234 < 0x400, 11 < 0x1000, 23 jusqu'à 0x4000 ; gros (>0x1000) : `> 0xfc|0xfd/0x65 A` (6+6), `> 0xfd/0x5b A` (3),
  `< 0xfc|0xfd/0x5f B` (2+2), `> 0xfd/0x6d A` (2), `> 0xfc/0x5b A`, `> 0xfc/0x6d A`.
  Recompte de la fin du contenu non nul dans les .bin : entre 0x400 et 0x1000 → `< B` TYPE 0x09 (0xcbe, 4/5),
  0x45 (0xcbe, 1/3), 0x21 (0xcaa, 5/5), 0x54 (0xc0f) — ces réponses seront TRONQUÉES avec le défaut 0x400.
- Vu (choix d'une seule direction) : `> B` = tout à zéro (sha 4fe7b59a = 0x4000 zéros) dans 71/73 (C5) et
  141/143 (C6) cas ; les 2+2 autres ont `changed=none` (identiques à la lecture `<` B précédente). `< A` :
  `changed=none` dans 78/78 (C5) et 156/162 (C6) ; les 6 autres sont une remise à zéro complète (sha 4fe7b59a).
  Donc lire A seulement sur `>` et B seulement sur `<` n'aurait perdu aucun contenu non nul nouveau dans C5/C6 ;
  seule perte : l'instant où A est remis à zéro (6 cas C6) et où B l'est (visible au `<` suivant).
- Fait (`hv/trace_sep_filtered.py`, rien dans m1n1, non commité) : SEP_OOL_BYTES défaut 0x400 ;
  SEP_OOL_FULL_TYPES (défaut 0x65,0x5b,0x5f,0x6d) = lecture de la taille apprise entière ; SEP_OOL_SPLIT_DIR
  (défaut 1 : `>`→A, `<`→B ; 0 = ancien comportement) ; traduction IOVA→PA en plages contiguës mise en cache par
  buffer (un readmem par plage contiguë ; invalidée sur erreur de lecture et sur CNTL 2/3/4/5 qui change
  IOVA/taille ; revalidée toutes les SEP_OOL_REVALIDATE_N=64 lectures → `# ool remap` si changée) ; ligne
  `# ool` + `full= xlat=hit|miss|reval rm= [trunc=1]` ; `changed` compare des lectures de même longueur ;
  `# ool_stats` (n, mean/max/total ms, octets, nb traductions, par direction) avant `# end`.
- Vérifié hors ligne : py_compile ; stubs m1n1 + faux DART t6000/RAM (scratchpad) : 1 readmem par lecture en
  cache, fusion de 2 pages contiguës en 1 plage (3 pages → 2 readmem), remap détecté, erreur → cache invalidé,
  `# ool_stats` cohérent.
- Estimation (NON mesurée) : en supposant ~0.12 ms par commande proxy et ~1.3 ms pour readmem 0x4000 (déduit de
  1.86 ms = 4 petites commandes + 1 gros readmem, répartition non mesurée), côté `>` : ~0.2 ms (TYPE courant)
  ou ~1.4 ms (TYPE complet) au lieu de ~3.7 ms → latence SBIO attendue ~3.9 ms (types complets ~5 ms), pas
  2.35 ms : le reste (~1.3 ms) vient des exceptions SYNC elles-mêmes, que ce changement ne touche pas.
- Risques : avec le cache, un remappage de l'IOVA sans message CNTL ferait lire l'ancienne PA (toujours vérifiée
  dans la RAM, lecture seule) jusqu'à la revalidation ; les réponses `< B` 0x09/0x21/0x45/0x54 sont coupées à
  0x400 (`trunc=1`) sauf à les ajouter à SEP_OOL_FULL_TYPES (coût après dépilement de la réponse, pas sur la
  latence requête→réponse).
- Interprété (hypothèse, non vérifiée) : TYPE 0x65 (`>` A, 12 fois dans C6, contenu jusqu'à 0x4000, absent de
  C5 sans doigt) = relais de données capteur AP→SEP. Repose sur une corrélation temporelle avec l'essai doigt.
- Incidents : aucun (aucune action hardware).

## 2026-11-07 — tracer — Option SEP_OOL_EPS (lecture seule des buffers OOL par endpoint, validée par Albert)
- Trace : — (aucune action hardware). Conçu d'après traces/20261107-042414_c4-shmem/sep.log L136-L144
  (`> EP=0x00 TAG=0x07 TYPE=0x04/0x02/0x05/0x03 PARAM=0x08 DATA=0x4000/0x54/0x4000/0x5c`) et L14-L23 (dart-sep
  `dart,t6000` sid 0, 0x4000 octets lus en 2.4 ms).
- Fait : `hv/trace_sep_filtered.py` (rien dans m1n1). Désactivé par défaut (SEP_OOL_EPS vide). Si actif :
  - apprentissage depuis `> EP=0x00` TYPE 2/3/4/5, EP cible = PARAM : A = (TYPE 2 → IOVA=DATA<<12, TYPE 4 → taille),
    B = (TYPE 3, TYPE 5) ; ligne `# ool learn` par valeur ; rien de codé en dur ;
  - INBOX et OUTBOX en SYNC toute la session (header `mode=SYNC(forcé par SEP_OOL_EPS)`) ; à chaque message
    (> et <) d'un EP de la liste, lecture de min(SEP_OOL_BYTES=0x4000, taille) octets de chaque buffer connu via
    SepDartReader (lecture seule, PA vérifiées dans la RAM, stream mémorisé par buffer) ;
  - ligne `# ool <ts> seq= EP= dir= buf= sha= nz= changed= len= elapsed_ms= [file=]` juste après la ligne du
    message ; `.bin` seulement si changement (`<SEP_TRACE_OUT>.ool/<seq>_<ep>_<buf>.bin`), plafond SEP_OOL_MAX_MB
    (64) → `# ool_cap` ; toute exception → `# ool_error`, le tracing continue.
  - `analysis/ool_view.py` + `analysis/tests/test_ool_view.py` (fixtures synthétiques `analysis/tests/fake_ool/`).
- Vérifié hors ligne : py_compile ; test avec stubs m1n1/hv et fausse mémoire + faux DART t6000 (scratchpad, non
  versionné) : apprentissage, init/changed/none, `.bin` seulement si changé, erreur contexte async, erreur TCR
  bypass sans arrêt, plafond, aucune écriture appelée. diff_ranges du tracer = celui d'ool_view (3000 cas
  aléatoires). Tests analysis : 19/19 OK.
- Interprété (hypothèses) : l'association TYPE 2/4 = A et 3/5 = B, et « un buffer par direction », viennent de
  l'analyste ; non vérifiées. seq = compteur `seen` de tous les messages (1 = premier), pas un numéro de ligne.
- NON TESTÉ sur le Mac : SYNC permanent des deux boîtes (coût par accès MMIO = aller-retour USB) ; durée réelle
  (estimation ~5 ms/message pour 2 × 0x4000, soit ~0.1-0.2 s par rafale SBIO de 25 messages) ; tolérance de
  macOS/SEP à ce ralentissement (timeouts possibles) ; cohérence des dumps : le SEP lit/écrit ces buffers et
  continue de tourner pendant la lecture (seuls les CPU du guest sont arrêtés), un dump peut être partiel.
  Moment : '>' avant que le SEP ne reçoive le message, '<' après dépilement par l'AP.
- Note : `boot_and_trace.sh` transmet l'environnement (SEP_OOL_EPS passe), mais meta.txt n'enregistre que
  SEP_EPS ; la config OOL est dans l'en-tête de sep.log.
- Incidents : aucun.

## 2026-11-07 04:35 — tracer — Option SEP_SHMEM_DUMP (lecture unique de l'en-tête shmem SEP, validée par Albert)
- Trace : — (aucune action hardware ; déclencheur choisi d'après traces/20261107-033436_c1-boot et
  traces/20261107-035422_c3-touchid/sep.log L13 `> EP=0xfe TAG=0x01 TYPE=0x1c DATA=0x00000580`)
- Fait : `hv/trace_sep_filtered.py` (rien dans m1n1). Désactivé par défaut. `SEP_SHMEM_DUMP=1` : au premier
  `> EP=0xfe` TYPE 0x1c ou 0x18, IOVA = DATA<<12 (hypothèse m1n1 hw/sep.py), lecture de 0x4000 octets via
  `/arm-io/dart-sep` → `<SEP_TRACE_OUT>.shmem_hdr.bin` + lignes `# shmem trigger|dart|hdr|table|entry|region|done`
  dans sep.log ; erreurs → `# shmem_error ...`, le tracing continue. `SEP_SHMEM_DUMP_FULL=<octets>` : dump de
  chaque région de la table (plafond par région, total ≤ 32 MiB). `SEP_SHMEM_WHEN=trigger|next`,
  `SEP_SHMEM_SYNC_MAX` (défaut 64 messages AP→SEP sans déclencheur → abandon).
- Vu (lecture du code m1n1, pas d'expérience) : en ASYNC le handler tourne dans `proxy.py reply()` pendant que le
  guest tourne ; une commande proxy à ce moment ferait entrer m1n1 dans `hv_tick` → USER_INTERRUPT → shell HV.
  Lecture mémoire possible seulement dans une exception (`hv.ctx` non nul). Donc avec SEP_SHMEM_DUMP=1, INBOX
  (écritures AP→SEP seulement) est tracé en SYNC jusqu'à la lecture, puis repasse dans le mode normal.
  En SYNC le handler tourne avant que m1n1 ne rejoue l'écriture INBOX1 : en mode `trigger` le SEP n'a pas
  encore reçu le message EP=0xfe quand on lit.
- Traduction DART refaite en lecture seule (TCR/TTBR par read32, PTE 8 octets, adresses vérifiées dans
  [hv.ram_base, +ram_size)), compatibles dart,t8020/t6000 seulement ; stream 0 essayé d'abord, puis les autres
  streams actifs. Aucune écriture SEP/DART/mémoire guest.
- Vérifié hors ligne : py_compile ; test avec un faux hv/DART/RAM (scratchpad) : table décodée, régions plafonnées,
  erreurs (contexte async, IOVA non mappée, PA hors RAM) → `# shmem_error`, retour au mode normal appelé.
- Non testé : tout sur le matériel (compat et stream de dart-sep sous 13.5, DATA<<12, format de la table côté
  macOS, mélange SYNC/ASYNC et bascule en cours de route, durée réelle, réaction du SEP à la pause).
  `boot_and_trace.sh` n'écrit pas SEP_SHMEM_* dans meta.txt (seule la ligne `# trace_sep_filtered start ... shmem=`
  de sep.log le note).
- Incidents : aucun.

## 2026-11-07 04:30 — analyste — Analyse de C3 (Touch ID : lock, mot de passe, bon/mauvais doigt)
- Trace : traces/20261107-035930_c3-touchid/ (sep.log 5841 lignes, 887 msgs EP 0x08 ; hv_uart.log 5264 lignes ; marks.txt).
  Capture avortée traces/20261107-035422_c3-touchid (login trop tôt, marque `abort_protocole_casse`) : notée, **non analysée**.
- Fait : nouveau script `analysis/lock_cycles.py` (états `LOCKED/UNLOCKED now=` de hv_uart + découpage des tentatives SBIO
  `0x23…0x21`) → `analysis/out/c3_lock_cycles.txt` ; `align_uart.py` → `analysis/out/c3_align.txt` ; rapport
  `analysis/out/c3_report.md` ; section C3 ajoutée dans `docs/messages.md`. Aucune action hardware.
- Vu :
  - Marques décalées : 11 LOCKED / 11 UNLOCKED dans hv_uart (uart L2089…L5233) pour 6 `lock_*` marqués ; plusieurs actions
    avant leur marque (LOCKED 616 vs `lock1` 596 ; unlock doigt 937-938 avant `fp_good_3`). Décalage Mac/PC < ~2 s
    (ancrages CRC uart L3397 ↔ L2158, L2778 ↔ L727). Aucun événement « buttonIndex » (Ctrl+Cmd+Q).
  - Chaque LOCKED (10/10) : `< 0x01/0x09 P2 0x1f5` puis `2b 2b 7d 2b` ; 30 s de lock sans doigt (616-646) : aucun 0x23.
  - Séquence `23 06 65 07 09 … 1f 22 0b 70 <03 21` identique bit à bit 8 fois (L2147…L4966), = C1 L1109, chaque fois avant
    un UNLOCKED. 12 tentatives sans UNLOCKED : pas de `<01/08`, pas de `0b`, 0x09 296-356 ms (vs 240-245). 2 abandons `23 06 65 07 22`.
  - Le 5e échec consécutif (cycle 1100) porte `<01/45` ×3 ; puis déverrouillage au mot de passe (L5723-5760, avec un `<01/08`).
  - fp_bad_1 a déverrouillé (L4966, UNLOCKED now=1097, uart L4942).
  - fp_prelogin et fp_noprompt : 0 message SBIO. SKS TAG 0x84/0x86 : PARAM 0xfd → 0x00 au login (L688 → L697), comme C1 et C2a.
  - Rafale `6b 79 6c 37 33 36 6c 37` ~15 s après chaque unlock doigt (5/5).
- Interprété (hypothèses) : `<01/09` + `2b…` = armement au lock ; 0x09 = comparaison, `<01/08` = correspondance ; le verdict
  succès/échec est visible dans le mailbox (pas seulement dans l'OOL) ; `<01/45` = blocage après 5 échecs (1 seul cycle).
  Quel doigt a produit les échecs : inconnu (marques peu fiables). Rien en `vérifié`.
- Incidents : aucun.

## 2026-11-07 03:50 — analyste — Analyse de C1 (boot + login mdp + lock + unlock doigt)
- Trace : traces/20261107-033436_c1-boot/ (sep.log 1865 msgs tous EP, hv_uart.log 3045 lignes, lecture seule)
- Fait : stats `analysis/parse_trace.py` ; nouveaux scripts `analysis/sbio_transactions.py` (paires 0xfc, fragments,
  rafales) et `analysis/align_uart.py` (ancrages sep.log ↔ hv_uart.log par TAG xART, CRC, handle SKS ; epochs macOS).
  Mise à jour de `docs/messages.md` ; chronologie et candidats dans `analysis/out/c1_report.md`.
- Vu :
  - 12 noms 0xFD = les 12 EP de la doc Asahi. CNTL `TYPE 4/2/5/3 PARAM=ep` pour 9 EP, même ordre que « SEP EP n enabled » (uart) ;
    DATA de T2/T3 suit exactement « + taille/0x1000 + 4 » sur les 9.
  - 36/36 « Replied to xART app » ↔ `> EP=0x13` par TAG (22 identiques bit à bit) ; 5/5 handles SKS du noyau ↔
    `< EP=0x12 TAG=0x00 DATA=handle` (L550, 639, 641, 697/1124, 1624).
  - Epochs macOS dans hv_uart : UNLOCKED `now=1794018972` (uart L2661, login), LOCKED `now=1794019015` (L2748),
    UNLOCKED `now=1794019020` (L2806, `lastDuration=5`). Lignes noyau sans horodatage.
  - SBIO : 100 % des messages 0xfc ont PARAM=0 DATA=0 ; 0x23/0x06/0x65/0x07/0x09/0x22/0x21 seulement à L1109-1145
    (03:36:59.9–03:37:00.4), encadrés par les ancrages xART L1122/L1140 entre LOCKED et UNLOCKED ; L1224-1247 (03:37:15) est
    ancré **après** UNLOCKED.
  - uart L2736-2739 : un seul événement « SMC HID buttonIndex=6 » press/release, juste avant le lock.
- Interprété (hypothèses) : login mdp ≈ SKS L632-642 (03:36:09–12) ; unlock doigt ≈ SBIO L1109-1145, 0x09 = candidat
  « match » ; la rafale de 03:37:15 est post-unlock (contredit l'alignement A de HC). Lock non isolé (écran verrouillé 5 s
  seulement ; lock probablement fait en appuyant sur la touche Touch ID). Rien en `vérifié`.
- Incidents : aucun (pas d'accès hardware). Un `sed` en lecture sur traces/ a été refusé par une règle ; refait en Python.

## 2026-11-07 ~03:50 — tracer — Repères (mark.sh), affichage direct, --between, étude OOL
- Trace : traces/20261107-033436_c1-boot/sep.log (lecture seule, pour l'étude) ; aucune capture lancée.
- Fait (aucune action hardware ; capture C2a de l'orchestrateur en cours pendant ce travail) :
  - `tools/boot_and_trace.sh.new` (PAS installé : le script tourne, bash le lit au fil de l'eau ; `mv` à faire
    par l'orchestrateur après la capture) : un seul `trap cleanup EXIT` (les deux traps précédents s'écrasaient) ;
    écrit `$REPO_ROOT/.current_capture` (ligne 1 dossier, ligne 2 PID du script), effacé en fin de capture s'il
    désigne encore cette capture ; mode AUTO : affichage direct `tail --pid=$$ -F sep.log | gawk` filtré par
    `LIVE_EPS` (défaut 0x08, `all`, `none`), validé avant tout accès au Mac ; `live_eps:` et `marks:` dans meta.txt.
  - `tools/mark.sh <étiquette>` : `date +%s.%6N` (CLOCK_REALTIME du PC = horloge du `time.time()` du tracer)
    → `marks.txt` du dossier en cours ; refuse sans capture, PID mort, dossier hors traces/, étiquette hors
    `[A-Za-z0-9._:-]+`. Ne source pas env.sh (aucun accès aux ports).
  - `.gitignore` : `.current_capture`.
  - `analysis/parse_trace.py --between E1 E2` : fenêtre [1re E1, 1re E2 après E1], bornes incluses, d'après
    marks.txt du dossier ; erreur rc=2 si marks.txt ou étiquette absents. Fixture synthétique
    `analysis/tests/fake_marks/`, 4 tests ajoutés : 15/15 OK.
- Vérifs : `bash -n` (boot_and_trace.sh.new, mark.sh), `py_compile`, tests unitaires ; pipeline tail/gawk testé
  sur un fichier factice du scratchpad (pas de tail/gawk orphelin après la sortie du script) ; mark.sh testé dans
  un faux repo du scratchpad (accepte / refuse les 5 cas). Pas testé sur une vraie capture.
- Vu (c1-boot, lecture) : `EP=0xfe TYPE=0x1c DATA=0x00000580` (L13) après `EP=0xff TYPE=0x06 DATA=0x4` (L12) ;
  m1n1 envoie SET_SHMEM = EP 0xFE TYPE **0x18** DATA=IOVA>>12 (`m1n1/proxyclient/m1n1/hw/sep.py:118-123`).
  EP 0xFD TYPE 1 : DATA 0x01010101 (0x08, 0x0a, 0x0c, 0x0e, 0x14, 0x17), 0x02020202 (0x10, 0x13, 0x18),
  0x02020404 (0x15), 0x02010201 (0x12), 0x00000000 (0x00).
- Interprété (hypothèses, rien de vérifié) : 0xFE/0x1c pourrait être l'équivalent 13.5 de SET_SHMEM (IOVA 0x580000
  si même décalage) ; les octets de DATA (0xFD/1) pourraient être des tailles/compteurs OOL par EP. m1n1 ne décode
  pas 0xFD TYPE 1 (`hw/sep.py:151-159` ne traite que TYPE 0) ; aucune source locale ne parle d'OOL.
- Incidents : deux commandes de test refusées par le système de permissions (création de mark.sh via heredoc ;
  test avec `rm -rf`/`sleep &`) ; refaites avec Write et des commandes plus simples.

## 2026-11-07 ~03:23 — Albert / Claude — 2e essai H2 réussi (client connecté)
- Trace : traces/20261107_h2-notrace-2/ (console.log 44 343 o ; hv_uart.log ~229 Ko, 3210 lignes à 03:25, boot complet)
- Fait : arrêt complet du Mac, démarrage à froid sur m1n1, chainload OK, run_guest.py sans tracer.
- Vu : PID run_guest.py vivant à 03:25:36, plus de déconnexion USB ; Albert : macOS tourne, lock / unlock Touch ID OK.
  Repérage rapide dans hv_uart.log (grep, comptes après masquage des nombres) : lignes `AppleSEPBooter ... SEP status: 2`,
  `AppleSEPXART (EP: 19) received unknown SEP request op 29` (×5), `AppleSEPXART ... Fetched SEP-xART Locker / USER-xART Locker`,
  `AppleBiometricSensor: loaded patch vers=22`, nombreux `AppleSEPKeyStore ... operation failed (sel: 7|17|23|75 ...)`.
- Interprété (hypothèses) : EP 19 = 0x13 (xART), cohérent avec la doc Asahi. Le chainload bloqué de 03:13 serait dû au
  redémarrage à chaud (le démarrage à froid a marché) — une seule observation, pas vérifié.
- Incidents : aucun pendant cet essai.

## 2026-11-07 ~03:13 — Albert / Claude — 3e essai : chainload bloqué au « Reloading into stub »
- Trace : — (sortie collée par Albert, non sauvegardée dans traces/)
- Vu : m1n1 réapparu en USB à 03:13:02 (1-1, ttyACM0/1), après une disparition à 03:09:54 (cause inconnue).
  chainload.py : copie SEPFW/preoslog/TrustCache, chargement, « Reloading into stub at 0x10010a90240 », puis
  `UartTimeout` sur la réponse à P_VECTOR. **Pas de déconnexion USB ensuite** (contrairement au 1er essai réussi,
  où le reload provoquait disconnect + reconnexion).
  Différences avec le boot de 02:52 dans la sortie du m1n1 installé : `Unknown payload at 0x100050b8000 (magic: 4d697373)`
  au lieu de `No more payloads`, et `pmgr: Enabling 0.ANS2 / 0.DEBUG` en plus. Sens inconnu.
- Interprété : aucune explication vérifiée. Ce boot venait d'un redémarrage à chaud après macOS-sous-HV ; un démarrage
  à froid est le premier test à faire.

## 2026-11-07 ~03:06 — Albert / Claude — 2e essai H2 avorté : mauvais port série
- Trace : — (rien capturé)
- Vu : un téléphone Samsung (CDC-ACM, branché 03:04:19) a pris /dev/ttyACM0 ; m1n1 est passé en ttyACM1 (if00, proxy)
  / ttyACM2 (if02, UART HV). chainload.py a parlé au modem du téléphone (réponses `+CME Error` / `OK`) → UartTimeout.
  Rien n'a été envoyé au Mac.
- Fait : `tools/env.sh` résout désormais les ports par `/dev/serial/by-id/usb-Asahi_Linux_m1n1_uartproxy_*-if00|if02`
  (fonction `refresh_ports`, rappelée par `require_mac`, donc après le chainload) ; ports notés dans meta.txt.

## 2026-11-07 ~02:53 — Albert (lancé) / Claude (lecture) — Premier essai H2, sans tracer
- Trace : traces/20261107_h2-notrace/ (console.log 46 237 o, hv_uart.log 6 497 o, 78 lignes)
- Fait : chainload.py -r m1n1.bin (OK, « Proxy is alive again »), puis run_guest.py macos/kernel.macho sans -m,
  bootargs de la doc. UART HV lu avec `sudo cat > hv_uart.log`, relancé une fois (le 2e `>` a écrasé le 1er : début du boot perdu).
- Vu :
  - console.log : kernel chargé (fileset OK), SEPFW copié, 10 CPU démarrés côté invité, puis `run_guest.py` meurt dans
    `hv_start` : `SerialException: device reports readiness to read but returned no data`.
  - Log noyau du PC : `usb 1-1: USB disconnect` à 02:53:24, ré-énumération 1209:316d (m1n1) à 02:53:25.
  - hv_uart.log continue à se remplir jusqu'à ~02:56 : logs macOS en espace utilisateur (triald, siri embeddedspeech,
    nearbyd, écriture nvram battery-health) et `AppleSEPKeyStore ... operation failed (sel: 7 ret: e00002c2 ...)`,
    `unexpected session: 100031 uid: -1`, une fois `sel: 75 ret: e00002ce`.
- Interprété (hypothèses) : macOS a continué à tourner sous l'hyperviseur après la perte du client Python ;
  le SEP répond aux requêtes keystore (erreurs probablement liées à l'absence de session utilisateur). À confirmer.
  Cause de la déconnexion USB : inconnue.
- H2 : Albert rapporte « le mac est lent mais le Touch ID fonctionne encore » → H2 confirmée une fois (observation humaine, voir hypotheses.md). Détails : écran verrouillé, 3 essais bon doigt OK, essais mauvais doigt faits (résultat non noté).
- Incidents : client proxy perdu ; aucun panic vu dans les 78 lignes conservées.

## 2026-11-07 — Claude (session principale) — Reprise du travail sur m1n1, kernel, commande H2
- Trace : —
- Décision (Albert) : on continue à travailler sur le clone m1n1 malgré `m1n1/CLAUDE.md` (licence MIT/GPLv2,
  usage privé, rien ne sort du repo). Les tâches suspendues plus bas sont reprises.
- Vu (code m1n1 70757dc7) :
  - `run_guest.py` charge la charge utile avec `hv.load_macho()` ; `m1n1/macho.py` gère les filesets (LC_FILESET_ENTRY), pas l'IMG4.
  - `macos/kernel.macho` parsé hors ligne par `m1n1.macho.MachO` : entry 0xfffffe00083f0540, 357 entrées fileset.
  - Doc Asahi m1n1-hypervisor : extraction img4tool en 2 étapes (équivalente à pyimg4), bootargs identiques à `MACOS_BOOTARGS`.
  - `asn1` est importé en tête de `m1n1/hv/__init__.py` → indispensable pour `run_guest.py`.
  - `chainload.py` préserve le SEPFW par défaut (`-n` pour ne pas le faire) : copie du blob + mise à jour de l'adresse dans l'ADT (`src/chainload.c`).
  - J'ai confirmé qu'aucun `SEPTracer` n'existe (`git log --all -S SEPTracer` ne renvoie rien), ce qui recoupe l'entrée du tracer.
- Fait : `tools/env.sh` → `M1N1_PYTHON` (venv `~/.venvs/m1n1` si présent, sinon python3), utilisé par `tools/*.sh` ;
  `boot_and_trace.sh` exporte `SEP_TRACE_OUT=$OUT/sep.log` et note `sep_eps`/`sep_lines` dans meta.txt ;
  `parse_trace.py` lit `<dossier>/sep.log` en priorité. Commande H2 manuelle écrite dans `docs/hypotheses.md`.
- Non vérifié : tout ce qui demande le Mac (chargement réel du kernel, tracer, H2).
- Incidents : aucun (aucune action hardware).

## 2026-11-07 — tracer — Localisation du « tracer SEP » m1n1, écriture de hv/trace_sep_filtered.py
- Trace : — (aucune action hardware, lecture de code + py_compile uniquement)
- Fait :
  - Recherche `SEPTracer` / `sep` dans `m1n1/proxyclient` (trace/, hv/, fw/, hw/) et dans tout l'historique
    git (`git log --all -S SEPTracer`, 2928 commits, clone non shallow, toutes branches distantes) :
    **aucun `SEPTracer` n'existe dans m1n1 public**, ni maintenant ni dans l'historique. Pas de `hv/trace_sep.py`.
    Seule mention : `proxyclient/hv/trace_mesa.py:5` (« sven's old SEP tracer »), code non publié dans le dépôt.
  - Ce qui existe côté SEP :
    - `proxyclient/m1n1/hw/sep.py` : `SEPMessage` (Register64 : EP 7:0, TAG 15:8, TYPE 23:16, PARAM 31:24,
      DATA 63:32 = doc Asahi), `SEP` (boot de SEPOS *par m1n1* : messages ROM EP 0xFF/0xFE, `BootRomMsg`,
      `BootRomStatus` ; découverte des noms d'endpoints EP 0xFD TYPE 0 → PARAM = n° d'EP, DATA = 4 caractères).
      Ce n'est pas un traceur : il écrit dans le mailbox (INBOX0 puis INBOX1=0). Hors périmètre pour nous.
    - `src/sep.c` : `sep_get_random` (EP 0xFF, cmd 16 → réponse 116), via `asc_init("/arm-io/sep")`.
    - `proxyclient/hv/trace_dart.py` : trace `/arm-io/dart-sep` (DARTTracer, verbose=3) parmi d'autres DART.
  - Le traceur générique applicable au SEP est `proxyclient/m1n1/trace/asc.py` :
    `BaseASCTracer(ADTDevTracer)` (l.100), `DEFAULT_MODE = TraceMode.SYNC`, regmap `ASCRegs` sur reg[0]
    (`hw/asc.py` : INBOX0 +0x8800, INBOX1 +0x8808, OUTBOX0 +0x8830, OUTBOX1 +0x8838, CTRL +0x8110/+0x8114).
    Hooks `w_INBOX1` (l.117, TX) et `r_OUTBOX1` (l.124, RX) → `handle_msg` (l.134) qui route par
    `r1.EP` = bits 7:0 **du mot 1**. `ASCTracer` (l.264) n'a que EP 0 Management et EP 2 Syslog.
  - Activation : pas de `-m` dédié. Il faudrait un script `run_guest.py -m` qui fait
    `ASCTracer(hv, "/arm-io/sep", verbose=N).start()` (modèle : `hv/trace_smc.py`, `hv/trace_aop.py`), ou
    `hv/trace_all.py` (trace tout `/arm-io` en ASYNC via PrintTracer, SEP compris).
    `run_guest.py` exécute chaque `-m` par `hv.run_script()` = `runpy.run_path(init_globals=hv.shell_locals)` :
    globales `hv, iface, p, u, trace, TraceMode` + toutes les méthodes de `hv` (`trace_range`, `trace_device`…).
  - `hv/trace_sep_filtered.py` écrit (repo projet, rien modifié dans m1n1, aucun commit m1n1) :
    sous-classe `ADTDevTracer`, ne trace que INBOX0/1 (écritures) et OUTBOX0/1 (lectures) de `/arm-io/sep`
    reg[0] (sous-pages de 0x10 octets, granularité 4 octets supportée par `src/hv/hv_vm.c`), mode ASYNC par
    défaut (`SEP_TRACE_MODE=SYNC` possible). Décode le mot 0 selon la doc Asahi, filtre `SEP_EPS`, écrit une
    ligne par message dans `SEP_TRACE_OUT` (défaut `traces/sep_<AAAAMMJJ-HHMMSS>.log`), flush toutes les
    0,5 s (`SEP_FLUSH_S`) + à la sortie, en-tête/fin en lignes `#`, un seul print console au démarrage.
    `ool=m1:0x…` = mot 1 brut, seulement si bits non nuls hors champs FIFO (40-56). Noms d'EP (0xFD/TYPE 0)
    recopiés en commentaire `# epname`, quel que soit le filtre. Aucune écriture, aucun HOOK, aucune injection.
  - `tools/reboot_mac.sh` : API vérifiée, correcte (voir Vu), seul le commentaire TODO remplacé.
- Vu (lecture de code) :
  - **Le traceur ASC générique décode mal le SEP** : le SEP porte l'endpoint dans le mot 0 (bits 7:0,
    `hw/sep.py`, `src/sep.c`) et m1n1 écrit INBOX1=0 → `handle_msg` routerait tout vers EP 0 et le décoderait
    comme `ManagementMessage` (TYPE = bits 59:52 du mot 0, `fw/asc/mgmt.py`), donc TYPE faux.
  - Sources du spam (si on applique `ASCTracer`/`trace_all` au SEP) : mode SYNC = chaque accès tracé
    remonte en Python par USB ; à `verbose>=2` deux lignes par message (`SEND:/RECV:` + ligne EP) ; à
    `verbose==2` chaque registre sans handler (polls de `INBOX_CTRL`/`OUTBOX_CTRL`, OUTBOX0…) est loggé ; à
    `verbose>=3` chaque accès MMIO ; `w_OUTBOX_CTRL`/`w_INBOX_CTRL`/`w_CPU_CONTROL` loggent toujours. Tout
    passe par `hv.log()` = `print()` console (+ fichier `-l`). `trace_all.py` loggue chaque accès MMIO du bloc.
  - Version macOS : aucun code SEP de m1n1 ne dépend d'une version de macOS (ni Big Sur ni Monterey
    mentionnés). Rien à « mettre à jour pour 13.5 » identifiable. Je ne sais pas si 13.5 change l'usage du mot 1
    ou l'ordre des accès.
  - API reboot : `m1n1/setup.py` (pas de `__all__`) définit `iface, p = M1N1Proxy(...), u, mon, hv` et
    reset le panic counter ; `M1N1Proxy.reboot()` (`proxy.py:834`) = `request(P_REBOOT=0x010, no_reply=True)`,
    traité par `src/proxy.c` → `reboot()`. `proxyclient/tools/reboot.py` fait exactement la même chose.
  - `m1n1/macho.py` gère `FILESET_ENTRY` (`load_fileset`) : `hv.load_macho` lit a priori un Mach-O fileset
    (répond en partie au « non vérifié » de la session 1 ; non testé).
- Interprété : le « tracer SEP actuel qui spamme » du CLAUDE.md n'est pas un fichier de m1n1 public ; c'est
  vraisemblablement l'`ASCTracer` générique (ou `trace_all.py`) appliqué à `/arm-io/sep` — hypothèse.
- Non testé (aucun accès Mac) : tout le comportement à l'exécution de `trace_sep_filtered.py` ; ordre
  INBOX0→INBOX1 / OUTBOX0→OUTBOX1 sous macOS 13.5 ; accès 64 bits (des accès 32 bits casseraient le décodage) ;
  `/arm-io/sep` reg[0] = base ASC sur j314c ; pertes d'événements en ASYNC sous charge ; contenu réel du
  mot 1 ; timestamp = heure PC de traitement, pas l'horloge du Mac. À noter : `boot_and_trace.sh` n'exporte pas
  `SEP_TRACE_OUT` → la sortie va dans `traces/sep_<stamp>.log`, hors du dossier de capture (suggestion :
  `export SEP_TRACE_OUT="$OUT/sep.log"` avant l'étape 3, à décider par Albert).
- Incidents : aucun.

## 2026-11-07 — Claude (session principale) — Session 1 : outillage hors hardware
- Trace : —
- Fait :
  - Clone `https://github.com/AsahiLinux/m1n1` (--recursive) dans `m1n1/`, branche `sep-touchid` créée
    sur le commit `70757dc7` (« kboot: fix M2 dcpext handling »). Submodule artwork : `80d14f8b`.
  - `./tools/build_m1n1.sh` : OK, `m1n1/build/m1n1.bin` = 5 046 272 octets. Le build compile `rust/`
    (cargo) même sans `CHAINLOADING=1`.
  - Dépendances proxyclient lues dans `m1n1/requirements.ini` : pyserial, construct, asn1.
    `asn1` absent du PC et des dépôts officiels Arch. SETUP-ARCH.md corrigé.
  - `albert` n'est pas dans le groupe `uucp` (sortie de `groups`).
  - Kernel : `macos/kernelcache` = IMG4 (IM4P `krnl`, `KernelManagement_host-354.140.3`, payload LZFSE `bvx2`).
    Extraction avec pyimg4 0.8.9 (venv jetable) : `img4 extract -p` puis `im4p extract`
    → `macos/kernel.macho` : Mach-O 64-bit arm64e, filetype=12 (MH_FILESET), 96 763 904 octets.
    sha256 kernelcache `8c62bae3…0c92`, kernel.macho `35695639…78a3`.
  - Agent analyste : `analysis/parse_trace.py` (`parse_file()` réutilisable, stats par EP/dir/type/param avec lignes sources, lignes invalides comptées), `analysis/diff_traces.py` (ensembles + `--seq` via difflib, TAG/DATA ignorés). Tests synthétiques dans `analysis/tests/` : 11/11 OK (relancés par la session principale). Pas encore testés sur une vraie capture.
- Vu : **les fichiers `m1n1/CLAUDE.md`, `m1n1/AGENTS.md`, `m1n1/GEMINI.md` déclarent que les mainteneurs
  de m1n1 interdisent tout usage d'outils IA/LLM sur le projet (« for legal reasons »)** et renvoient vers
  https://asahilinux.org/slop/. Ça dépasse le « ne rien soumettre à Asahi » du README.
- Décision : arrêt de tout travail d'agent qui lit en détail ou modifie le code m1n1 (tâche 3 : SEPTracer,
  `hv/trace_sep_filtered.py`, API de reboot ; tâche 2 : format attendu par `run_guest.py`),
  en attendant la décision d'Albert. Le clone et le build étaient déjà faits.
- Non vérifié : `run_guest.py` accepte-t-il le Mach-O fileset, ou le kernelcache brut ? Non lu.
- Incidents : aucun (aucune action hardware).

## 2026-11-07 — Albert — État du Mac avant la session 1 (rapporté par Albert)
- Trace : —
- macOS 13.5 installé sur le volume `macos13.5` (groupe de volumes EFF3C698-A740-4F41-AB86-99C85C0EB880), Touch ID enrôlé.
- `bputil -nkcas` + `csrutil disable` : `bputil -d` affiche « Security Mode: Permissive » (coih absent).
  Le déverrouillage Touch ID fonctionne dans ce mode (boot natif de macOS) → H1 réfutée.
- m1n1 compilé sur Asahi (`make ARCH=`) et installé par `kmutil` sur macos13.5 : démarre en mode proxy
  (« Running proxy... »). Le Mac s'identifie comme `apple,j314c`.
- Kernelcache 13.5 copié dans `macos/kernelcache`.
- PC : aarch64-linux-gnu-gcc, python-pyserial, python-construct, imagemagick, dtc, tmux, rustup
  + cible aarch64-unknown-none-softfloat.

## 2026-11-06 — Albert — Démarrage du projet
- Phase 1 (traces seules) décidée. Passage en phase 2 (kexts) si le jalon 1 est prometteur.
- Hôte : PC Ryzen sous Arch. Cible : MacBook Pro 14" M1 Max.
- Contrainte : hyperviseur m1n1 = macOS 13.5 uniquement → volume macOS 13.5 dédié au tracing.
