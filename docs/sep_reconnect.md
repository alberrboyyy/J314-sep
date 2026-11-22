# Se reconnecter à un SEP déjà démarré ? (analyse 2026-11-23)

Question : entre deux essais, peut-on éviter le power-cycle physique, soit en reprenant un SEPOS déjà Running
(xART servi, sbio ouvert), soit autrement ? Analyse hors matériel : code, logs, traces, `journalctl` en lecture seule.
**Rien n'a été lancé** : pas d'insmod, pas de sudo, aucune écriture SEP.

Légende : **VU** = lu dans du code ou un log, avec la référence ; **DÉDUIT** = raisonnement à partir du VU, non testé ;
**INCONNU** = pas de donnée.

---

## 0. Résultat principal : le reboot logiciel de Linux suffit déjà (VU, n=6)

Le power-cycle n'est pas nécessaire **entre deux runs sous Linux natif**. Un `reboot` systemd normal remet le SEP en
mode ROM. Lu dans `journalctl --list-boots` et `journalctl -b N`, sur ALARM, en lecture seule. Chaque boot est relié à
son run par l'adresse `sepfw phys`, qui change d'un boot à l'autre et qu'on retrouve dans `logs/*/kernel.log` :

| Boot | Run (logs/) | SEP touché par sep_native | Fin du boot (journal) | Boot suivant : GET_STATUS #1 |
|---|---|---|---|---|
| -17 | J2 (`sepfw 0x1000550c000`) | SEPOS Running | `System is rebooting` 18:35:48 | -16 (J4) : DATA 0x1, boot OK |
| -16 | J4 `20261122-183847` | xART servi, 12 SAVE acquittés | `System is rebooting` 18:52:18 | -15 (J3) : DATA 0x1, boot OK |
| -15 | J3 `20261122-185633` | xART servi, **Halted** (CNTL 0x08 sans ack) | reboot.target 19:02:28 | -14 (J3b) : DATA 0x1, boot OK |
| -14 | J3b `20261122-190438` | **Halted** | reboot.target 19:17:38 | -13 (J3c) : DATA 0x1, boot OK |
| -13 | J3c `20261122-192013` | sbio ouvert, 0x73 VIVANT | `System is rebooting` 19:54:43 | -12 (J3d) : DATA 0x1, boot OK |
| -3 | J7b n=2 `20261123-001026` | sbio VIVANT, skdl/sks/scrd ouverts | reboot.target 00:20:56 | -2 (pas de sep_native) puis reboot → -1 (J7c) : DATA 0x1, boot OK |

- Les boots -12 à -4 et -1 se terminent par `macsmc-input: Triggering forced shutdown!` (appui long sur le bouton,
  c.-à-d. le power-cycle). C'est cohérent avec le mot « power-cycle » du journal à partir de J5.
- **Correction du journal** : l'entrée J7c (2026-11-23 00:29) dit « power-cycle ». En fait le boot -2 s'est terminé
  par un reboot logiciel (`reboot.target`, `Unmounted /home`), puis J7c a tourné au boot -1. Le SEP de J7b a donc été
  remis à zéro par deux reboots logiciels, sans power-cycle.
- Chemin du reboot sous Linux (VU, code) : `macsmc-reboot` déclare le restart SMC `MBSE = 'phra'` avec
  `SYS_OFF_PRIO_HIGH` (`drivers/power/reset/macsmc-reboot.c:112-122, 261-268`). `apple_wdt` n'a que la priorité 128
  (`drivers/watchdog/apple_wdt.c:193`). Sous m1n1, `reboot` passe par `hvc` ou `wdt_reboot` (`m1n1/src/start.S:241-253`,
  `src/wdt.c:51-59`). Ce sont deux chemins différents.
- DÉDUIT : le piège « le reboot logiciel fige le PMU/SPMI » (`handoff.md:122`, `:314-318` ; journal 2026-11-12)
  concerne le **reboot via le proxy m1n1** (watchdog), puis `linux.py` qui bloque au `PMU.reset_panic_counter`.
  Il ne concerne **pas** le reboot SMC de Linux. Sur les 6 reboots Linux ci-dessus, aucun gel PMU n'a été vu.
  `macsmc-reboot` relit et remet à zéro les compteurs PMU à chaque boot (`macsmc-reboot.c:170-198`), et ces lectures
  ont réussi (ex. boot -16 : « PMU logged 1 boot error(s) »).
- **Non couvert** (INCONNU) : un reboot logiciel **après une init capteur** (J5 à J8 : sbiod, spi2, gpio capteur). Tous
  ces boots se sont terminés par un power-cycle. Le boot courant (0, J8) a encore `sep_native` chargé (`lsmod` :
  `sep_native 131072 1`).

---

## 1. Notre `sep_native.rs` au probe et au remove

### VU (code)
- Le probe refuse tout SEP « déjà touché » : `TOUCHED != 0` → EBUSY « power-cycle requis »
  (`driver/rust/kmod/sep_native.rs:2535-2537`) ; une seule instance à la fois (`BOUND`, `:2539`). Ces deux
  statiques sont au niveau du module (`:287-289`), donc remis à 0 uniquement par un nouveau chargement du module.
- Au premier envoi, `mark_touched()` prend une référence sur le module qui n'est jamais rendue (`:1963-1970`) :
  **rmmod → EBUSY** jusqu'au reboot. Il n'y a donc jamais de second insmod sur un SEP déjà démarré.
- Unbind sysfs après un envoi (`Drop`, `:2551-2564`) : fuite voulue de la mailbox (le callback IRQ reste actif, ce
  qui est sûr parce que le code du module ne peut plus être déchargé), de la shmem, des OOL et du mapping firmware
  s'il est encore mappé. Sans envoi : arrêt propre, `apple_mbox_stop` puis `flush_work` (`:2566-2575`).
- Tampons : la shmem 0x30000 et les OOL (0x13 : 2 × 0x8000 ; 0x08 : 2 × 0x4000 ; skdl/sks/scrd) sont des
  `dma::Coherent` alloués au probe (`:2402-2440`). Les IOVA sont choisies par l'allocateur iommu-dma : shmem
  `0xfffc0000` et firmware `0xff800000` dans J2 (journal 2026-11-22 17:58 et 18:06).
- Le firmware est démappé juste après 0x6A (`:2079`), comme m1n1 (`hw/sep.py:127`). En cas d'échec après IMG4,
  il reste mappé (`:2076`).
- État `Idle` (allow_boot=0) : tout mot reçu → Halted et journalisé (`:721`). Un probe à allow_boot=0 est donc un
  détecteur passif de mots en attente dans la boîte I2A.
- Boot : GET_STATUS doit répondre 0x66 avec DATA = 1, puis 2 après TZ0, sinon Halted (`:2038-2046`, constantes
  `:171-175`). Un SEPOS déjà Running qui ne répondrait pas, ou répondrait autre chose, → Halted, fail-closed.

### DÉDUIT : ce qui empêcherait un second insmod de reprendre
1. **Code du callback** : une vraie décharge exige d'arrêter la mailbox avant (`apple_mbox_stop` désactive l'IRQ,
   `drivers/soc/apple/mailbox.c:274-284`). Sinon, l'IRQ suivante saute dans du code libéré.
2. **Danger DMA** : SEPOS garde les IOVA de la shmem (SET_SHMEM) et de chaque OOL (CNTL 0x02/0x03). Libérer un
   `dma::Coherent` pendant que le SEP peut y écrire = corruption mémoire possible. C'est pour ça que le Drop actuel
   fuit au lieu de libérer. Une reprise devrait **garder** ces tampons et retrouver leurs IOVA et adresses CPU
   (mémoire réservée au DT, ou petit module ancre qui les détient).
3. **État logiciel perdu** : table de découverte (les annonces 0xFD ne viennent qu'au boot de SEPOS ; on ne connaît
   pas de demande de « ré-annonce »), état xART (TAG en cours, requête en attente), état GT/sbio (compteur fd/fc,
   phase du relais), état de sepd/sbiod.
4. **Messages pendant l'absence** : IRQ coupée, les mots SEP→AP s'accumulent dans la FIFO I2A. Au `apple_mbox_start`
   suivant, l'IRQ (niveau) repart et le poll les vide (`mailbox.c:185-215, 243-272`). Profondeur de la FIFO :
   INCONNUE. Comportement du SEP si la FIFO est pleine, ou si un SAVE xART reste sans réponse : INCONNU.
5. **Côté SEPOS** : accepte-t-il un second jeu de CNTL SET_OOL (0x02-0x05) sur un EP déjà ouvert ? Un second
   SECMODE 0x14 ? INCONNU (jamais vu dans nos traces, ni dans macOS ni chez nous).
6. **GET_STATUS sur un SEPOS Running** : INCONNU. Seul indice (hypothèse, journal 2026-11-18 soir, l. 302-308) :
   sous m1n1, après un run qui avait démarré le SEP, sans reset du SoC (chainload seulement), la séquence de boot
   publique est restée sans réponse (pas de `BOOT OK` en plus de 2 min). L'étape exacte qui bloquait n'est pas notée.
   `hw/sep.py` attend sans délai, donc ça veut dire qu'aucun mot n'est arrivé sur l'EP 0xFF.

---

## 2. Sources publiques présentes localement

Sources lues : `~/m1n1` (commit 70757dc7) et `~/kbuild/src/linux-asahi-7.2.12-3`.

### VU
- **linux-asahi `drivers/soc/apple/sep.rs`** : le probe envoie BOOT_TZ0 sans GET_STATUS (`:198-206, 359`). Il n'y a
  aucun chemin « SEP déjà démarré », aucun reset, aucune veille. `remove` (`:284-296`) : `set(None)` sur la mailbox,
  `dma_unmap_resource` du firmware avec l'adresse **physique** au lieu de l'IOVA (`:288-293`). La shmem est libérée
  au drop du `SepData`, alors que SEPOS la référence encore (DÉDUIT : risque DMA). Aucun message envoyé au SEP.
- **m1n1 `hw/sep.py`** : `boot()` = GET_STATUS → 0x66, TZ0 → 0x69 + 0xD2, GET_STATUS → 0x66, IMG4 + SET_SHMEM → 0x6A,
  unmap (`:104-127`). La valeur du statut n'est pas vérifiée (`expect_msg` ne teste que le TYPE, `:129-134`). Rien sur
  la reprise, la veille ou le reset.
- **m1n1 `src/sep.c`** : GETRAND seulement (EP 0xFF, type 16 → 116, `:14-17, 32-67`). Il est appelé par `kboot.c:108-115`
  pour `kaslr-seed`. m1n1 stage 2 parle donc au SEPROM avant Linux, et le SEPROM répond encore GET_STATUS = 1 ensuite
  (VU dans tous nos logs `GET_STATUS #1 DATA 0x1`).
- **m1n1 `src/asc.c`** : `asc_init` ne touche pas `CPU_CONTROL`, la ligne est commentée (`:55`). `sep_peek` lit
  `CPU_CONTROL` RUN = 0 alors que le SEPROM répond (journal 2026-11-09 21:05, l. 1262-1266) : ce registre ne dit pas
  si le SEP tourne.
- **Domaine d'alimentation** : `ps_sep` est `apple,always-on; /* Locked on */` (`arch/arm64/boot/dts/apple/t600x-pmgr.dtsi:1407-1414`).
  Linux ne peut pas couper le SEP par le PMGR. Le nœud expose bien `#reset-cells`, mais un reset PMGR du SEP n'est
  utilisé nulle part dans le code public (INCONNU s'il marche ; à ne pas essayer, voir §4).
- `docs/public_linux_state.md` §1 : rien de public sur un endpoint de veille ou `hibe` (0x14) ; Asahi n'a que s2idle
  (`docs/power_sep_options.md`).
- `hibe` est annoncé à chaque boot natif : `découverte : EP 0x14 = 'hibe'`, tailles `0x01010101`
  (ex. `logs/20261123-002956_j8-chained-sensor/kernel.log:27-28`). Aucun échange vu, ni chez nous ni sous macOS.

---

## 3. Veille et réveil sous macOS (traces + kext)

### VU (traces)
- Trois captures contiennent une mise en veille macOS : C6 `20261107-043828_c6-doigt-ool`, C13
  `20261108-163401_c13-ke1`, C14 `20261108-171039_c14-ke1`. Juste avant la veille, sur le fil :
  `> EP=0x00 TAG=0x08 TYPE=0x0c PARAM=0x02` (CNTL **SLEEP**, type 2), ack `< EP=0x00 TAG=0x08 TYPE=0x01` en 28 ms
  (C13 `sep.log:688-689`, C6 `sep.log:2723-2724`, C14 `sep.log:682-683`). Juste avant : un échange sur 0x15 (pnon).
- `hv_uart.log` C13 L2764-2801 : « SEP EP 21/23/18/24/10/12/8 disabled » (pnon, skdl, sks, stac, scrd, sse, sbio), puis
  `AppleCredentialManager: powerOffActionGated: SEPEndpoint disabled`, puis
  `AppleSEPManager::_setPowerState: power state 2 -> 0`, `IOPlatformQuiesceAction -> AppleSEPManager` (L2889),
  `pmu go hib (0x7)`. Même suite dans C6 (L3601-3726). Pour ces désactivations d'EP, on ne voit **aucun** mot CNTL sur
  le fil (DÉDUIT : côté AP seulement).
- **Aucun réveil capturé** : les trois captures s'arrêtent dans la veille (le Mac sous hyperviseur ne revient pas).
- Les captures C2b, C4 et C7 ont `TYPE=0x0c` sur les EP 0x12 et 0x0a : c'est un autre opcode propre à ces EP, pas le
  SLEEP du CNTL.

### VU (kext, `kext_sepmanager.md` §2-§3, source: kext, statut hypothèse)
- BOOT_IMG4 a une variante « resume » TYPE 0x08 (§2, ligne 5).
- Au réveil (sans firmware), le kext envoie un mot brut sur l'EP 0xFE avec l'offset de base de temps
  (`ml_get_abstime_offset`). Le réveil d'une sieste (« nap ») poste deux fois `0x0e0000` (EP 0, TYPE 0x0e) (§2).
- CNTL : 0x0c SLEEP (param = type), 0x11 SEP→AP « nap » → l'AP répond 0x12 NAP_OK, 0x13 NAP (§3).
- `_bootAction` traite les réponses ROM 0x65-0x6c, 0x82-0x89, 0xc7/0xc9/0xca, 0xd2, 0xff (§2). Le sens de 0x65,
  0x67, 0x68, 0x6b et 0x6c est INCONNU.

### DÉDUIT
macOS a un chemin « SEPOS reste en vie, l'AP le reprend » pour la veille : SLEEP type 2, puis au réveil un mot 0xFE
(et/ou BOOT_IMG4 « resume » TYPE 0x08). Ce chemin suppose que **la mémoire du SEP et de l'AP survit** (veille avec RAM
alimentée). Rien ne dit qu'il marche avec un AP **neuf** : nouveau noyau, nouvelles IOVA, tampons perdus. Rien non
plus sur une reprise après un rechargement du pilote. Ce que fait le réveil côté EP est INCONNU : re-SET_OOL ?
re-SECMODE ? nouvelles annonces 0xFD ?

---

## 4. Proposition graduée (rien n'est lancé)

**P0 — tout de suite, sans code : remplacer le power-cycle par `reboot` entre deux runs.** C'est déjà VU n=6 (§0),
y compris après Halted et après des SAVE acquittés. Le reboot demande root : Albert tape `! sudo reboot` (l'agent
n'utilise pas sudo). Le module reste fail-closed : si un jour GET_STATUS #1 ≠ 1, il passe en Halted
(`sep_native.rs:2039`), et le power-cycle redevient le filet. À mettre à jour : le texte « power-cycle requis » du
module (`:2536`) et des scripts `pending/j*.sh`, plus `CLAUDE.md` et `handoff.md` (« le reboot logiciel fige le PMU » →
« via le proxy m1n1 »). La ligne CLAUDE.md, c'est Albert qui la change.
- Seul trou : un reboot après une init capteur n'a jamais été fait. Expérience : après le J8 en cours (boot 0),
  `sudo reboot`, puis relancer `pending/j8_chained_sensor.sh` (script déjà éprouvé). Prédiction : GET_STATUS #1 =
  DATA 0x1, même déroulé que J8, 0 SAVE, « 2e passe terminée ». En cas d'écart (capteur dans un état anormal, Halted),
  on retombe sur le power-cycle. Ce n'est pas une classe neuve côté SEP : mêmes messages, après un reboot au lieu
  d'un power-cycle.

**P1 — plusieurs essais dans le même boot, sans recharger le module.** On garde `sep_native` chargé, et on refait
une **session sbio** en espace utilisateur. VU : macOS refait toute l'init capteur dans le même boot SEPOS
(`0x19 handleReset` puis 0x17 → 0x63 ; J5c pass2, journal 2026-11-22 22:11). Il faudrait :
`/dev/sep_sbio` ré-ouvrable après la fin d'un sbiod, et une porte `sbio_gate` qui accepte de repartir de 0x19 (ou de
0x17) quand la session précédente est close. Les paramètres d'expérience passent en ioctl au lieu de `insmod`. Coût :
un boot par série d'essais, pas par essai. Risque : script neuf, donc go d'Albert ; on ne sait pas ce que fait le SEP
si un sbiod meurt au milieu d'un échange (fail-closed : Halted, puis reboot). Ce n'est **pas** une reprise après
rmmod : l'état SEP reste servi par le même module.

**P2 — vraie reprise après rmmod (« handover »). Déconseillé tant que §5 n'a pas répondu.** Il faudrait tout à la
fois : (1) arrêter la mailbox avant la décharge ; (2) garder la shmem et les OOL vivants et mappés (mémoire réservée au
DT avec IOVA fixes, ou module ancre en C qui détient les tampons) ; (3) transmettre la table EP, les IOVA, l'état
xART et GT à l'instance suivante ; (4) qu'aucun SAVE xART n'arrive pendant le trou (FIFO, délai : INCONNUS) ; (5) que
SEPOS accepte un AP qui reprend sans re-boot. Gain par rapport à P0/P1 : faible. Risque : DMA sur de la mémoire
libérée si on se trompe une seule fois.

**P3 — au probe, détecter un SEPOS Running et sauter le boot IMG4.** Il faut un message qui réponde « je suis SEPOS »
sans effet de bord. GET_STATUS sur SEPOS : INCONNU, et l'indice du 2026-11-18 (silence) n'est pas encourageant. Un
essai serait une **écriture SEP de classe neuve** (go d'Albert), et un SEPOS qui panique sur un mot 0xFF inattendu
coûte de toute façon un reboot. Avec P0 en place, l'intérêt est faible. **Ne pas** essayer un reset PMGR de `ps_sep`
(domaine verrouillé par iBoot ; effet INCONNU ; on ne joue pas avec l'alimentation du SEP).

Ordre conseillé : P0 (et son seul trou, le reboot après capteur), puis P1 si le reboot entre essais devient le
goulot. P2 et P3 seulement si la mission kext (§5) montre un chemin de reprise documenté côté AppleSEPManager.

---

## 5. Mission de décompilation (session PC c9, `macos/kernel.macho` 13.5)

But : savoir si l'AP sait **reprendre** un SEPOS vivant, et avec quels mots. Protocole uniquement, `source: kext`.
On cherche d'abord les chaînes, puis on remonte aux fonctions.

1. **AppleSEPBooter : boot à froid ou reprise.** `bootSEP`, `_bootAction` et les fonctions qui les appellent. Quelles
   valeurs de GET_STATUS (DATA de 0x66) sont acceptées, et qu'est-ce qui est fait pour chacune (1, 2, autres :
   « SEPOS déjà lancé » ?). Sens de 0x65, 0x67, 0x68, 0x6b, 0x6c et 0xd2. Quand le kext prend-il BOOT_IMG4 TYPE 0x08
   (« resume ») au lieu de 0x06 ? Format exact du mot brut 0xFE au réveil (`ml_get_abstime_offset`) et réponse attendue.
2. **AppleSEPManager : gestion d'énergie.** `_setPowerState` (chaîne VU « power state 2 -> 0 »), le gestionnaire
   `IOPlatformQuiesceAction` / `callPlatformFunction`, les `powerStateWillChangeTo` / `DidChangeTo` éventuels. Ordre
   des mots envoyés au coucher et au réveil. D'où vient SLEEP 0x0c PARAM 2 (quelles valeurs de PARAM : veille,
   hibernation, extinction, redémarrage ?). **Le kext envoie-t-il quelque chose au SEP à l'extinction ou au
   redémarrage ?**
3. **AppleSEPControl.** Les `cmsg*` SLEEP (0x0c), NAP (0x13), NAP_OK (0x12), le traitement du 0x11 SEP→AP dans
   `_cmsgAction`. Y a-t-il un opcode CNTL « reset », « re-sync » ou « re-annonce des EP » ? À vérifier aussi :
   ERASE_INSTALL 0x25, SELF_TEST 0x18.
4. **AppleSEPEndpoint / AppleSEPDiscovery après réveil.** La chaîne « SEP EP %d disabled » : qui l'émet, quelle
   fonction réactive un EP (« enabled » ?). Au réveil, le kext renvoie-t-il SET_OOL 0x02-0x05 et SECMODE 0x14, ou les
   tampons restent-ils valides ? La table de découverte est-elle gardée ou ré-annoncée par SEPOS ?
5. **AppleSEPXART au réveil** (`_handle_sep_driven_msg`) : y a-t-il de nouveaux FETCH/SAVE après un réveil ?
6. **`hibe` (EP 0x14).** Quel client ouvre le nub `sep-endpoint,hibe` (HibernationService ? IOHibernate dans le
   kernel ? chaîne « hib state ») ; opcodes et contenu des OOL.
7. **Chaînes à chercher** dans les kexts SEP : `already`, `alive`, `booted`, `resume`, `wake`, `nap`, `sleep`,
   `quiesce`, `hibernat`, `restart`, `reset`, `reinit`, `re-init`, `reconnect`.

Format de rendu attendu : pour chaque point, le mot mailbox (EP/TAG/TYPE/PARAM/DATA), la condition d'envoi et la
réponse attendue, avec l'adresse de la fonction. « Pas trouvé » est une réponse valable.

---

## 6. INCONNU (récapitulatif)
- Réponse (ou non-réponse) de SEPOS à GET_STATUS 0xFF/0x02.
- Acceptation par SEPOS d'un nouveau SET_OOL ou SECMODE sur un EP déjà ouvert ; existence d'une ré-annonce 0xFD.
- Profondeur de la FIFO I2A et comportement du SEP quand elle est pleine.
- Reboot logiciel Linux après une init capteur (sbiod) : jamais fait.
- Le réveil macOS (aucune trace) ; protocole de `hibe`.
- Effet d'un reset PMGR de `ps_sep` (à ne pas essayer).
