> # 🟠 MAC RÉCUPÉRÉ (ALARM) — CÔTÉ APPLE TOUJOURS CASSÉ (2026-11-12)
> Les essais voie C (rejeu SEP) ont bousculé l'état de la puce : côté Apple tout bootloope (macOS,
> recovery, menu Startup Options) ; seul m1n1 démarre. **Mais ALARM (le Linux d'Albert) est RÉCUPÉRÉ
> et bootable** par tethered boot depuis le PC (`tools/tethered_boot.sh alarm`). Données + ALARM
> intactes, backup OK, **Mac non brické**. Réparer le côté Apple = DFU Restore (plus tard, 2e Mac).
> Mémoire : [[mac-boot-casse-recuperation]]. **Aucune réécriture SEP sans l'accord d'Albert** (il lance).

Tu reprends le projet sep-touchid dans ~/Desktop/sep-touchid : Touch ID sous Linux sur MacBook Pro 14" M1 Max (j314c). Lis d'abord CLAUDE.md (PHASE 2, seul Albert change cette ligne ; lis surtout « Qui décide quoi » et « Exception : 2e Linux de test »), puis la mémoire du projet, puis le haut de docs/journal.md (entrées du 2026-11-09 au 12).

## POINT DE REPRISE 2026-11-12 (Opus 4.8) — Mac récupéré en ALARM ; prochain pas SEP = essai observationnel (relais du dernier SAVE)

**ÉTAT MATÉRIEL à la reprise (différent des sections plus bas : plus de tunnel relais) :**
- Mac en **USB LOCAL direct** (Albert est devant, pas de relais TCP). Proxy m1n1 v2.0.0-92-g7075,
  `/dev/serial/by-id/usb-Asahi_Linux_m1n1_uartproxy_v2.0.0-92-g7075_WHFWP7FYXF-if00` → ttyACM0 (console if02→ttyACM1).
- **Le Mac tourne ALARM (tethered boot)** à la fin de cette session. Pour faire du SEP il faut le remettre
  en **m1n1 proxy** (ALARM ≠ proxy : le noyau a pris la main).
- **Piège PMU/SPMI (vu aujourd'hui, aussi en mémoire)** : après des manips SEP (sep_peek / voie C), `linux.py`
  plante au `PMU.reset_panic_counter` (UartTimeout SPMI, bus PMU figé). **Un m1n1 frais ne suffit pas** →
  **coupure complète du courant** (bouton alim ~10 s). Ensuite le **proxy USB ne réénumère pas seul**
  (rien sur ttyACM / lsusb alors que l'écran dit « running proxy ») → **changer câble/port** jusqu'à ce que
  `serial/by-id` revienne. Une fois coupé proprement, le PMU répond et le boot passe.
- `tools/tethered_boot.sh alarm` lancé **sans terminal** finit par `termios.error: Inappropriate ioctl for device`
  (ouverture du ttymode) — **pas un échec**, le noyau est déjà parti. ALARM se rejoint par SSH (`tools/linux_ssh.sh`, root@10.0.200.4).

**CE QUI A CHANGÉ CÔTÉ ANALYSE (corrige les sections plus bas) :** voir [[voie-c-xart-fraicheur]], docs/messages.md
+ docs/hypotheses.md (section xART, 2026-11-12), docs/kext_sepmanager.md §8/§9.
- Le blob xART variable rejoué **= exactement le DERNIER SAVE du boot précédent** (chaînage prouvé octet pour octet,
  `fetch(N)=save(N-1)`). Donc un rejeu doit resservir **le dernier SAVE, PAS le FETCH initial** d'un boot.
- Les 2 blobs qui changent par boot = **SEP-xART maître** (TAG 0x03, avant sbio) + locker **Credential Manager**.
  **USER-xART est STABLE** (corrige une hypothèse antérieure). UUID d'OS constant `EFF3C698-…` (rejouable, pas le verrou).
- La divergence de l'essai n°1 (SEP envoie TAG=0x05 **TYPE=0x01 SAVE** au lieu de FETCH) = re-scellement **attendu**.
  Le verrou de fond (clé relayable OU compteur scellé) **ne se tranche QUE par une écriture**.

**PROCHAIN PAS = essai observationnel (écriture SEP → script `pending/`, Albert lance).** Pas encore écrit.
Il doit **suivre le SEP** au lieu de s'arrêter à la divergence : laisser le SEP re-sceller (op 0x01), **l'acquitter**,
et regarder s'il finit par annoncer **`sks` (0x12, le trousseau)** et atteindre un état fonctionnel (≠ juste `sbio`).

**PROCÉDURE :**
1. *(Optionnel — décision Albert)* **image disque** depuis ALARM (qui tourne). Discuté : ce n'est **pas** un vrai
   filet pour le SEP (une image disque ne répare pas le SEP ; seul DFU Restore le fait), juste du confort. Les vrais
   filets existent déjà : ALARM boote indépendamment + DFU Restore plus tard. Albert tranche : image ou on saute.
2. **Remettre le Mac en m1n1 proxy** : power-cycle, **ne PAS** tethered-booter ALARM ; vérifier `/dev/ttyACM`
   (re-câble/port si besoin, cf. piège ci-dessus).
3. **J'écris le script** dans `pending/` (en-tête but / risque / résultat attendu ; relais du **dernier SAVE** ;
   OBSERVE = suit le SEP, acquitte le SAVE, écoute l'annonce d'endpoints).
4. **Albert relit.**
5. **Albert lance.** Je lis la trace : SEP accepte et avance (sks annoncé → rejeu suffisant) OU re-scelle et bloque
   (compteur scellé). S_new à relayer : repartir de `traces/20261111-113919_snew-reel` (ou recapturer un S_new en
   lecture seule avant, sans booter macOS entre-temps).

**EN ATTENTE D'ALBERT :** (a) image disque oui/non ; (b) quand lancer (reboot m1n1 maintenant, ou plus tard).

**Sûreté (mémoire voie-c-xart-fraicheur) :** lectures seules et **boot SEP permissif nu** (sep_boot, sep_peek) OK en
autonomie (le SEP-BOOT du 2026-11-09 n'a pas cassé le menu, auto-récupéré). Ce qui casse = **engagement xART +
re-scellement**. Toute écriture xART = Albert + (si choisie) image disque.

## POINT DE REPRISE 2026-11-11 (fin après-midi, Opus 4.8) — essai voie C REPRODUIT ; reprendre par l'observation
<!-- ⚠️ SECTION HISTORIQUE — l'état matériel ci-dessous (tunnel relais 10.0.200.5, « Mac débranché », S_new à
     recapturer) est PÉRIMÉ. État courant et procédure à jour = section 2026-11-12 en tête. Garder pour l'historique
     des idées (OBSERVE, divergence) mais NE PAS suivre les commandes tunnel/relais : le Mac est en USB local direct. -->

**Acquis aujourd'hui (vérifié n=2, Albert a lancé) :** un SEP démarré par m1n1 accepte la pose des tampons
xART, **rejoue 4 lockers** (dont SEP-xART+USER-xART), **annonce sbio/scrd/sse/skdl**, puis **diverge à la 5e
transaction** (SEP demande TAG=0x05 TYPE=0x01=SAVE au lieu de TYPE=0x05=FETCH). Reproductible sur 2 runs.
« sbio annoncé » ≠ « Touch ID marche » (sks 0x12 absent). Détail : journal + docs/hypotheses.md « Revue
sceptique — ESSAI VOIE C n°1 » + docs/voie_c_design.md « Résultats ».

**PROCHAIN PAS = essai A (observationnel), déjà prêt** (`OBSERVE` est le DÉFAUT de `pending/sep_xart_replay.sh`) :
rejoue pareil puis **écoute le tampon B en lecture seule ~20 s sans répondre sur 0x13** (n'acquitte PAS le
SAVE → compteur anti-rejeu préservé). But : voir ce que le SEP réclame à la divergence (B≈849 o = SAVE ?).

**ÉTAT MATÉRIEL à la reprise :** Albert a débranché le Mac. Son m1n1 s'était **coincé** (« 0 octet ») après
une capture S_new ratée (run_guest avorté sur lien instable — voir mémoire tunnel-relais-mac, erreur notée).
**À faire pour reprendre :**
1. Albert rebranche + **reboot physique en m1n1**.
2. Relancer le tunnel si besoin : `./tools/restart_tunnel.sh` (le kill est bloqué par le mode auto → Albert
   approuve, ou il lance `! ./tools/restart_tunnel.sh`). NE PAS relancer le tunnel si `sep_peek` dit déjà
   « Running proxy... » (m1n1 vivant, octets périmés qui se purgent en réessayant).
3. **1 seul `./tools/sep_peek.sh`** pour confirmer le lien (lecture seule) — rien d'autre.
4. **Pas besoin de recapturer un S_new** : `traces/20261111-113919_snew-reel` est toujours valide (la capture
   ratée n'a jamais démarré macOS). Si macOS a VRAIMENT rebooté entre-temps, alors recapturer.
5. Albert lance (écriture SEP, jamais l'agent) :
   `M1N1TIMEOUT=20 M1N1DEVICE=/tmp/m1n1 HV_UART=/tmp/m1n1-console ./pending/sep_xart_replay.sh traces/20261111-113919_snew-reel`
   (OBSERVE par défaut → la lecture de B à la divergence s'affiche automatiquement.)
6. Reproductibilité : relancer tunnel.py ENTRE chaque run (le lien désync après chaque run).

## Mise à jour 2026-11-11 (journée, Opus 4.8) — EXPÉRIENCE VOIE C PRÊTE À LANCER

**Contexte matériel nouveau** : le MacBook n'est pas en USB local mais derrière un **relais TCP**
(`10.0.200.5`, ports 4000 proxy / 4001 console). Monter le lien : `./tunnel.py` (robuste, PTY stable),
puis `export M1N1DEVICE=/tmp/m1n1 HV_UART=/tmp/m1n1-console`. **Pour le boot macOS (run_guest) : `export
M1N1TIMEOUT=20`** (le défaut 3 s est trop court sur ce lien → UartTimeout ; c'était LA cause des échecs,
pas le tunnel). Détails + récup : mémoire `tunnel-relais-mac`. (Côté relais, bridge avec `fork`.)

**Ce qui est fait et commité aujourd'hui** :
- `tunnel.py` : lien relais fiable (chainload 6/6).
- `pending/sep_xart_replay.sh` **v2** : rejeu xART avec le rôle AP complet (SECMODE + allocation/mapping/
  annonce des tampons OOL via CNTL, protocole du kext §3/§5), puis rejeu fidèle des lockers depuis une
  capture S_new. **Validé** : SELFTEST OK, et surtout le protocole CNTL est **confirmé octet pour octet**
  contre la capture réelle non filtrée `traces/20261111-111740_cntl-study3` (ordre 0x14→0x04/0x02/0x05/0x03,
  IOVA 0x2c/0x38, ack TYPE 0x01 même tag).
- `CLAUDE.md` : décompilation élargie (tout binaire Apple pertinent) ; leçon RTFM M1N1TIMEOUT.
- Docs : `voie_c_design.md` « Correctif voie C » (protocole complet), journal, mémoires à jour.

**ÉTAT : script v2 PRÊT et relu (sceptique : « lançable tel quel », sûr, 0 opération disque). Mac au m1n1
propre. MAIS il MANQUE un vrai S_new.** `traces/20261111-111740_cntl-study3` a servi à VALIDER le protocole
CNTL (octet pour octet), mais ses lockers .ool sont **tronqués à 0x400** (capturé avec le défaut `nbytes=0x400`)
→ **INUTILISABLE comme S_new** (le tampon A serait rejoué incomplet). Erreur de la session précédente, corrigée ici.

**PROCÉDURE pour lancer l'essai voie C :**
1. **Capturer un vrai S_new** (lecture seule, ~15 min ; `SEP_OOL_BYTES=0x8000` = tampon COMPLET, et reboot auto
   en m1n1 à la fin) :
   ```
   M1N1TIMEOUT=20 M1N1DEVICE=/tmp/m1n1 HV_UART=/tmp/m1n1-console \
   SEP_OOL_EPS=0x13 SEP_EPS=0x13 SEP_OOL_BYTES=0x8000 END_ACTION=reboot \
   ./tools/boot_and_trace.sh snew-reel
   ```
   Vérifier ensuite que `traces/..._snew-reel/sep.log.ool/*_A.bin` font bien **32768** octets.
2. **NE PAS booter macOS entre la capture et le lancement** (reboots m1n1 OK — m1n1 = startup disk).
3. **Albert lance** (écriture SEP), après relecture de l'en-tête de `pending/sep_xart_replay.sh` :
   ```
   M1N1TIMEOUT=20 M1N1DEVICE=/tmp/m1n1 HV_UART=/tmp/m1n1-console ./pending/sep_xart_replay.sh traces/<le_snew-reel>
   ```
   Succès = `>>> sbio PRÉSENT`. Échecs = sorties propres (exit 2/3) AVANT toute écriture risquée.

**Sceptique (fait, 2026-11-11)** : v2 conforme à la capture réelle, sûre. Incertitudes de fond, tranchées
seulement par l'essai (non bloquantes pour la sûreté — échec propre si manqué) : le stream/IOVA DART que xarm
lit vraiment ; faut-il aussi poser les tampons de 0x18(stac)/0x0e(hdcp) avant que le SEP enchaîne xART ;
le SEP démarré par m1n1 enchaîne-t-il l'échange. Amélioration v3 notée : écrire A via `phys_A` direct plutôt
que re-dériver par `find_sid` (évite une mappe résiduelle d'un stream inférieur).

## Mise à jour nuit du 2026-11-11 (session autonome, Opus 4.8)
- VOIE B FAITE. Contenu du coffre xART capturé en lecture seule sur 3 boots macOS : c21/c23/c24 = traces T-45/T-46/T-47. Outils déjà en place (SEP_OOL_EPS=0x13). c22 a raté (boot à chaud), ignoré.
- Résultat clé (vérifié octet pour octet, journal + messages.md « xART — contenu OOL » + verification_status « xART-CHAIN ») : sur 10 lockers rendus au SEP, 8 sont identiques sur les 3 boots ; 2 changent = SEP-xART (TAG 0x03) et un locker Credential Manager (TAG 0x10, UUID 8624497a…). USER-xART (TAG 0x04) est STABLE. Chaînage save(N)=fetch(N+1) prouvé sur le contenu. Aucun compteur en clair ; fraîcheur = préfixe 16 o (nonce/MAC) + corps chiffré renouvelé = hypothèse.
- Verdict rejeu (voie C) : plausible, non mort. Rendre la dernière sauvegarde = ce que le SEP attend ; seul un essai en écriture (pending/ + Albert) dit si l'état interne l'accepte quand Linux boote le SEP. Analyse : docs/xart_options.md. Scripts : analysis/diff_xart_ool.py, scratchpad lockers_variables.md.
- Autres résultats de la journée du 10-11 : capteur relayé octet pour octet au SEP (image 0x65, OOL EP 0x08, analysis/cmp_sensor_sep_image.py) ; 27 images lues / 7 transmises (count_sensor_vs_sep_images.py) ; transport capteur réactif (mesa_wait_ready, broche gpio0 195 caractérisée) ; piste hibernation écartée côté SEP (docs/power_sep_options.md, c'est du power management, pas le SEP).
- GUIDE : docs/guide/05-xart.md réécrit au style (3 boots). En cours de dernier tour de relecture (lecteur-naif + verificateur). À faire ensuite : y intégrer l'identité précise des 2 lockers variables (SEP-xART + locker Credential Manager, USER-xART stable) une fois ces faits dans les notes — ils y sont depuis cette session. Chapitres encore périmés par la journée : 06-capteur (image relayée, broche, transport réactif) et 09-etat-et-suite.
- PROCHAIN VRAI PAS = essai de rejeu (voie C), écriture SEP, donc script pending/ relu et lancé par Albert, avec garanties : aucun brick, aucune atteinte à la partition Linux. macOS sacrifiable (backup Linux seulement, voir mémoire priorites-risque).
  Plan détaillé + analyse de sûreté + SPEC CODABLE : docs/voie_c_design.md. La spec est complète côté lecture : buffers xarm (A IOVA 0x2c000, B IOVA 0x38000, 0x8000, relus à la volée), et table de rejeu des 10 lockers de la phase de boot (TAG, en-tête de réponse PARAM/DATA, étiquette de 16 o ; SEP-xART et USER-xART sans étiquette ; Credential Manager = étiquette 8624497a lue 3 fois). Les 3 lockers qui changent = SEP-xART, USER-xART (en fait USER-xART stable, voir journal — SEP-xART + locker 0x10 Credential), reste à coder.
  Reste pour le script pending/ (session dédiée, moi j'écris / Albert lance) : l'implémentation m1n1 qui boote le SEP (pending/sep_boot.sh existe) puis joue le rôle de l'AP sur l'EP 0x13 (lire l'étiquette dans buffer B, écrire le locker dans buffer A à l'IOVA apprise, renvoyer la réponse). Vérifier d'abord qu'on peut ÉCRIRE dans le buffer du SEP par le DART depuis m1n1 (on n'a fait que lire jusqu'ici). Idée S_new : capturer juste avant, sans reboot macOS entre capture et essai. Seule inconnue de fond : l'anti-rejeu accepte-t-il le rejeu.


## Albert et la façon de travailler
- Français simple, courtes réponses, souvent depuis son téléphone. IL NE COMPREND PAS LE JARGON (étapes, EP, « proposé vérifié »…). Décide seul tout le technique ; ne lui demande que ce qui peut abîmer le Mac ou écrit vers le SEP, en une phrase (quoi, ce qui peut rater, oui/non). Tout ce qu'il doit lancer : commande prête à coller avec `! `.
- Autonomie : captures/reboots via tools/boot_and_trace.sh, sous-agents (analyste, lecteur-logs, sceptique, tracer, documentaliste, driver) sans demander. Quota limité. Appel : ./tools/appel_albert.sh "consigne courte".
- Lignes rouges (CLAUDE.md) : pas de sudo/bputil/kmutil/csrutil/nvram/dd/partitionnement ; le hardware passe par tools/*.sh ; toute écriture SEP = script dans pending/ avec en-tête (but, risque, résultat), Albert le lance ; rien vers Asahi ; traces/ en lecture seule ; pas de copie de code Apple ; info de kext marquée `source: kext`. Exception : sur le Linux de test root@10.0.200.4 uniquement, root via tools/linux_ssh.sh (son filtre refuse les commandes contenant « sep », « xart », 0x10/12/13/15, disques, m1n1… : évite ces chaînes dans les commandes).
- Commits fréquents, attribution demandée par le harness. Albert a un backup de sa partition Linux (c'est tout ce qui lui importe) ; la reconnexion iCloud qu'il a subie après le boot SEP par m1n1 est de cause non établie (2 reboots natifs ensuite sans souci).

## Résultats acquis (tout commité)
- Captures C1-C16 (K-E1 terminée : TAG 0x01 suit le keybag, 0x209@lock, 0x228@mdp, 0x208@doigt ; 0 TAG 0x01 pendant invites en session ouverte).
- Statuts : init 57 commandes, structure 0x65 + CRC, boucle 0x6c→0x6d = « vérifié (macOS) » (= ce que macOS fait, pas ce que le SEP exige). driver/ (sepreplay, 29 tests) rejoue tout hors ligne.
- ADT : capteur `biosensor,mesa` sous spi2 (0x39B108000, IRQ AIC 1108, pas de chip-select, CPHA 1, CLKDIV 3), alimentation capteur = gpio0 196 (0xc4) actif haut, IRQ gpio0 195. Alimentation de spi2 = pmgr SPI2, registre 0x28e580200 = ps_spi2 du DT public. Broches gpio0 48/49/50 déjà réglées par iBoot : rien à configurer (vérifié par MESA-HELLO).
- SEP sous m1n1 seul : peek lecture seule OK ; GETRAND (EP 0xFF) répond ; pending/sep_boot.sh (code public m1n1, DART T6000) a démarré SEPOS : « BOOT OK », 7/12 endpoints (cntl hdcp xars xarm hibe pnon stac), sans sbio/sks/scrd/sse/skdl.
- Dans 19/19 boots macOS, sbio etc. sont annoncés ~0,12 s après la réponse de l'AP à l'échange xART (EP 0x13). xART = coffre : le SEP confie des blobs, l'AP les lui rend au boot suivant (état du disque macOS, jamais capturé). Rejeu impossible sans ce contenu, et risqué (macOS/FileVault/trousseau). Décision : aucune réponse 0x13/0x15, aucune capture des blobs, pas de nouveau boot SEP.
- Linux de test (Fedora Asahi Remix, 10.0.200.4) : gcc/make/git/dtc/kernel-devel installés ; sources dans /root/mesa (mesa_probe.c, mesa_ovl.c, mesa-spi2-overlay.dts, copies de driver/linux/). DT vivant sans __symbols__, pas de configfs d'overlay, mais `of_overlay_fdt_apply` marche depuis un module (mesa_ovl).
- Outils ajoutés le 2026-11-10 : tools/gpio_peek.sh (lecture broches + alimentation), tools/mesa_hello.sh (bonjour capteur depuis m1n1), hv/trace_sep_spi.py et hv/trace_sep_spi_dma.py (écoute du bus capteur sous macOS), analysis/adt_pmgr_ps.py, analysis/spi2_transfers.py, analysis/sio_dialog.py.

- Bus SPI du capteur écouté sous macOS (2026-11-10, C17-C20, hv/trace_sep_spi_dma.py, analysis/sio_dialog.py, docs/sensor_hw.md « Dialogue SPI ») : trames en clair = réveil 0x78, identité 0x70, état 0x10, lecture 0x13 ; tout le reste est chiffré entre le SEP et le capteur, l'AP relaie (vérifié macOS pour l'image 0x65, C20). Albert a confirmé le 2026-11-10 que le projet reste privé malgré l'interdiction d'IA de m1n1/CLAUDE.md : ne rien modifier dans m1n1/, rien vers Asahi.

## Où on en est (fin de la session du 2026-11-10, tout est commité)
1. CAPTEUR : FAIT ET VÉRIFIÉ. Le capteur répond sans macOS aux trames en clair (réveil 0x78, état 0x10, identité 0x70, lecture 0x13), identité identique à celle vue sous macOS : depuis m1n1 (tools/mesa_hello.sh, 2 essais) et depuis Linux (LINUX-HELLO, 1 essai). Sur le Linux de test : `cd /root/mesa && cp mesa-spi2.dtbo /lib/firmware/ && insmod mesa_ovl.ko && insmod mesa_probe.ko enable=1 && dmesg | tail -20` (ajout à chaud de spi2 + capteur, rien d'installé, à refaire après chaque reboot ; les numéros de l'overlay valent pour le noyau 7.2.12-402.asahi.fc45). Le développement capteur se fait par ssh, Mac seul, sans câble USB.
2. Ce que Linux ne peut pas faire sans le SEP : tout le reste du dialogue capteur est chiffré entre le SEP et le capteur ; sous macOS l'AP ne fait que relayer (vérifié macOS pour l'image 0x65, C20). Table des états du capteur : docs/sensor_hw.md. Plan à jour : docs/driver_plan.md (« Mise à jour 2026-11-10 (nuit) »).
3. BLOCAGE inchangé : sbio n'est annoncé qu'après l'échange xART (le « coffre »). Décision en vigueur : aucune réponse 0x13/0x15, aucune capture des blobs, pas de nouveau boot SEP.
4. FILTRE DE SÉCURITÉ DU MODÈLE (important pour la session suivante) : pendant la session du 2026-11-10 (Fable 5.2), trois choses ont été coupées par le filtre « [cyber] » : (a) un sous-agent documentaliste chargé d'étudier les voies possibles pour xART ; (b) la relance, même réduite à un résumé de la doc publique ; (c) une analyse hors ligne comparant les buffers échangés avec le SEP (OOL de C20) aux trames du bus du capteur. Rien n'a été produit sur ces trois points et ils n'ont pas été refaits autrement. Albert change de session pour traiter ce sujet (programme de vérification Anthropic : https://support.claude.com/en/articles/14604842-real-time-cyber-safeguards-on-claude). Si le filtre coupe encore : ne pas insister ni reformuler, le noter au journal, passer à la liste de tâches ci-dessous.
5. Reste ouvert (ancien) : SKS-1 (le SEP refuse-t-il 0x09 avant le mot de passe ? tranche seulement par une écriture), 2e 0x209 inexpliqué après chaque lock, cause de la reconnexion iCloud, rôle des 20 images non transmises au SEP (C20) — QUANTIFIÉ 2026-11-10 : 27 lues sur le bus, 7 transmises (hypothèse : trames de prévisualisation non envoyées) ; voir analysis/count_sensor_vs_sep_images.py, groupe de broches 116-118.
6. m1n1/CLAUDE.md (mainteneurs de m1n1) interdit l'usage d'IA sur LEUR projet. Albert a décidé le 2026-11-10 : le travail reste privé, aucune contribution ; on ne modifie rien dans m1n1/ et rien ne sort vers Asahi. Ne pas lui reposer la question.
État du Mac en fin de session : Albert le redémarre sur le Linux de test et le relie au réseau par VPN ; l'adresse autorisée reste 10.0.200.4 (si elle change, c'est Albert qui modifie CLAUDE.md et tools/linux_ssh.sh). Câble USB débranché : pas de m1n1 ni de capture macOS tant qu'il n'est pas rebranché.

## Liste de tâches (tenue à jour par Claude ; Albert peut ajouter des lignes en français normal)
Légende : [ ] à faire, [x] fait, [!] bloqué (dire pourquoi).

### Sans Albert, sans le Mac
- [x] Table des réponses d'état du capteur (docs/sensor_hw.md, 2026-11-10).
- [x] Ranger le module Linux : transport (mesa_transport.h) séparé du test « bonjour » (mesa_probe.c), compile W=1 (2026-11-10).
- [x] docs/driver_plan.md mis à jour (2026-11-10 nuit).
- [x] Étude du « coffre » (xART) : docs/xart_options.md écrit le 2026-11-10 (Opus 4.8, filtre non déclenché). 5 voies, reco = voie B.
- [x] Comparaison fine image puce ↔ bus ↔ SEP : faite le 2026-11-10 (analysis/cmp_sensor_sep_image.py). Image relayée octet pour octet au SEP (OOL 0x08, entête 0x1c, type 0x65), chiffrée bout en bout. verification_status.md SPI-1.
- [x] Voie B outillage : l'OOL de l'EP 0x13 est déjà traçable (SEP_OOL_EPS=0x13), commande prête dans docs/xart_options.md. Rien à coder.
- [x] Voie B capture : FAITE 2026-11-11 (c21 + c23, lecture seule). Coffre xART : 8/10 blobs stables entre 2 boots, 2 changent, saves 100 % frais. Verdict rejeu : ni mort ni gagné, tranchable seulement par un test en écriture. docs/xart_options.md voie C, analysis/diff_xart_ool.py.

- [x] Caractérisé la broche gpio0 195 (2026-11-10, mesa_irqwatch hello=1) : ligne « donnée prête », remonte à chaque réponse en attente (y compris après 0x70), retombe à la lecture d'état. Pilotage par interruption possible.
- [x] Transport réactif : mesa_wait_ready() attend la broche « donnée prête » (scrutation sûre) avant chaque lecture d'état ; identité toujours identique (2026-11-10).
- [ ] (optionnel, risqué à distance) Vrai pilotage par interruption matérielle (request_irq) : seulement quand Albert peut power-cycler le Mac (rafale d'IRQ possible).
- [x] docs/sensor_hw.md : comportement de la broche 195 et de l'octet 0x18 reporté (2026-11-10).

### Avec le Mac sur le Linux de test (joignable à 10.0.200.4), sans action d'Albert
- [x] Recharger les modules et refaire le « bonjour » (reproductibilité) : FAIT 2026-11-10 sur 10.0.200.4, identité identique, avec le module rangé (transport). Entrée journal du jour.
- [x] État du capteur en boucle 30 s sans doigt : stable (2026-11-10, mesa_statloop.c ; 0x18 seulement à la 1re lecture).

### Avec Albert devant le Mac (2 minutes)
- [x] Doigt posé sans la puce de sécurité : l'état ne change pas (2026-11-10, 1 essai, doigt déclaré par Albert). Journal 06:08.
- [x] Même essai en regardant la broche d'interruption (gpio0 195) : elle marche sous Linux (1 à l'allumage, 0 après la 1re lecture d'état) mais ne réagit pas au doigt (2026-11-10, mesa_irqwatch.c, journal 06:15).

### Décisions qui appartiennent à Albert
- [ ] Faut-il s'inscrire au programme de vérification d'Anthropic pour débloquer l'étude du « coffre » ?
- [ ] Jusqu'où aller : s'arrêter au « Linux parle au capteur », ou viser un Touch ID complet (dépend du « coffre », risque pour macOS à évaluer).
