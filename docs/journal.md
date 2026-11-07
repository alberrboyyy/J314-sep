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
