#!/usr/bin/env bash
# =============================================================================
# sep_native_sbio7.sh — ROUTE NATIVE + sbio : refaire TOUT sbio6 (persist → 0x73 → 0x17 franchi →
#   key exchange 0x15/0x16 relayé → compteur 0x42/0x18 relayé → patch 0x5f REÇU+RÉASSEMBLÉ) PUIS
#   **ÉMETTRE** le push du patch au capteur : prélude SPI `80 60 00 07 00 00 00` (7 o) + le bloc patch
#   (~22158 o) en FIFO scruté, lire l'état capteur (0x10) avant/après, rendre un VERDICT (push accepté
#   vs cassé) et S'ARRÊTER (on N'ENCHAÎNE PAS les params 0x5d/0x5c… ce run). C'est le TEST DE FAISABILITÉ
#   du push 22 Ko en FIFO scruté que sbio6 avait volontairement laissé de côté.
#
#   VOIE CHOISIE = PUSH réel (sbio6 s'arrêtait AVANT). POURQUOI MAINTENANT (voir RAPPORT + sbio_session.md §3-4) :
#     sbio6 a PROUVÉ sur matériel que le SEP livre le patch à l'AP (fe/fd) et que l'AP le réassemble en entier
#     (22158 o, préfixe cohérent). La seule inconnue restante de la 2e moitié = le PUSH AP→capteur. macOS le
#     fait en UN burst DMA SIO. On ne peut PAS tester hors-ligne si le contrôleur SPI2 garde CS asserté sur un
#     transfert FIFO aussi long : sbio7 est PRÉCISÉMENT l'expérience qui tranche. Deux issues honnêtes :
#       (a) le FIFO tient 22 Ko (CS maintenu, pas de timeout) → status capteur lisible/cohérent → push accepté.
#       (b) le FIFO ne tient pas (timeout / CS lâché mi-parcours) → STOP+dump + message clair « il faut le DMA
#           SIO (sbio8) ». Le capteur peut rester MI-PATCHÉ : un power-cycle (teardown du finally) le récupère.
#
# ─────────────────────────────────────────────────────────────────────────────
# EN LANGAGE CLAIR (décision go / no-go — Albert)
#   BUT : sbio6 a reçu + réassemblé sur matériel le PATCH CAPTEUR 0x5f (LoadPatch) que le SEP fabrique CHIFFRÉ
#   et FRAIS à chaque boot (~22158 o, non rejouable) et livre à l'AP. Il restait à savoir si on peut le POUSSER
#   au capteur comme le fait macOS. sbio7 FAIT ce push, en FIFO scruté (le transport qu'on maîtrise), et regarde
#   si ça tient :
#     {sbio 0x5f → le SEP livre le patch ~22 Ko à l'AP en fragments OOL} → {l'AP réassemble (poignée fe/fd) →
#      patch complet 22158 o} → {l'AP ÉMET au capteur : prélude `80 60 00 07 00 00 00` (7 o) PUIS le bloc patch
#      (22158 o) en UN transfert SPI} → {lire l'état capteur 0x10 → VERDICT : status lisible/cohérent = push
#      accepté ; timeout ou status cassé = le FIFO ne tient pas 22 Ko → il faut le DMA SIO (sbio8)}.
#   Poignée de livraison multi-fragment (VU C12 seq 313-316, re-VU C19) : l'AP envoie 0x5f (TAG=0xfc), le SEP
#   répond un 1er fragment (TAG=0xfc, en-tête gt_packet : total 32b @+0x04, offset @+0x08, long. fragment @+0x18,
#   charge @+0x1c) ; tant que offset+long < total, l'AP RÉCLAME la suite (TAG=0xfe, tampon A inchangé) et le SEP
#   rend le fragment suivant ; le DERNIER vient en TAG=0xfd (DATA=0x00010000). L'AP recolle charge[+0x1c:+0x1c+long]
#   à la position `offset`. Les octets du patch ne sont JAMAIS modifiés : on les reçoit, recolle, et on les émet
#   TELS QUELS au capteur. Ce script refait TOUT sbio6 (persist → 0x73 → 0x17 → key exchange → compteur → RECON
#   0x5f), PUIS ÉMET le push, lit l'état capteur, rend le verdict, et S'ARRÊTE (pas de params 0x5d… ce run).
#
#   CE QUI EST ÉCRIT (⚠️ même classe de risque que sep_native_sbio3.sh / persist — récupérable) :
#     - Booter le firmware SEP (IMG4) : écriture SEP, routine depuis des semaines.
#     - Acquitter les SAVE (0x01/0x06) fait AVANCER le compteur anti-rejeu scellé du SEP : irréversible au
#       sens « on ne revient pas en arrière sur le compteur ». MÊME chose que persist / sbio3.
#     - ALIMENTER le capteur (gpio0 196) + spi2 en mode scruté, lire identité (0x17) PUIS relayer le key
#       exchange : EXACTEMENT le transport de tools/mesa_hello.sh (brique mesa_spi_proxy). Le capteur reste
#       ALIMENTÉ entre 0x17 et le key exchange (une seule session). TOUT est REMIS dans l'état d'iBoot en
#       FIN de run (power_off + restore dans le finally EXTERNE, MÊME en cas d'erreur). AUCUN DOIGT.
#     - Le key exchange 0x15/0x16 PUIS le compteur 0x42/0x18 relaient des OCTETS OPAQUES : le SEP rend un blob
#       (40 o puis 64 o), on le passe au capteur, le capteur rend un blob, on le rend au SEP. AUCUN SECRET
#       connu/extrait côté AP, AUCUNE image, AUCUN match, AUCUN enrôlement, AUCUN DOIGT. On lit/dumpe tout.
#     - Comme sbio6 : on ENVOIE 0x5f au SEP (entrée 2 o, opaque) et on REÇOIT le patch ~22 Ko qu'il livre
#       (poignée fe/fd). 0x5f est une commande sbio (EP 0x08), MÊME classe que 0x17/0x15/0x42 déjà envoyés :
#       elle fait AVANCER l'état de la session capteur côté SEP, mais n'écrit NI vers le keybag NI vers le
#       xART (0x12/0x13) ; aucun secret, aucune image, aucun doigt. On reçoit/réassemble/dumpe le patch.
#     - NOUVEAU sbio7 : on ÉMET le patch AU CAPTEUR (vers le capteur SPI, PAS vers le SEP) : prélude SPI
#       `80 60 00 07 00 00 00` (7 o) puis le bloc patch (22158 o) via mesa_spi_proxy (FIFO scruté), EXACTEMENT
#       le transport de tools/mesa_hello.sh, juste un bloc plus gros. On ne POUSSE PAS la suite (params 0x5d/
#       0x5c/0x55…) ni commande blob/doigt. Après le push on LIT l'état capteur (0x10) et on S'ARRÊTE.
#     - ⚠️ RISQUE PRINCIPAL (non testable hors-ligne) : pousser 22 Ko en FIFO scruté demande ~1400 cycles
#       remplir-FIFO/attendre-vide SANS relâcher CS. Si le contrôleur SPI2 dé-asserte CS quand le FIFO se vide
#       entre deux remplissages, le patch arrive CASSÉ. On code le push le plus CONTINU possible (on remplit
#       le FIFO dès qu'il y a de la place, sans trou) et on allonge le timeout (défaut 60 s), mais on ne peut
#       PAS garantir le CS-maintenu avant de l'avoir vu tourner. Si le push rate (timeout/erreur), on STOP+dump
#       et on dit clairement « le FIFO ne tient pas 22 Ko → il faut le DMA SIO (sbio8) ». Le capteur peut rester
#       MI-PATCHÉ ; le teardown du finally (power_off) le power-cycle et le récupère.
#     - Récupération : through-SEP = quasi toujours réparable par DFU (voie C), PAS garanti à 100 %
#       (Stockholm / inconnus). Backup + IPSW prêts. macOS sera désynchronisé — on s'en fiche (ne boote déjà
#       plus). Linux : aucun risque.
#     - Budget de SAVE BORNÉ (MAX_SAVES, défaut 48). Fail-closed PARTOUT : op EP 0x13 inconnue, CNTL non
#       acquitté, 0x73 sans réponse, capteur muet / identité inattendue, série ≠ gabarit c12, 0x17 non
#       acquitté, réponse 0x15 ≠ 40 o, réponse SPI trop courte, 0x16 non acquitté, réponse 0x42 ≠ 64 o,
#       réponse SPI 0x73 trop courte, 0x18 non acquitté → on N'ENVOIE RIEN de plus, on dumpe, on s'arrête,
#       ET on remet le capteur comme iBoot.
#
#   CE QUE ÇA N'EST PAS : pas du rejeu de coffre macOS (store VIDE xart_store_sbio7, À PART ; le SEP crée
#     SON état frais). Les gabarits 0x15/0x16/0x42/0x18/0x5f relus de la capture c12 (000305/000307/000309/
#     000311/000313_08_A.bin) servent de FORME EXACTE du gt_packet ; la CHARGE des 0x16/0x18 est REMPLACÉE par
#     les octets que le CAPTEUR rend À L'INSTANT. « patch poussé » ≠ « Touch ID marche » : restent les params
#     chiffrés (0x5d/0x5c/0x55…), la calibration, le match, l'enrôlement. On teste UNIQUEMENT la FAISABILITÉ
#     du push 22 Ko en FIFO scruté ; un status capteur OK ne dit RIEN du reste de la session.
#
#   ENDPOINTS TOUCHÉS : 0x00 (CNTL), 0x13 (xART/gigalocker, comme persist), 0x08 (sbio : 0x73 + 0x17 +
#     0x15/0x16 + 0x42/0x18 + 0x5f), + le CAPTEUR SPI (spi2 + gpio0 196 : identité 0x17 + relais 0x72 du key
#     exchange + relais 0x73 du compteur + PUSH du patch 0x60, comme mesa_hello, un bloc plus gros). Le push va
#     AU CAPTEUR (spi2), PAS au SEP (0x12/0x13 jamais touchés en écriture par le push).
#   RISQUE : identique à sep_native_sbio6.sh (boot IMG4 + ACK SAVE = compteur avance ; alim/SPI capteur
#     restaurée dans le finally) PLUS, en nouveau, l'ÉMISSION de 22 Ko au capteur en FIFO scruté : NON TESTÉ,
#     CS-maintenu incertain. Pire cas : capteur mi-patché → power-cycle (teardown) récupère. Aucun secret, aucun
#     doigt. Le patch émis = octets opaques du SEP recopiés tels quels.
#   RÉSULTAT ATTENDU : le script refait sbio6 (0x17 + key exchange + compteur + RECON 0x5f), puis ÉMET le push.
#     VERDICT auto-vérifiant du PUSH : le prélude passe (petit), puis le bloc 22158 o est émis en UN xfer. Si
#     le xfer se termine SANS timeout ET que l'état capteur relu (0x10) est bien formé (en-tête 80 20 00 10) →
#     PUSH ÉMIS, status capteur lisible (= « patch chargé », pas de read-back d'après sbio_session §3). Si le
#     xfer time-out / lève, ou si l'état capteur est illisible après → le FIFO NE TIENT PAS 22 Ko → STOP+dump +
#     message « il faut le DMA SIO (sbio8) ». Dump complet dans TOUS les cas (fragments OOL bruts, patch
#     réassemblé, trame de push, état capteur avant/après). On S'ARRÊTE après le push (pas de params ce run).
#   PRÉPARÉ PAR : Claude (Opus 4.8), 2026-11-22 — à relire et lancer par Albert, backup + DFU prêts.
#                 L'agent ne lance JAMAIS ce script en réel (uniquement SELFTEST=1 hors-ligne).
# ─────────────────────────────────────────────────────────────────────────────
#
# TECHNIQUE
#   PHASE 1 — NATIF (IDENTIQUE à sbio3) : ack recon, SERVIR/ABSENT les FETCH, STOCKER+ACK les SAVE, boucle
#     jusqu'à idle, budget MAX_SAVES, fail-closed sur op inconnue.
#   PHASE 2 — SONDE sbio (IDENTIQUE à sbio3) : ouvrir l'EP 0x08 (A8/B8), 0x73 exact, verdict VIVANT/MUET.
#   PHASE 3 — FRANCHIR 0x17 (IDENTIQUE à sbio3 à une exception près) : MesaSPI power_on + read_id → série lue
#     en direct, VÉRIFIER == gabarit c12, envoyer 0x17. EXCEPTION sbio4 : le capteur reste ALIMENTÉ (PAS de
#     power_off entre 0x17 et le key exchange), l'instance MesaSPI VIT jusqu'à la fin, et le TEARDOWN (power_off
#     + restore) va dans le finally EXTERNE (après la Phase 4), MÊME en cas d'erreur.
#   PHASE 4 — RELAIS key exchange 0x15/0x16 (IDENTIQUE à sbio4) :
#     (1) sbio 0x15 : gabarit 000305_08_A.bin (sessionType=1), envoyer EP 0x08 TYPE=0x15, lire B8 ;
#         EXTRAIRE le blob du SEP = 40 o à +0x1c (offset CONFIRMÉ par la capture 000306_08_B.bin :
#         +0x14=0x15, +0x18=0x28). VÉRIFIER taille == 0x28, sinon STOP+dump (fail-closed).
#     (2) SPI : trame 0x72 = 80 72 00 2f 00 00 00 + 40 o → spi_relay(mesa, 0x72, blob) ; poll état 0x10 ;
#         demande 0x13 ; lecture. EXTRAIRE 40 o de réponse capteur (offset SPI_RESP_OFF, défaut 9 =
#         en-tête 80 d4 00 LL 00000000 <type>, comme l'identité). DUMPE toute la réponse SPI brute.
#     (3) sbio 0x16 : gabarit 000307_08_A.bin, INJECTER les 40 o du capteur à la place de la charge,
#         envoyer EP 0x08 TYPE=0x16, lire B8.
#     (4) VERDICT : le SEP ACQUITTE 0x16 (« < EP=0x08 TYPE=0x16 ») → relais MARCHÉ ; sinon STOP+dump.
#     (5) Si 0x16 acquitté → ENCHAÎNER la Phase 5 ; sinon STOP (fail-closed).
#   PHASE 5 — RELAIS compteur de séquence 0x42/0x18 (NOUVEAU ; même recette de relais que la Phase 4) :
#     (1) sbio 0x42 : gabarit 000309_08_A.bin (initializeSequenceCounter, charge vide), envoyer EP 0x08
#         TYPE=0x42, lire B8 ; EXTRAIRE le blob du SEP = 64 o à +0x1c (taille lue à +0x18 ; VÉRIFIÉE == 0x40
#         d'après la réponse 000310_08_B.bin + la trame SPI 80 73 00 47 VU C19). Sinon STOP+dump (fail-closed).
#     (2) SPI : trame 0x73 = 80 73 00 47 00 00 00 + 64 o → spi_relay(mesa, 0x73, blob) ; poll état 0x10
#         (attendu 0x4b=75) ; demande 0x13 ; lecture. EXTRAIRE 64 o de réponse capteur (offset SPI_RESP_OFF=9).
#     (3) sbio 0x18 : gabarit 000311_08_A.bin, INJECTER les 64 o du capteur à la place de la charge,
#         envoyer EP 0x08 TYPE=0x18, lire B8.
#     (4) VERDICT : le SEP ACQUITTE 0x18 (« < EP=0x08 TYPE=0x18 ») → relais compteur MARCHÉ ; sinon STOP+dump.
#     (5) Si 0x18 acquitté → ENCHAÎNER la Phase 6 ; sinon STOP (fail-closed).
#   PHASE 6 — RECON du patch 0x5f (comme sbio6) PUIS PUSH au capteur (NOUVEAU sbio7) :
#     (1) sbio 0x5f : gabarit 000313_08_A.bin (LoadPatch, entrée 2 o `02 00`), envoyer EP 0x08 TYPE=0x5f.
#     (2) RÉASSEMBLAGE multi-fragment (poignée fe/fd) : lire B8 (fragment 1, TAG=0xfc) ; tant que
#         offset+long < total (champs gt_packet : total @+0x04, offset @+0x08, long. fragment @+0x18, tous 32b),
#         RÉCLAMER la suite (envoyer EP 0x08 TAG=0xfe TYPE=0x5f, tampon A inchangé) et lire le fragment suivant
#         (dernier = TAG=0xfd). Recoller charge[+0x1c:+0x1c+long] à `offset`. Garde-fous : op==0x5f, fragments
#         DANS L'ORDRE (offset == longueur déjà reçue), nb de fragments borné (MAX_FRAGS), B8 assez grand.
#     (3) VÉRIF auto-vérifiante : len(patch) == total ET préfixe 2 o LE == total−2 (forme VU C12/C19). Sinon
#         STOP+dump (on ne devine pas). DUMPE chaque fragment brut + le patch réassemblé + la trame de push.
#     (4) PUSH (NOUVEAU) : lire l'état capteur 0x10 AVANT (baseline, dump) ; émettre le prélude
#         `80 60 00 07 00 00 00` (mesa.xfer, rx_len=0, 7 o) ; émettre le bloc patch 22158 o en UN xfer
#         (rx_len=0, timeout PATCH_PUSH_TIMEOUT_S ≈ 60 s) — remplissage FIFO le plus CONTINU possible (code
#         mesa_spi_proxy inchangé : fill dès qu'il y a de la place). Si le xfer lève/time-out → STOP+dump +
#         « FIFO ne tient pas 22 Ko → DMA SIO (sbio8) » (fail-closed, honnête).
#     (5) VÉRIF après push : lire l'état capteur 0x10 APRÈS (dump) ; écouter un court instant si le SEP enchaîne
#         (EP 0x08). VERDICT : status APRÈS bien formé (en-tête 80 20 00 10) → PUSH ÉMIS, status lisible (patch
#         = status only, pas de read-back) ; status illisible → push PROBABLEMENT cassé → DMA SIO (sbio8).
#     (6) STOP. On N'ENCHAÎNE PAS les params (0x5d…). Teardown capteur dans le finally EXTERNE, MÊME en cas
#         d'erreur (power_off power-cycle le capteur → récupère un éventuel état mi-patché). Fail-closed partout.
#
# RED LINES : aucune op disque sur le Mac, pas de dd/nvram/sudo/partition. Le store est un fichier sur CE PC.
#   m1n1 : lu, jamais modifié/poussé. Le SEP-write (boot IMG4 + SAVE-ack) = lancé par Albert (ce script, pending/).
#   On N'ENVOIE JAMAIS un SAVE vers sbio. Le key exchange 0x15/0x16, le compteur 0x42/0x18 et le patch 0x5f =
#   transport/réception d'octets opaques (aucun secret). Le PUSH va AU CAPTEUR (spi2), JAMAIS au SEP (0x12/0x13
#   jamais en écriture). On N'ENVOIE PAS la suite (params 0x5d…), ni commande blob/doigt. Capteur remis en état
#   d'iBoot (finally : power_off + restore) MÊME en cas d'erreur ou de push cassé.
#
# USAGE
#   SELFTEST=1 ./pending/sep_native_sbio7.sh   # hors-ligne : politique + 0x17 + gabarits 0x15/0x16/0x42/0x18/0x5f + trames 0x72/0x73 + réassemblage 0x5f + CONSTRUCTION+VÉRIF du push (rien émis). Ne touche pas le Mac.
#   ./tools/catch_proxy.sh                      # D'ABORD (Claude) : attrape le Mac en proxy (tu power-cycles)
#   ./pending/sep_native_sbio7.sh               # PUIS run RÉEL (Albert lance)
#   Vars : MAX_SAVES=48 | IDLE=25 | XART_STORE=<dir> | OS_UUID_MODE=fixed|none | SBIO_A=<0x73.bin> |
#          SBIO_0X17_TMPL=<gabarit 0x17> | SBIO_0X15_TMPL=<gabarit 0x15> | SBIO_0X16_TMPL=<gabarit 0x16> |
#          SBIO_0X42_TMPL=<gabarit 0x42> | SBIO_0X18_TMPL=<gabarit 0x18> | SBIO_0X5F_TMPL=<gabarit 0x5f> |
#          SBIO_STREAM15=0|1 | C12_OOL=<dir ool c12> | SPI_RESP_OFF=9 | WALL_LISTEN=4 | MAX_FRAGS=16 |
#          PATCH_PUSH_TIMEOUT_S=60 (timeout du xfer du bloc patch 22 Ko ; défaut 60 s)
#
# PRÉPARÉ PAR : Claude (Opus 4.8), 2026-11-22 — en-tête clair ci-dessus ; à lancer par Albert, backup+DFU prêts.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/../tools/env.sh"

export SELFTEST="${SELFTEST:-0}"
export OS_UUID_MODE="${OS_UUID_MODE:-fixed}"
export LINUX_OS_UUID="${LINUX_OS_UUID:-4c494e55580000000000000000000000}"
export MAX_SAVES="${MAX_SAVES:-48}"
export IDLE="${IDLE:-25}"
# Store SÉPARÉ, DISTINCT de sbio/sbio2/sbio3/sbio5/sbio6 ET de l'état précieux (xart_store_linux).
export XART_STORE="${XART_STORE:-$REPO_ROOT/xart_store_sbio7}"
# Poignée 0x73 rejouée OCTET POUR OCTET depuis la capture (pas de gt_packet construit à la main).
export SBIO_A="${SBIO_A:-$REPO_ROOT/traces/20261108-032454_c12-boot-ho/sep.log.ool/000300_08_A.bin}"
# Gabarit 0x17 (gt_packet EXACT de macOS, DONNÉES) : forme du prepareSession ; la charge = n° série capteur.
export SBIO_0X17_TMPL="${SBIO_0X17_TMPL:-$REPO_ROOT/traces/20261108-032454_c12-boot-ho/sep.log.ool/000303_08_A.bin}"
# Gabarits 0x15 / 0x16 (gt_packet EXACTS de macOS, DONNÉES = FORME uniquement) pour le key exchange.
#   0x15 : la charge = sessionType (01000000). 0x16 : la charge (40 o) est REMPLACÉE par la réponse LIVE du capteur.
export SBIO_0X15_TMPL="${SBIO_0X15_TMPL:-$REPO_ROOT/traces/20261108-032454_c12-boot-ho/sep.log.ool/000305_08_A.bin}"
export SBIO_0X16_TMPL="${SBIO_0X16_TMPL:-$REPO_ROOT/traces/20261108-032454_c12-boot-ho/sep.log.ool/000307_08_A.bin}"
# Gabarits 0x42 / 0x18 (gt_packet EXACTS de macOS, DONNÉES = FORME uniquement) pour le compteur de séquence.
#   0x42 : charge VIDE (initializeSequenceCounter). 0x18 : la charge (64 o) est REMPLACÉE par la réponse LIVE du capteur.
export SBIO_0X42_TMPL="${SBIO_0X42_TMPL:-$REPO_ROOT/traces/20261108-032454_c12-boot-ho/sep.log.ool/000309_08_A.bin}"
export SBIO_0X18_TMPL="${SBIO_0X18_TMPL:-$REPO_ROOT/traces/20261108-032454_c12-boot-ho/sep.log.ool/000311_08_A.bin}"
# Gabarit 0x5f (gt_packet EXACT de macOS, DONNÉES = FORME uniquement) pour le RECON du patch LoadPatch.
#   0x5f : entrée 2 o (`02 00`) relayée telle quelle ; la SORTIE (~22 Ko) est livrée par le SEP en fragments OOL.
export SBIO_0X5F_TMPL="${SBIO_0X5F_TMPL:-$REPO_ROOT/traces/20261108-032454_c12-boot-ho/sep.log.ool/000313_08_A.bin}"
# Référence c12 des fragments OOL du patch (SELFTEST : vérifie le réassemblage hors-ligne ; DONNÉES).
export C12_PATCH_FRAG1="${C12_PATCH_FRAG1:-$REPO_ROOT/traces/20261108-032454_c12-boot-ho/sep.log.ool/000314_08_B.bin}"
export C12_PATCH_FRAG2="${C12_PATCH_FRAG2:-$REPO_ROOT/traces/20261108-032454_c12-boot-ho/sep.log.ool/000316_08_B.bin}"
# Nombre MAX de fragments OOL acceptés au réassemblage du patch (garde-fou fail-closed).
export MAX_FRAGS="${MAX_FRAGS:-16}"
# Dossier des OOL EP 0x08 de la capture c12 (source des octets EXACTS rejoués / référence du mur = DONNÉES).
export C12_OOL="${C12_OOL:-$REPO_ROOT/traces/20261108-032454_c12-boot-ho/sep.log.ool}"
# Racine du repo, pour importer analysis.mesa_spi_proxy (brique SPI capteur réutilisable).
export ANALYSIS_PARENT="${ANALYSIS_PARENT:-$REPO_ROOT}"
# Option diagnostic (défaut 0) : programmer AUSSI le stream 15 du dart-sep côté AP (aucune écriture SEP).
export SBIO_STREAM15="${SBIO_STREAM15:-0}"
# Offset de la charge (40 o) dans la réponse SPI 0x72 : best-effort (9 = en-tête 80 d4 00 LL 00000000 <type>,
#   comme l'identité). Le parsing d'enveloppe SPI n'est pas 100% reversé (sbio_keyexchange.md §8) : l'ACK 0x16 tranche.
export SPI_RESP_OFF="${SPI_RESP_OFF:-9}"
# Durée d'écoute au mur (dump).
export WALL_LISTEN="${WALL_LISTEN:-4}"
# Timeout (s) du xfer SPI qui ÉMET le bloc patch (~22 Ko) : le défaut mesa (2 s) est trop court pour ~1400
#   cycles FIFO sur lien distant. 60 s = marge confortable ; au-delà on conclut « FIFO ne tient pas » (sbio8).
export PATCH_PUSH_TIMEOUT_S="${PATCH_PUSH_TIMEOUT_S:-60}"
export M1N1_PROXYCLIENT="$M1N1_DIR/proxyclient"
mkdir -p "$XART_STORE"

if [ "$SELFTEST" != 1 ]; then
  [ -f "$M1N1_DIR/build/m1n1.bin" ] || die "m1n1 non compilé : ./tools/build_m1n1.sh"
  STAMP="$(date +%Y%m%d-%H%M%S)"; OUT="$TRACES_DIR/${STAMP}_native_sbio7"; mkdir -p "$OUT"; export OUT
  # Le Mac doit DÉJÀ être en proxy : lancer ./tools/catch_proxy.sh AVANT (Claude le fait + power-cycle).
  require_mac
fi

timeout 480 "$M1N1_PYTHON" - <<'PY' 2>&1 | tee "${OUT:-/tmp}/native_sbio7.log"
import os, sys, time, struct, glob
SELFTEST = os.environ["SELFTEST"] == "1"
OS_UUID_MODE = os.environ.get("OS_UUID_MODE", "fixed")
LINUX_OS_UUID = bytes.fromhex(os.environ["LINUX_OS_UUID"])
MAX_SAVES = int(os.environ.get("MAX_SAVES", "48"))
IDLE = int(os.environ.get("IDLE", "25"))
XART_STORE = os.environ["XART_STORE"]
SBIO_A = os.environ.get("SBIO_A", "")
SBIO_0X17_TMPL = os.environ.get("SBIO_0X17_TMPL", "")
SBIO_0X15_TMPL = os.environ.get("SBIO_0X15_TMPL", "")
SBIO_0X16_TMPL = os.environ.get("SBIO_0X16_TMPL", "")
SBIO_0X42_TMPL = os.environ.get("SBIO_0X42_TMPL", "")
SBIO_0X18_TMPL = os.environ.get("SBIO_0X18_TMPL", "")
SBIO_0X5F_TMPL = os.environ.get("SBIO_0X5F_TMPL", "")
C12_PATCH_FRAG1 = os.environ.get("C12_PATCH_FRAG1", "")
C12_PATCH_FRAG2 = os.environ.get("C12_PATCH_FRAG2", "")
C12_OOL = os.environ.get("C12_OOL", "")
SBIO_STREAM15 = os.environ.get("SBIO_STREAM15", "0") == "1"
SPI_RESP_OFF = int(os.environ.get("SPI_RESP_OFF", "9"))
WALL_LISTEN = int(os.environ.get("WALL_LISTEN", "4"))
MAX_FRAGS = int(os.environ.get("MAX_FRAGS", "16"))
PATCH_PUSH_TIMEOUT_S = float(os.environ.get("PATCH_PUSH_TIMEOUT_S", "60"))  # timeout du xfer du bloc patch 22 Ko
KX_BLOB_LEN = 0x28           # longueur du blob key-exchange (40 o) : SEP 0x15/0x16 ET charge SPI 0x72 (VU c12)
CNT_BLOB_LEN = 0x40          # longueur du blob compteur (64 o) : SEP 0x42/0x18 ET charge SPI 0x73 (VU C19 + 000310_08_B.bin)
CNT_PENDING = 0x4b           # longueur attendue de la reponse SPI 0x73 (75 o) au poll d'etat (VU C19) ; indicatif (log)
PATCH_OP = 0x5f              # LoadPatch : le SEP livre un patch ~22 Ko a l'AP en fragments OOL (VU C12 seq 313-316 / C19)
PATCH_PRELUDE = bytes.fromhex("80600007000000")  # prelude SPI du push (80 60 00 07 00 00 00) : VU C19 avant le bloc de 22 Ko
# Poignee de livraison multi-fragment (TAG mailbox) : VU C12/C19.
PATCH_TAG_FRAG = 0xfc        # 1er fragment (et fragments intermediaires) : SEP -> AP
PATCH_TAG_MORE = 0xfe        # AP -> SEP : "donne le fragment suivant" (tampon A inchange)
PATCH_TAG_LAST = 0xfd        # dernier fragment : SEP -> AP (DATA=0x00010000)

def build_spi_frame(cmd_opcode, blob):
    """Construit la trame SPI capteur : en-tete 80 <cmd> <LL 16b BE> 00 00 00 + blob, ou LL = TAILLE TOTALE
    (7 + len(blob)), PAS la taille de la charge (regle VU macOS C19, sbio_keyexchange.md §9 / sbio_session.md §1).
    SEUL l'opcode de commande (0x72 KX / 0x73 compteur) est fixe ; la LONGUEUR vient de len(blob), pas codee en dur."""
    total = 7 + len(blob)
    return bytes([0x80, cmd_opcode & 0xff]) + struct.pack(">H", total) + b"\x00\x00\x00" + bytes(blob)

def parse_frag_header(buf):
    """Lit l'en-tete gt_packet d'un FRAGMENT de transfert (VU C12 seq 314/316). Rend un dict :
    kind(@+0x00), total(@+0x04), offset(@+0x08), op(@+0x14), fraglen(@+0x18) — tous 32b petit-boutiste —
    et la tranche de charge payload = buf[0x1c:0x1c+fraglen]. Aucune interpretation du contenu (octets opaques)."""
    if len(buf) < GT_PAYLOAD:
        raise ValueError(f"fragment trop court ({len(buf)} o < {GT_PAYLOAD})")
    kind   = struct.unpack_from("<I", buf, GT_KIND)[0]
    total  = struct.unpack_from("<I", buf, GT_TOTAL)[0]
    offset = struct.unpack_from("<I", buf, GT_OFFSET)[0]
    op     = struct.unpack_from("<I", buf, GT_OP)[0] & 0xff
    fraglen = struct.unpack_from("<I", buf, GT_LEN)[0]
    if GT_PAYLOAD + fraglen > len(buf):
        raise ValueError(f"fragment incoherent : charge {fraglen} o depasse le tampon ({len(buf)} o)")
    return {"kind": kind, "total": total, "offset": offset, "op": op, "fraglen": fraglen,
            "payload": bytes(buf[GT_PAYLOAD:GT_PAYLOAD + fraglen])}

def verify_reassembled_patch(reasm, total):
    """VERDICT auto-verifiant du RECON (forme VU C12/C19) : le patch reassemble doit faire exactement `total`
    octets ET commencer par un prefixe 2 o petit-boutiste == total-2 (`8c 56 ..` = 0x568c pour total 0x568e).
    Rend (ok, raison)."""
    if len(reasm) != total:
        return False, f"len reassemble {len(reasm)} != total declare {total}"
    if len(reasm) < 2:
        return False, "patch trop court (<2 o)"
    pre = struct.unpack_from("<H", reasm, 0)[0]
    if pre != (total - 2) & 0xffff:
        return False, f"prefixe LE 0x{pre:x} != total-2 0x{(total-2)&0xffff:x}"
    return True, "OK"

# Racine du repo sur sys.path pour importer la brique SPI capteur (import OFFLINE-safe : m1n1/time y sont
# importés paresseusement, dans les méthodes ; l'import du module n'ouvre aucun matériel).
sys.path.insert(0, os.environ.get("ANALYSIS_PARENT", "."))

OP_FWBOOT, OP_OSUUID, OP_FETCH_MASTER, OP_FETCH_GL = 0x0e, 0x13, 0x00, 0x05
OP_ABSENT, OP_ANNOUNCE, OP_SAVE_XART, OP_SAVE_LOCKER = 0x07, 0x1d, 0x01, 0x06
RESP_DONE, RESP_ANNOUNCE = 0x00, 0x16
ACK_MASK = 0xFFFFFF00
OPNAME = {OP_FWBOOT:"fw-boot", OP_OSUUID:"os-uuid", OP_FETCH_MASTER:"FETCH-maître",
          OP_FETCH_GL:"FETCH-locker", OP_ABSENT:"absent(SEP)", OP_ANNOUNCE:"annonce-EP",
          OP_SAVE_XART:"SAVE-xART", OP_SAVE_LOCKER:"SAVE-locker"}

# Offsets gt_packet_t (vérifié, docs/messages.md §SBIO) : +0x14 = opcode, +0x18 = longueur de charge, +0x1c = charge.
GT_OP, GT_LEN, GT_PAYLOAD = 0x14, 0x18, 0x1c
# Champs d'en-tete pour le TRANSFERT FRAGMENTE (GenericTransfer, VU C12 seq 314/316 ; docs/sbio_match.md §2) :
#   +0x00 kind(=1), +0x04 TOTAL (taille complete, 32b LE), +0x08 OFFSET du fragment (32b LE), +0x18 = longueur
#   DE CE FRAGMENT (32b LE pour les gros blobs, pas 1 octet). La charge du fragment est a +0x1c.
GT_KIND, GT_TOTAL, GT_OFFSET = 0x00, 0x04, 0x08
X17_PAYLEN = 0x10            # longueur de la charge du 0x17 = 16 octets (n° de série capteur), VU c12
SERIAL_SLICE = slice(9, 25)  # dans la trame d'identité capteur (80 d4 00 1b 0000 0000 70 <16o série> 75 76)

def declen(param, data): return (param & 0xFF) | ((data & 0xFF) << 8)

# ---------------------------------------------------------------------------
# LISTE ORDONNÉE des commandes sbio APRÈS le 0x73 (docs/sbio_sequence.md §1.1 + trace c12, seq 303+).
#   (opcode, classe, nom, ool_A, ool_B). CLASSES : "AP"/"SEP" = rejouables ; "SPI"/"BLOB"/"FINGER" = MUR.
# L'index 0 (0x17) est FRANCHI SPÉCIALEMENT par la Phase 3 (série capteur lue en direct). Le déroulé
# post-0x17 reprend à l'index 1 : la carte c12 y place 0x15 [SPI] = le MUR SUIVANT (lockstep chiffré).
POST_0X73_STEPS = [
    # --- §1.1 : init + 1re passe capteur ---
    (0x17, "SPI", "prepareSession — n° serie capteur lu sur SPI", "000303_08_A.bin", "000304_08_B.bin"),
    (0x15, "SPI", "performKeyExchange (sessionType=1)",            "000305_08_A.bin", "000306_08_B.bin"),
    (0x16, "SPI", "performKeyExchange (2) — reponse capteur",      "000307_08_A.bin", "000308_08_B.bin"),
    (0x42, "SPI", "initializeSequenceCounter",                     "000309_08_A.bin", "000310_08_B.bin"),
    (0x18, "SPI", "compteur (reponse capteur)",                    "000311_08_A.bin", "000312_08_B.bin"),
    (0x5f, "SPI", "LoadPatch (patch capteur, OOL ~16Ko)",          "000313_08_A.bin", None),
    (0x5d, "SPI", "applySensorParams",                             None, None),
    (0x5c, "SPI", "applySensorParams (suite)",                     None, None),
    (0x6a, "SPI", "applySensorParams (suite)",                     None, None),
    (0x31, "SPI", "n0 serie module",                               None, None),
    (0x32, "SPI", "n0 serie module (2)",                           None, None),
    (0x01, "SPI", "fin loadPatch (etat capteur=3)",                None, None),
    (0x1f, "SEP", "cacheMatchPolicy",                              None, None),
    (0x31, "SPI", "n0 serie module (repete)",                      None, None),
    (0x32, "SPI", "n0 serie module (2, repete)",                   None, None),
    (0x5b, "BLOB","setCalibrationData (~64Ko)",                    None, None),
    # --- §1.2/§1.3 : tout ce qui suit est APRÈS d'autres murs [SPI]/[BLOB] (cf. sbio_sequence.md). ---
]

# --- store xART sbio3 sur CE PC : maîtres par type (1/2), gigalockers par UUID + dump brut ---
store_masters = {}
store_gls = {}
def store_load():
    for f in glob.glob(os.path.join(XART_STORE, "master_*.bin")):
        t = int(os.path.basename(f)[7:-4]); store_masters[t] = open(f, "rb").read()
    for f in glob.glob(os.path.join(XART_STORE, "gl_*.bin")):
        uuid = bytes.fromhex(os.path.basename(f)[3:-4]); store_gls[uuid] = open(f, "rb").read()
def store_put_master(t, blob):
    store_masters[t] = blob; open(os.path.join(XART_STORE, f"master_{t}.bin"), "wb").write(blob)
def store_put_gl(uuid, blob):
    store_gls[uuid] = blob; open(os.path.join(XART_STORE, f"gl_{uuid.hex()}.bin"), "wb").write(blob)

def _read_file(pth):
    return open(pth, "rb").read() if (pth and os.path.exists(pth)) else None

if SELFTEST:
    print("--- SELFTEST (hors-ligne, le Mac et le capteur ne sont PAS touches) ---", flush=True)
    print(f"store xART sbio7 : {XART_STORE}  (maitres={len(glob.glob(os.path.join(XART_STORE,'master_*.bin')))}, "
          f"gl={len(glob.glob(os.path.join(XART_STORE,'gl_*.bin')))})  [SEPARE de xart_store_linux/sbio/sbio2/sbio3/sbio4/sbio5/sbio6]", flush=True)
    print("PHASE 1 — politique native PERSIST (identique a sep_native_sbio3.sh) :", flush=True)
    print("  fw-boot/os-uuid/annonce/absent-SEP : ack ; FETCH : SERVIR si store sinon ABSENT ;", flush=True)
    print(f"  SAVE 0x01/0x06 : lire B, STOCKER, ACK (DATA&0xffffff00)  !! ECRITURE  (budget {MAX_SAVES})", flush=True)
    print(f"  boucle jusqu'a idle ({IDLE}s de silence) ; fail-closed sur op inconnue", flush=True)
    assert OS_UUID_MODE in ("fixed", "none") and len(LINUX_OS_UUID) == 16

    print("PHASE 2 — sonde sbio 0x73 (identique a sep_native_sbio2.sh, seulement si idle ET 0x08 annonce) :", flush=True)
    b = _read_file(SBIO_A)
    if b is None:
        print(f"  ERREUR — fichier SBIO_A introuvable : {SBIO_A!r}.", flush=True); raise SystemExit(1)
    assert len(b) > GT_OP, f"SBIO_A trop court ({len(b)} o)"
    assert b[0x00] == 1, f"SBIO_A +0x00={b[0x00]} (attendu 1)"
    assert b[GT_OP] == 0x73, f"SBIO_A +0x14={b[GT_OP]:#x} (attendu 0x73)"
    print(f"  SBIO_A verifie : {os.path.basename(SBIO_A)} = gt_packet 0x73 valide (+0x00=1, +0x14=0x73).", flush=True)

    print("PHASE 3 — FRANCHIR 0x17 (NOUVEAU) : lire l'identite capteur SUR SPI (live) et la servir au SEP.", flush=True)
    # (a) le gabarit 0x17 de la capture c12 : forme EXACTE + charge = n° serie capteur.
    tmpl = _read_file(SBIO_0X17_TMPL)
    if tmpl is None:
        print(f"  ERREUR — gabarit 0x17 introuvable : {SBIO_0X17_TMPL!r}.", flush=True); raise SystemExit(1)
    assert len(tmpl) >= GT_PAYLOAD + X17_PAYLEN, f"gabarit 0x17 trop court ({len(tmpl)} o)"
    assert tmpl[GT_OP] == 0x17, f"gabarit +0x14=0x{tmpl[GT_OP]:02x} (attendu 0x17)"
    assert tmpl[GT_LEN] == X17_PAYLEN, f"gabarit +0x18=0x{tmpl[GT_LEN]:02x} (attendu 0x{X17_PAYLEN:02x})"
    charge = tmpl[GT_PAYLOAD:GT_PAYLOAD + X17_PAYLEN]
    print(f"  gabarit 0x17 verifie : {os.path.basename(SBIO_0X17_TMPL)} ({len(tmpl)}o) "
          f"+0x14=0x17 +0x18=0x{X17_PAYLEN:02x} ; charge (serie, 16o) = {charge.hex()}", flush=True)
    # (b) import de la brique SPI capteur + coherence charge == identite attendue.
    try:
        from analysis.mesa_spi_proxy import MesaSPI, ID_EXPECTED, MesaError
    except Exception as e:
        print(f"  ERREUR — import de analysis.mesa_spi_proxy impossible : {e}", flush=True); raise SystemExit(1)
    expected_serial = ID_EXPECTED[SERIAL_SLICE]
    print(f"  import MesaSPI OK ; identite connue ID_EXPECTED ({len(ID_EXPECTED)}o) = {ID_EXPECTED.hex()}", flush=True)
    print(f"  serie attendue (ID_EXPECTED[9:25]) = {expected_serial.hex()}", flush=True)
    assert charge == expected_serial, (f"charge du gabarit 0x17 ({charge.hex()}) != serie capteur connue "
                                       f"({expected_serial.hex()})")
    print("  >>> COHERENCE OK : la charge du 0x17 (c12) == le n° de serie que le capteur annonce "
          "(mesa_spi_proxy.read_id). Le run LIRA cette serie EN DIRECT et la servira telle quelle.", flush=True)
    print("  Plan Phase 3 : MesaSPI(iface,p,u) -> power_on() -> read_id() -> serie[9:25] ; VERIFIER == gabarit ;", flush=True)
    print("    ecrire gabarit+serie-live dans A8 ; envoyer EP 0x08 TAG=0xfc TYPE=0x17 ; lire/dumper B8 + faute DART.", flush=True)
    print("    EXCEPTION sbio4 : capteur reste ALIMENTE (pas de power_off) ; teardown dans le finally EXTERNE (apres Phase 4).", flush=True)

    print("PHASE 4 — RELAIS key exchange 0x15/0x16 (NOUVEAU) : l'AP = PUR RELAIS d'octets (docs/sbio_keyexchange.md).", flush=True)
    # (1) gabarit 0x15 : sessionType=1 ; sa reponse SEP = blob opaque 40 o.
    t15 = _read_file(SBIO_0X15_TMPL)
    if t15 is None:
        print(f"  ERREUR — gabarit 0x15 introuvable : {SBIO_0X15_TMPL!r}.", flush=True); raise SystemExit(1)
    assert len(t15) >= GT_PAYLOAD + 4, f"gabarit 0x15 trop court ({len(t15)} o)"
    assert t15[GT_OP] == 0x15, f"gabarit 0x15 +0x14=0x{t15[GT_OP]:02x} (attendu 0x15)"
    assert t15[GT_LEN] == 0x04, f"gabarit 0x15 +0x18=0x{t15[GT_LEN]:02x} (attendu 0x04)"
    st15 = t15[GT_PAYLOAD:GT_PAYLOAD + 4]
    assert st15 == bytes.fromhex("01000000"), f"gabarit 0x15 sessionType={st15.hex()} (attendu 01000000)"
    print(f"  gabarit 0x15 verifie : {os.path.basename(SBIO_0X15_TMPL)} ({len(t15)}o) +0x14=0x15 +0x18=0x04 "
          f"sessionType={st15.hex()}", flush=True)
    # (2) gabarit 0x16 : la charge (40 o) sera REMPLACEE par la reponse LIVE du capteur.
    t16 = _read_file(SBIO_0X16_TMPL)
    if t16 is None:
        print(f"  ERREUR — gabarit 0x16 introuvable : {SBIO_0X16_TMPL!r}.", flush=True); raise SystemExit(1)
    assert len(t16) >= GT_PAYLOAD + KX_BLOB_LEN, f"gabarit 0x16 trop court ({len(t16)} o)"
    assert t16[GT_OP] == 0x16, f"gabarit 0x16 +0x14=0x{t16[GT_OP]:02x} (attendu 0x16)"
    assert t16[GT_LEN] == KX_BLOB_LEN, f"gabarit 0x16 +0x18=0x{t16[GT_LEN]:02x} (attendu 0x{KX_BLOB_LEN:02x})"
    print(f"  gabarit 0x16 verifie : {os.path.basename(SBIO_0X16_TMPL)} ({len(t16)}o) +0x14=0x16 "
          f"+0x18=0x{KX_BLOB_LEN:02x} (charge 40 o remplacee a l'execution)", flush=True)
    # (3) reference : la reponse SEP 0x15 capturee confirme offset+taille du blob (pas une supposition).
    rb15 = _read_file(os.path.join(C12_OOL, "000306_08_B.bin"))
    if rb15 is not None and len(rb15) > GT_LEN:
        assert rb15[GT_OP] == 0x15 and rb15[GT_LEN] == KX_BLOB_LEN, (
            f"ref 000306_08_B.bin inattendue (+0x14=0x{rb15[GT_OP]:02x} +0x18=0x{rb15[GT_LEN]:02x})")
        print(f"  reference 000306_08_B.bin : reponse SEP 0x15 = +0x14=0x15 +0x18=0x{KX_BLOB_LEN:02x} ; "
              f"blob 40 o @ +0x1c = {rb15[GT_PAYLOAD:GT_PAYLOAD+KX_BLOB_LEN].hex()} (offset CONFIRME par capture).", flush=True)
    # (4) construction de la trame SPI 0x72 = en-tete 7 o + 40 o = 47 o (0x2f), sans toucher au capteur.
    kx_frame = bytes.fromhex("8072002f000000") + bytes(KX_BLOB_LEN)   # longueur d'en-tete = TOTALE (0x2f=47), pas la charge
    assert len(kx_frame) == 0x2f, f"trame 0x72 = {len(kx_frame)} o (attendu 0x2f=47)"
    assert kx_frame[:7].hex() == "8072002f000000", "en-tete 0x72 incorrect (longueur TOTALE 0x2f, VU macOS C19)"
    print(f"  trame 0x72 construite (a blanc) : en-tete {kx_frame[:7].hex()} + 40 o = {len(kx_frame)} o (0x2f). OK.", flush=True)
    print(f"  offset d'extraction de la charge SPI (SPI_RESP_OFF) = {SPI_RESP_OFF} (best-effort ; l'ACK 0x16 tranche).", flush=True)
    print("  Plan Phase 4 : 0x15 -> B8 (blob 40 o @ +0x1c) -> SPI 0x72 (poll etat, 0x13, lecture) -> 40 o capteur ", flush=True)
    print("    -> 0x16 (charge=40 o capteur) -> VERDICT : ACK 0x16 = relais MARCHE ; sinon STOP+dump. Puis ENCHAINE Phase 5.", flush=True)

    print("PHASE 5 — RELAIS compteur de sequence 0x42/0x18 (NOUVEAU) : meme recette de relais que la Phase 4.", flush=True)
    # (1) gabarit 0x42 : initializeSequenceCounter, charge VIDE (+0x18=0x00) ; sa reponse SEP = blob opaque 64 o.
    t42 = _read_file(SBIO_0X42_TMPL)
    if t42 is None:
        print(f"  ERREUR — gabarit 0x42 introuvable : {SBIO_0X42_TMPL!r}.", flush=True); raise SystemExit(1)
    assert len(t42) > GT_LEN, f"gabarit 0x42 trop court ({len(t42)} o)"
    assert t42[GT_OP] == 0x42, f"gabarit 0x42 +0x14=0x{t42[GT_OP]:02x} (attendu 0x42)"
    print(f"  gabarit 0x42 verifie : {os.path.basename(SBIO_0X42_TMPL)} ({len(t42)}o) +0x14=0x42 "
          f"+0x18=0x{t42[GT_LEN]:02x} (charge d'entree vide).", flush=True)
    # (2) gabarit 0x18 : la charge (64 o) sera REMPLACEE par la reponse LIVE du capteur.
    t18 = _read_file(SBIO_0X18_TMPL)
    if t18 is None:
        print(f"  ERREUR — gabarit 0x18 introuvable : {SBIO_0X18_TMPL!r}.", flush=True); raise SystemExit(1)
    assert len(t18) >= GT_PAYLOAD + CNT_BLOB_LEN, f"gabarit 0x18 trop court ({len(t18)} o)"
    assert t18[GT_OP] == 0x18, f"gabarit 0x18 +0x14=0x{t18[GT_OP]:02x} (attendu 0x18)"
    assert t18[GT_LEN] == CNT_BLOB_LEN, f"gabarit 0x18 +0x18=0x{t18[GT_LEN]:02x} (attendu 0x{CNT_BLOB_LEN:02x})"
    print(f"  gabarit 0x18 verifie : {os.path.basename(SBIO_0X18_TMPL)} ({len(t18)}o) +0x14=0x18 "
          f"+0x18=0x{CNT_BLOB_LEN:02x} (charge 64 o remplacee a l'execution).", flush=True)
    # (3) reference : la reponse SEP 0x42 capturee confirme offset+taille du blob (pas une supposition).
    rb42 = _read_file(os.path.join(C12_OOL, "000310_08_B.bin"))
    if rb42 is not None and len(rb42) > GT_LEN:
        assert rb42[GT_OP] == 0x42 and rb42[GT_LEN] == CNT_BLOB_LEN, (
            f"ref 000310_08_B.bin inattendue (+0x14=0x{rb42[GT_OP]:02x} +0x18=0x{rb42[GT_LEN]:02x})")
        print(f"  reference 000310_08_B.bin : reponse SEP 0x42 = +0x14=0x42 +0x18=0x{CNT_BLOB_LEN:02x} ; "
              f"blob 64 o @ +0x1c (offset CONFIRME par capture).", flush=True)
    # (4) construction de la trame SPI 0x73 = en-tete 7 o + 64 o = 71 o (0x47), via la MEME fonction spi_relay.
    cnt_frame = build_spi_frame(0x73, bytes(CNT_BLOB_LEN))   # 80 73 <7+64 BE> 000000 + 64 o
    assert len(cnt_frame) == 0x47, f"trame 0x73 = {len(cnt_frame)} o (attendu 0x47=71)"
    assert cnt_frame[:7].hex() == "80730047000000", "en-tete 0x73 incorrect (longueur TOTALE 0x47, VU macOS C19)"
    # non-regression : la factorisation reproduit EXACTEMENT la trame 0x72 d'origine de la Phase 4.
    kx_frame_gen = build_spi_frame(0x72, bytes(KX_BLOB_LEN))
    assert kx_frame_gen.hex() == ("8072002f000000" + "00" * KX_BLOB_LEN), "regression : build_spi_frame(0x72) != trame sbio4"
    print(f"  trame 0x73 construite (a blanc) via build_spi_frame : en-tete {cnt_frame[:7].hex()} + 64 o = {len(cnt_frame)} o (0x47). OK.", flush=True)
    print("  non-regression : build_spi_frame(0x72) reproduit la trame sbio4 (80 72 00 2f ...). OK.", flush=True)
    print(f"  poll d'etat 0x73 attendu = 0x{CNT_PENDING:02x}=75 (VU C19) ; charge capteur a extraire = 64 o @ offset {SPI_RESP_OFF}.", flush=True)
    print("  Plan Phase 5 : 0x42 -> B8 (blob 64 o @ +0x1c, taille lue a +0x18) -> SPI 0x73 (poll etat, 0x13, lecture) ", flush=True)
    print("    -> 64 o capteur -> 0x18 (charge=64 o capteur) -> VERDICT : ACK 0x18 = relais compteur MARCHE ; sinon STOP+dump.", flush=True)
    print("    Si 0x18 acquitte -> ENCHAINE la Phase 6 (patch 0x5f : RECON + PUSH au capteur).", flush=True)

    print("PHASE 6 — RECON du patch 0x5f (comme sbio6) PUIS PUSH au capteur (NOUVEAU sbio7) : recevoir+reassembler, puis EMETTRE le push.", flush=True)
    # (1) gabarit 0x5f : LoadPatch, entree 2 o relayee telle quelle.
    t5f = _read_file(SBIO_0X5F_TMPL)
    if t5f is None:
        print(f"  ERREUR — gabarit 0x5f introuvable : {SBIO_0X5F_TMPL!r}.", flush=True); raise SystemExit(1)
    assert len(t5f) > GT_LEN, f"gabarit 0x5f trop court ({len(t5f)} o)"
    assert t5f[GT_OP] == PATCH_OP, f"gabarit 0x5f +0x14=0x{t5f[GT_OP]:02x} (attendu 0x{PATCH_OP:02x})"
    print(f"  gabarit 0x5f verifie : {os.path.basename(SBIO_0X5F_TMPL)} ({len(t5f)}o) +0x14=0x{PATCH_OP:02x} "
          f"+0x18=0x{t5f[GT_LEN]:02x} (entree {t5f[GT_LEN]} o = {t5f[GT_PAYLOAD:GT_PAYLOAD+t5f[GT_LEN]].hex()}).", flush=True)
    # (2) VERIF HORS-LIGNE du reassemblage sur les fragments c12 REELS (000314_08_B + 000316_08_B) : on exerce
    #     EXACTEMENT la logique de la Phase 6 (parse_frag_header + recollage + verdict), sur des octets VU.
    f1 = _read_file(C12_PATCH_FRAG1); f2 = _read_file(C12_PATCH_FRAG2)
    if f1 is None or f2 is None:
        print(f"  (reference fragments c12 absente : {C12_PATCH_FRAG1!r} / {C12_PATCH_FRAG2!r} — verif hors-ligne sautee)", flush=True)
    else:
        reasm = bytearray(); total = None; frags = 0
        for tag, buf in ((PATCH_TAG_FRAG, f1), (PATCH_TAG_LAST, f2)):
            h = parse_frag_header(buf); frags += 1
            assert h["op"] == PATCH_OP and h["kind"] == 1, f"fragment c12 : op=0x{h['op']:02x} kind={h['kind']}"
            if total is None: total = h["total"]
            assert h["total"] == total, f"total incoherent entre fragments ({h['total']} != {total})"
            assert h["offset"] == len(reasm), f"fragment hors ordre : offset={h['offset']} attendu {len(reasm)}"
            reasm += h["payload"]
        ok, why = verify_reassembled_patch(reasm, total)
        assert ok, f"reassemblage c12 INVALIDE : {why}"
        assert len(reasm) == 22158, f"patch c12 reassemble = {len(reasm)} o (attendu 22158)"
        assert reasm[:4].hex() == "8c563a00", f"tete patch c12 = {reasm[:4].hex()} (attendu 8c563a00)"
        print(f"  VERIF reassemblage (fragments c12 REELS, {frags} frags) : {len(reasm)} o = total 0x{total:x} ; "
              f"prefixe/tete OK (tete={reasm[:4].hex()}). La logique Phase 6 recolle le patch correctement.", flush=True)
        # (3) la trame SPI de push qu'on EMETTRA : prelude + bloc brut. On VERIFIE sa construction (sans emettre).
        assert PATCH_PRELUDE.hex() == "80600007000000", "prelude SPI 0x60 incorrect (attendu 80 60 00 07 00 00 00)"
        block = bytes(reasm)
        push = PATCH_PRELUDE + block
        assert len(push) == 7 + len(block), "trame de push mal formee"
        assert push[:7] == PATCH_PRELUDE and push[7:] == block, "push != prelude(7 o) + bloc patch"
        assert len(block) == 22158, f"bloc patch = {len(block)} o (attendu 22158)"
        print(f"  trame de push CONSTRUITE (a blanc, NON EMISE en selftest) : prelude {PATCH_PRELUDE.hex()} (7 o) + "
              f"bloc {len(block)} o = {len(push)} o. Le run REEL l'emet (prelude puis bloc, rx_len=0).", flush=True)
    # (3b) VERIF de la LOGIQUE de verdict du push (sans matériel) : un etat capteur bien forme (en-tete
    #      80 20 00 10) => push emis/lisible ; un etat sans cet en-tete => casse. On exerce le predicat.
    try:
        from analysis.mesa_spi_proxy import STATUS_HEAD, MesaSPI
        import inspect as _inspect
    except Exception as e:
        print(f"  ERREUR — import STATUS_HEAD/MesaSPI impossible : {e}", flush=True); raise SystemExit(1)
    assert STATUS_HEAD.hex() == "80200010", f"STATUS_HEAD={STATUS_HEAD.hex()} (attendu 80200010)"
    def _push_verdict(st):   # meme predicat que la Phase 6 (run reel)
        return st is not None and len(st) >= 4 and st[:4] == STATUS_HEAD
    st_ok  = STATUS_HEAD + bytes(12)                  # etat bien forme (16 o) -> push lisible
    st_bad = bytes.fromhex("deadbeef") + bytes(12)    # en-tete casse -> push probablement casse
    assert _push_verdict(st_ok) is True,  "verdict push : un etat bien forme doit etre accepte"
    assert _push_verdict(st_bad) is False, "verdict push : un etat sans en-tete 80200010 doit etre rejete"
    assert _push_verdict(None) is False and _push_verdict(b"\x80\x20") is False, "verdict push : None/tronque -> rejete"
    # (3c) le xfer de mesa_spi_proxy accepte bien le timeout (gros push) sans casser la retro-compat.
    _sig = _inspect.signature(MesaSPI.xfer)
    assert "timeout" in _sig.parameters and _sig.parameters["timeout"].default is None, \
        "MesaSPI.xfer doit accepter timeout=None (retro-compat sbio4/5/6)"
    print(f"  verdict push VERIFIE (predicat en-tete 80 20 00 10) ; MesaSPI.xfer(timeout=) OK (defaut={PATCH_PUSH_TIMEOUT_S:.0f}s, rx_len=0 pour le push).", flush=True)
    print(f"  garde-fou : B8 (0x4000) contient UN fragment (charge <= 0x3fe4) ; MAX_FRAGS={MAX_FRAGS}. "
          "Le >16 Ko passe par la poignee fe/fd (B8 PAS a agrandir ; corrige l'hypothese 'trop petit').", flush=True)
    print("  Plan Phase 6 : 0x5f -> reassembler (fc.. puis fe->fd) -> verifier (len==total, prefixe) -> DUMPER patch ", flush=True)
    print("    -> etat capteur AVANT -> EMETTRE prelude 0x60 puis le bloc 22Ko (rx_len=0, timeout) -> etat capteur APRES ", flush=True)
    print("    -> VERDICT (en-tete 80 20 00 10 = lisible, sinon casse -> DMA SIO sbio8) -> STOP (pas de params 0x5d). ", flush=True)
    print("  ⚠️ CS-HOLD (22 Ko FIFO) NON testable hors-ligne : code au plus continu + timeout, risque reel documente.", flush=True)

    print("  LISTE ORDONNEE post-0x73 (source: sbio_sequence.md §1 + trace c12) :", flush=True)
    for i, (op, cls, name, oa, ob) in enumerate(POST_0X73_STEPS):
        if i == 0:
            act = "FRANCHI (P3)"
        elif op in (0x15, 0x16):
            act = "RELAIS (P4)"
        elif op in (0x42, 0x18):
            act = "RELAIS (P5)"
        elif op == 0x5f:
            act = "PUSH (P6)"
        elif cls in ("SPI", "BLOB", "FINGER"):
            act = "MUR (apres)"
        else:
            act = "n/a"
        ref = ""
        if oa:
            exists = os.path.exists(os.path.join(C12_OOL, oa)) if C12_OOL else False
            ref = f"  [ref A={oa}{' OK' if exists else ' ABSENT'}]"
        print(f"    #{i:2d}  op=0x{op:02x}  [{cls:6s}]  {act:12s}  {name}{ref}", flush=True)
    print(f"  ecoute au mur = {WALL_LISTEN}s. Apres le PUSH du patch (prelude 0x60 + bloc 22Ko emis en FIFO scrute), "
          "on lit l'etat capteur, on rend le VERDICT, et on S'ARRETE (params 0x5d... NON envoyes ce run).", flush=True)
    print("SELFTEST OK (rien envoye au SEP ni au capteur ; construction + verdict du push verifies hors-ligne).", flush=True)
    sys.exit(0)

sys.path.insert(0, os.environ["M1N1_PROXYCLIENT"])
from m1n1.proxy import UartInterface, M1N1Proxy
from m1n1.proxyutils import ProxyUtils, bootstrap_port
from m1n1.hw.sep import SEP, SEPMessage
from m1n1.trace.asc import ASCRegs
from collections import defaultdict, deque

iface = UartInterface(); p = M1N1Proxy(iface, debug=False); bootstrap_port(iface, p)
u = ProxyUtils(p)
sep = SEP.__new__(SEP)
sep.i, sep.p, sep.u = iface, p, u
sep.sep_base = u.adt["/arm-io/sep"].get_reg(0)[0]
sep.dart_base = u.adt["/arm-io/dart-sep"].get_reg(0)[0]
sep.asc = ASCRegs(u, sep.sep_base)
sep.dart_handle = p.request(p.P_DART_INIT, sep.dart_base, 0, 0, 2)
sep.epnum2name, sep.epname2num, sep.msgs = {}, {}, defaultdict(deque)
CNTL_EP = 0
cntl_acks, cntl_tag = set(), [0]

def pump_ep0():
    sep._try_recv_msgs()
    while sep.msgs[CNTL_EP]:
        m = sep.msgs[CNTL_EP].popleft()
        if m.TYPE == 0x01:   cntl_acks.add(m.TAG)
        elif m.TYPE == 0x11: sep.send_msg(SEPMessage(EP=0, TAG=m.TAG, TYPE=0x12))

def cntl_send(typ, data, param, label, timeout_s=5):
    cntl_tag[0] = cntl_tag[0] % 8 + 1; tag = cntl_tag[0]
    sep.send_msg(SEPMessage(EP=0, TAG=tag, TYPE=typ, PARAM=param, DATA=data))
    t = time.time()
    while time.time() - t < timeout_s:
        pump_ep0()
        if tag in cntl_acks: cntl_acks.discard(tag); return True
        time.sleep(0.01)
    return False

def next_sep_13(timeout_s=10):
    t = time.time()
    while time.time() - t < timeout_s:
        pump_ep0()
        if sep.msgs[0x13]: return sep.msgs[0x13].popleft()
        time.sleep(0.01)
    return None

DART_TCR, DART_TTBR, DART_PAGE = 0x100, 0x200, 0x4000
TCR_TRANSLATE_ENABLE, TCR_BYPASS_DART = 1 << 7, 1 << 8
TTBR_VALID, TTBR_ADDR_MASK = 1 << 31, (1 << 31) - 1
PTE_OFFSET = {"dart,t8020": (14, 39), "dart,t6000": (10, 39)}
ram_lo = u.adt["/chosen"].dram_base; ram_hi = ram_lo + u.adt["/chosen"].dram_size
dart_node = u.adt["/arm-io/dart-sep"]; dart_base = dart_node.get_reg(0)[0]
pte_lo, pte_hi = PTE_OFFSET[dart_node.compatible[0]]; pte_mask = (1 << (pte_hi - pte_lo + 1)) - 1
def _check(pa, size):
    if not (ram_lo <= pa and pa + size <= ram_hi): raise RuntimeError("PA hors RAM")
def _pte(table_pa, idx):
    pa = table_pa + 8*idx; _check(pa, 8); return struct.unpack("<Q", iface.readmem(pa, 8))[0]
def translate_page(sid, iova):
    tcr = p.read32(dart_base + DART_TCR + 4*sid)
    if tcr & TCR_BYPASS_DART or not tcr & TCR_TRANSLATE_ENABLE: return None
    if (iova >> 36) >= 4: return None
    ttbr = p.read32(dart_base + DART_TTBR + 16*sid + 4*(iova >> 36))
    if not ttbr & TTBR_VALID: return None
    l1 = _pte((ttbr & TTBR_ADDR_MASK) << 12, (iova >> 25) & 0x7FF)
    if not l1 & 1: return None
    l2 = _pte(((l1 >> pte_lo) & pte_mask) << 14, (iova >> 14) & 0x7FF)
    if not l2 & 1: return None
    return ((l2 >> pte_lo) & pte_mask) << 14
def find_sid(iova):
    for sid in range(16):
        try:
            if translate_page(sid, iova & ~(DART_PAGE-1)) is not None: return sid
        except RuntimeError: continue
    raise RuntimeError("IOVA non mappee")
def dart_rw(sid, iova, data=None, size=0):
    read = data is None; end = iova + (size if read else len(data)); cur, off, out = iova, 0, []
    while cur < end:
        page = cur & ~(DART_PAGE-1); n = min(end, page+DART_PAGE) - cur
        pa = translate_page(sid, page)
        if pa is None: raise RuntimeError("page non mappee")
        pa += cur - page; _check(pa, n)
        if read: out.append(iface.readmem(pa, n))
        else: iface.writemem(pa, data[off:off+n]); off += n
        cur += n
    return b"".join(out) if read else None

# LECTURE SEULE de l'etat de faute du dart-sep. read32 only, aucune ecriture.
DART_ERROR, DART_ERROR_ADDR_LO, DART_ERROR_ADDR_HI = 0x40, 0x50, 0x54
_DART_ERR_BITS = (("NO_DAPF_MATCH", 11), ("WRITE", 10), ("SUBPAGE_PROT", 7), ("PTE_READ_FAULT", 6),
                  ("READ_FAULT", 4), ("WRITE_FAULT", 3), ("NO_PTE", 2), ("NO_PMD", 1), ("NO_TTBR", 0))
def read_dart_fault():
    raw = p.read32(dart_base + DART_ERROR)
    addr = (p.read32(dart_base + DART_ERROR_ADDR_HI) << 32) | p.read32(dart_base + DART_ERROR_ADDR_LO)
    bits = [nm for nm, b in _DART_ERR_BITS if raw & (1 << b)]
    return {"raw": raw, "flag": (raw >> 31) & 1, "sid": (raw >> 24) & 0xf, "bits": bits, "addr": addr}
def print_dart_fault(label):
    f = read_dart_fault()
    print(f"  [DART-faute {label}] ERROR=0x{f['raw']:08x} FLAG={f['flag']} sid={f['sid']} "
          f"causes={','.join(f['bits']) or '-'} ADDR=0x{f['addr']:x}", flush=True)
    return f

print("demarrage du SEP par m1n1 (sequence publique, routine)...", flush=True)
sep.boot(); print("BOOT OK", flush=True)
t0 = time.time()
while time.time() - t0 < 8:
    pump_ep0()
    if 0x13 in sep.epnum2name: break
    time.sleep(0.02)
if 0x13 not in sep.epnum2name:
    print(f"ERREUR: EP 0x13 non annonce. {sep.epnum2name}. Abandon.", flush=True); sys.exit(2)
print("xarm (0x13) annonce : " + ", ".join(f"0x{n:02x}:{nm}" for n, nm in sorted(sep.epnum2name.items())), flush=True)
if not cntl_send(0x14, 0, 0x00, "SECMODE"):
    print("ERREUR: pas d'ack SECMODE. Abandon.", flush=True); sys.exit(3)
SIZE, IOVA_A, IOVA_B = 0x8000, 0x2c000, 0x38000
phys_A = u.heap.memalign(0x4000, SIZE); phys_B = u.heap.memalign(0x4000, SIZE)
iface.writemem(phys_A, b"\x00"*SIZE); iface.writemem(phys_B, b"\x00"*SIZE)
p.dart_map(sep.dart_handle, IOVA_A, phys_A, SIZE); p.dart_map(sep.dart_handle, IOVA_B, phys_B, SIZE)
for label, typ, data in [("A taille",0x04,SIZE),("A adresse",0x02,IOVA_A>>12),
                         ("B taille",0x05,SIZE),("B adresse",0x03,IOVA_B>>12)]:
    if not cntl_send(typ, data, 0x13, label):
        print(f"ERREUR: pas d'ack CNTL {label}. Abandon.", flush=True); sys.exit(3)
sid_A = find_sid(IOVA_A); sid_B = find_sid(IOVA_B)
store_load()
print(f"tampons prets (A sid={sid_A}, B sid={sid_B}). store: maitres={sorted(store_masters)}, gl={len(store_gls)}.", flush=True)

def write_A(data):
    iface.writemem(phys_A, b"\x00"*SIZE); dart_rw(sid_A, IOVA_A, data=data[:SIZE])

def send(m, typ, param, data): sep.send_msg(SEPMessage(EP=0x13, TAG=m.TAG, TYPE=typ, PARAM=param, DATA=data))

def serve_master(m):
    sel = (m.DATA >> 8) & 0xFF; mtype = 2 if (sel & 1) else 1
    pay = store_masters.get(mtype)
    if pay is None:
        write_A(b"\x00" * 0x11); send(m, RESP_DONE, 0x11, sel << 8); return f"ABSENT maitre t{mtype}"
    A = b"\x00" * 0x11 + pay; ln = len(A); write_A(A)
    send(m, RESP_DONE, ln & 0xFF, ((ln >> 8) & 0xFF) | (sel << 8)); return f"SERVI maitre t{mtype} ({ln}o)"

def serve_gl(m):
    sel = (m.DATA >> 8) & 0xFF; uuid = dart_rw(sid_B, IOVA_B, size=16)
    pay = store_gls.get(uuid)
    if pay is None:
        write_A(b""); send(m, RESP_DONE, 0x00, sel << 8); return f"ABSENT gl {uuid.hex()}"
    ln = len(pay); write_A(pay)
    send(m, RESP_DONE, ln & 0xFF, ((ln >> 8) & 0xFF) | (sel << 8)); return f"SERVI gl {uuid.hex()} ({ln}o)"

gl_raw = []
def handle_save(m):
    sel = (m.DATA >> 8) & 0xFF; ln = declen(m.PARAM, m.DATA)
    blob = dart_rw(sid_B, IOVA_B, size=ln) if ln else b""
    if m.TYPE == OP_SAVE_XART:
        mtype = 2 if (sel & 1) else 1; store_put_master(mtype, blob); tag = f"maitre t{mtype}"
    else:
        idx = len(gl_raw); gl_raw.append(blob)
        open(os.path.join(XART_STORE, f"glsave_{idx}.bin"), "wb").write(blob)
        tag = f"gigalocker brut #{idx}"
    send(m, RESP_DONE, 0x00, m.DATA & ACK_MASK)      # !! ACK : le compteur scelle avance
    return tag, ln

# ===========================================================================
# PHASE 2 — sonde sbio (0x73). IDENTIQUE a sep_native_sbio2.sh, renvoie le contexte (tampons) a la Phase 3.
# ===========================================================================
def probe_sbio():
    print("=== PHASE 2 — SONDE sbio (0x73, sans doigt, une seule commande) ===", flush=True)
    if 0x08 not in sep.epnum2name:
        print("  sbio (0x08) n'est PAS annonce : rien a sonder.", flush=True); return None
    if not (SBIO_A and os.path.exists(SBIO_A)):
        print(f"  ERREUR: fichier SBIO_A introuvable ({SBIO_A!r}). On n'envoie RIEN.", flush=True); return None
    a_bytes = open(SBIO_A, "rb").read()
    if len(a_bytes) <= GT_OP or a_bytes[GT_OP] != 0x73 or a_bytes[0] != 1:
        print(f"  ERREUR: SBIO_A n'est pas un gt_packet 0x73. On n'envoie RIEN.", flush=True); return None

    SZ8 = 0x4000
    IOVA_A8, IOVA_B8 = 0x54000, 0x5c000
    try:
        phys_A8 = u.heap.memalign(0x4000, SZ8)
        phys_B8 = u.heap.memalign(0x4000, SZ8)
        iface.writemem(phys_A8, b"\x00" * SZ8)
        iface.writemem(phys_B8, b"\x00" * SZ8)
        p.dart_map(sep.dart_handle, IOVA_A8, phys_A8, SZ8)
        p.dart_map(sep.dart_handle, IOVA_B8, phys_B8, SZ8)
        if SBIO_STREAM15:
            dart_handle_15 = p.request(p.P_DART_INIT, sep.dart_base, 15, 0, 2)
            p.dart_map(dart_handle_15, IOVA_A8, phys_A8, SZ8)
            p.dart_map(dart_handle_15, IOVA_B8, phys_B8, SZ8)
            print("  E1 : stream 15 du dart-sep PROGRAMME ; A8/B8 mappes en sid 0 ET sid 15 "
                  "(ecriture DART cote AP seulement, aucune ecriture SEP).", flush=True)
    except Exception as e:
        print(f"  ERREUR a l'allocation/mapping des tampons sbio : {e}. On n'envoie RIEN.", flush=True); return None
    for label, typ, data in [("A8 taille", 0x04, SZ8), ("A8 adresse", 0x02, IOVA_A8 >> 12),
                             ("B8 taille", 0x05, SZ8), ("B8 adresse", 0x03, IOVA_B8 >> 12)]:
        if not cntl_send(typ, data, 0x08, label):
            print(f"  le SEP n'a PAS acquitte le CNTL {label} (ouverture sbio) en 5 s. On s'arrete, RIEN envoye.", flush=True)
            return {"alive": False}
        print(f"  CNTL {label} (ouverture sbio) : acquitte", flush=True)

    def _maps(sid):
        try: return translate_page(sid, IOVA_A8) is not None
        except RuntimeError: return False
    sids_A8 = [s for s in range(16) if _maps(s)]
    print(f"  A8 (IOVA 0x{IOVA_A8:x}) mappe dans les streams : {sids_A8}", flush=True)

    try:
        sid_A8 = find_sid(IOVA_A8)
        dart_rw(sid_A8, IOVA_A8, data=a_bytes[:SZ8])
    except Exception as e:
        print(f"  ERREUR a l'ecriture du 0x73 dans A8 : {e}. RIEN envoye.", flush=True); return {"alive": False}
    print(f"  0x73 ecrit dans A8 (depuis {os.path.basename(SBIO_A)}). Envoi...", flush=True)
    pump_ep0(); sep.msgs[0x08].clear()
    fault_before = print_dart_fault("avant 0x73 (baseline)")
    sep.send_msg(SEPMessage(EP=0x08, TAG=0xfc, TYPE=0x73, PARAM=0x00, DATA=0x00000000))

    got = []
    t0 = time.time()
    while time.time() - t0 < 6:
        pump_ep0()
        while sep.msgs[0x08]:
            m = sep.msgs[0x08].popleft()
            got.append((m.TAG, m.TYPE))
            print(f"  SEP> EP=0x08 TAG=0x{m.TAG:02x} TYPE=0x{m.TYPE:02x} PARAM=0x{m.PARAM:02x} "
                  f"DATA=0x{m.DATA:08x}", flush=True)
        time.sleep(0.02)
    fault_after = print_dart_fault("apres 0x73")
    changed = (fault_after["raw"] != fault_before["raw"]) or (fault_after["addr"] != fault_before["addr"])
    if fault_after["flag"] and (fault_before["flag"] == 0 or changed):
        print(f"  >>> FAUTE DART NEUVE apres le 0x73 : sid={fault_after['sid']} "
              f"causes={','.join(fault_after['bits']) or '-'} adresse=0x{fault_after['addr']:x}.", flush=True)
    try:
        b8 = iface.readmem(phys_B8, SZ8)
    except Exception as e:
        b8 = b""; print(f"  (lecture de B8 impossible : {e})", flush=True)
    nz = sum(1 for x in b8 if x)
    if b8 and os.environ.get("OUT"):
        try:
            with open(os.path.join(os.environ["OUT"], "sbio_probe_B.bin"), "wb") as f: f.write(b8)
        except Exception: pass
    b_ok = len(b8) > GT_OP and b8[0] == 1 and b8[GT_OP] == 0x73
    msg_ok = any(typ == 0x73 for _, typ in got) or any(tag == 0x04 for tag, _ in got)
    print(f"  B8 : {nz} octets non nuls ; tete={b8[:0x20].hex() if b8 else '-'}", flush=True)
    alive = bool(b_ok or msg_ok)
    if alive:
        print(">>> SONDE sbio : sbio a REPONDU au 0x73 (VIVANT sous m1n1). Comparer a c12 (B +0x00=1, +0x14=0x73). "
              "NE PAS conclure 'Touch ID marche' : reste init capteur, blobs, match, enrolement.", flush=True)
    else:
        print(">>> SONDE sbio : AUCUNE reponse au 0x73 (B8 nul, aucun message EP 0x08). sbio ANNONCE mais muet ici.", flush=True)
    return {"alive": alive, "phys_A8": phys_A8, "phys_B8": phys_B8,
            "IOVA_A8": IOVA_A8, "IOVA_B8": IOVA_B8, "sid_A8": (sid_A8 if 'sid_A8' in dir() else None), "SZ8": SZ8}

# ===========================================================================
# PHASE 3 — FRANCHIR 0x17 (lecture capteur SPI live) puis deroule post-0x17, STOP au 1er [SPI]/[BLOB]/[FINGER].
# ===========================================================================
def _hexhead(b, n=0x40): return b[:n].hex() if b else "-"

def read_c12_ool(fn):
    if not (fn and C12_OOL): return None
    pth = os.path.join(C12_OOL, fn)
    return open(pth, "rb").read() if os.path.exists(pth) else None

def dump_wall(ctx, step, idx):
    op, cls, name, oa, ob = step
    outdir = os.environ.get("OUT")
    print(f"  --- DUMP du mur (etape #{idx}, op=0x{op:02x} [{cls}] {name}) ---", flush=True)
    # 1. ce que le SEP demande spontanement sur EP 0x08
    pump_ep0()
    spont = []
    t0 = time.time()
    while time.time() - t0 < WALL_LISTEN:
        pump_ep0()
        while sep.msgs[0x08]:
            m = sep.msgs[0x08].popleft()
            spont.append((m.TAG, m.TYPE, m.PARAM, m.DATA))
            print(f"    SEP> EP=0x08 TAG=0x{m.TAG:02x} TYPE=0x{m.TYPE:02x} PARAM=0x{m.PARAM:02x} DATA=0x{m.DATA:08x}", flush=True)
        time.sleep(0.02)
    if not spont:
        print("    (aucun message EP 0x08 spontane : le SEP ATTEND que l'AP pilote la commande suivante, "
              "comme macOS. La commande suivante attendue = ce mur.)", flush=True)
    # 2. etat LIVE des tampons A8/B8
    try:
        a8 = iface.readmem(ctx["phys_A8"], ctx["SZ8"])
        b8 = iface.readmem(ctx["phys_B8"], ctx["SZ8"])
    except Exception as e:
        a8 = b8 = b""; print(f"    (lecture A8/B8 impossible : {e})", flush=True)
    print(f"    A8 (notre dernier envoi)  tete={_hexhead(a8)}", flush=True)
    print(f"    B8 (derniere sortie SEP)  tete={_hexhead(b8)}", flush=True)
    # 3. faute DART (lecture seule)
    print_dart_fault("au mur")
    # 4. reference capture c12 = DONNEES : forme EXACTE de la commande du mur cote macOS
    ref_a = read_c12_ool(oa); ref_b = read_c12_ool(ob)
    if ref_a is not None:
        oplen = ref_a[GT_LEN] if len(ref_a) > GT_LEN else None
        print(f"    ref capture c12 ({oa}, {len(ref_a)}o) = commande du mur cote macOS : gt_packet "
              f"+0x14=0x{ref_a[GT_OP]:02x} +0x18=0x{(oplen if oplen is not None else 0):02x} (len charge) ; "
              f"charge a +0x1c tete={_hexhead(ref_a[GT_PAYLOAD:GT_PAYLOAD+0x20])}", flush=True)
    # 5. ecrire les dumps
    if outdir:
        try:
            if a8: open(os.path.join(outdir, "wall_A8.bin"), "wb").write(a8)
            if b8: open(os.path.join(outdir, "wall_B8.bin"), "wb").write(b8)
            if ref_a is not None: open(os.path.join(outdir, f"wall_ref_{op:02x}_A.bin"), "wb").write(ref_a)
            if ref_b is not None: open(os.path.join(outdir, f"wall_ref_{op:02x}_B.bin"), "wb").write(ref_b)
            with open(os.path.join(outdir, "wall_summary.txt"), "w") as f:
                f.write(f"MUR post-0x17 (route native)\n")
                f.write(f"etape #{idx} op=0x{op:02x} classe=[{cls}] {name}\n")
                f.write(f"messages EP 0x08 spontanes du SEP : {spont}\n")
                f.write(f"A8_head={_hexhead(a8)}\nB8_head={_hexhead(b8)}\n")
                f.write(f"ref_capture_A={oa} ref_capture_B={ob}\n")
            print(f"    dumps ecrits dans {outdir}/ : wall_A8.bin wall_B8.bin "
                  f"{'wall_ref_%02x_A.bin ' % op if ref_a is not None else ''}wall_summary.txt", flush=True)
        except Exception as e:
            print(f"    (ecriture des dumps impossible : {e})", flush=True)

def phase3(ctx):
    """FRANCHIR 0x17. Renvoie (mesa, crossed). sbio4 : le capteur reste ALIMENTE (pas de teardown ici) ;
    l'instance MesaSPI est rendue a l'appelant qui la passe a la Phase 4 puis la detruit dans son finally."""
    print("=== PHASE 3 — FRANCHIR 0x17 prepareSession (n° serie capteur lu SUR SPI, en direct) ===", flush=True)
    if not ctx or not ctx.get("alive"):
        print("  sbio pas VIVANT (0x73 sans reponse) : PHASE 3 non lancee (fail-closed).", flush=True); return None, False
    if ctx.get("sid_A8") is None:
        print("  sid A8 inconnu : PHASE 3 non lancee (fail-closed).", flush=True); return None, False
    # 1. gabarit 0x17 (c12) = forme EXACTE du gt_packet (DONNEES) ; sa charge = serie attendue.
    if not (SBIO_0X17_TMPL and os.path.exists(SBIO_0X17_TMPL)):
        print(f"  gabarit 0x17 introuvable ({SBIO_0X17_TMPL!r}) -> STOP (fail-closed).", flush=True); return None, False
    tmpl = open(SBIO_0X17_TMPL, "rb").read()
    if len(tmpl) < GT_PAYLOAD + X17_PAYLEN or tmpl[GT_OP] != 0x17 or tmpl[GT_LEN] != X17_PAYLEN:
        o = tmpl[GT_OP] if len(tmpl) > GT_OP else -1; l = tmpl[GT_LEN] if len(tmpl) > GT_LEN else -1
        print(f"  gabarit 0x17 malforme (+0x14=0x{o:02x} +0x18=0x{l:02x}, len {len(tmpl)}) -> STOP (fail-closed).", flush=True); return None, False
    expected_serial = tmpl[GT_PAYLOAD:GT_PAYLOAD + X17_PAYLEN]
    print(f"  gabarit 0x17 : {os.path.basename(SBIO_0X17_TMPL)} ({len(tmpl)}o), serie attendue (c12) = {expected_serial.hex()}", flush=True)
    # 2. brique SPI capteur, DANS LA MEME session proxy.
    try:
        from analysis.mesa_spi_proxy import MesaSPI, MesaError
    except Exception as e:
        print(f"  import de analysis.mesa_spi_proxy impossible : {e} -> STOP (fail-closed).", flush=True); return None, False
    mesa = None
    try:
        mesa = MesaSPI(iface, p, u)              # verifie l'etat iBoot (lecture seule) ; peut lever MesaError
        print("  MesaSPI construit (capteur mesa sur spi2, etat iBoot verifie, lecture seule).", flush=True)
        mesa.power_on()                          # alim gpio0 196 + spi2 mode scrute (comme mesa_hello)
        print("  capteur ALIMENTE (gpio0 196) + spi2 en mode scrute (reste alimente jusqu'a la fin du run).", flush=True)
        ident = mesa.read_id()                   # bonjour -> identite ; verif interne vs ID_EXPECTED
        serial = ident[SERIAL_SLICE]
        print(f"  identite capteur LUE ({len(ident)}o) : {ident.hex()}", flush=True)
        print(f"  n° de serie extrait [9:25] : {serial.hex()}", flush=True)
        if serial != expected_serial:
            print(f"  >>> MUR : serie capteur != gabarit c12 ({serial.hex()} != {expected_serial.hex()}) "
                  f"-> STOP (fail-closed). On N'ENVOIE PAS 0x17.", flush=True)
            dump_wall(ctx, POST_0X73_STEPS[0], 0); return mesa, False
        # 3. construire la commande 0x17 depuis le gabarit, en INJECTANT la serie LUE A L'INSTANT.
        #    (securite : on sert ce que le capteur DIT MAINTENANT ; doit etre identique au gabarit.)
        cmd = bytearray(tmpl); cmd[GT_PAYLOAD:GT_PAYLOAD + X17_PAYLEN] = serial
        try:
            iface.writemem(ctx["phys_A8"], b"\x00" * ctx["SZ8"])
            dart_rw(ctx["sid_A8"], ctx["IOVA_A8"], data=bytes(cmd)[:ctx["SZ8"]])
        except Exception as e:
            print(f"  ecriture de la commande 0x17 dans A8 impossible : {e} -> STOP (fail-closed).", flush=True); return mesa, False
        pump_ep0(); sep.msgs[0x08].clear()
        print_dart_fault("avant 0x17 (baseline)")
        print("  envoi EP 0x08 TAG=0xfc TYPE=0x17 (prepareSession ; charge = serie capteur lue en direct)...", flush=True)
        sep.send_msg(SEPMessage(EP=0x08, TAG=0xfc, TYPE=0x17, PARAM=0x00, DATA=0x00000000))
        got = []; t0 = time.time()
        while time.time() - t0 < 6:
            pump_ep0()
            while sep.msgs[0x08]:
                m = sep.msgs[0x08].popleft(); got.append((m.TAG, m.TYPE))
                print(f"    SEP> EP=0x08 TAG=0x{m.TAG:02x} TYPE=0x{m.TYPE:02x} PARAM=0x{m.PARAM:02x} DATA=0x{m.DATA:08x}", flush=True)
            time.sleep(0.02)
        print_dart_fault("apres 0x17")
        try: b8 = iface.readmem(ctx["phys_B8"], ctx["SZ8"])
        except Exception: b8 = b""
        nz = sum(1 for x in b8 if x)
        if b8 and os.environ.get("OUT"):
            try: open(os.path.join(os.environ["OUT"], "cross_0x17_B.bin"), "wb").write(b8)
            except Exception: pass
        print(f"  B8 apres 0x17 : {nz} octets non nuls ; tete={_hexhead(b8)}", flush=True)
        ok = any(typ == 0x17 for _, typ in got)
        print(f"  reponse SEP de meme type 0x17 : {'OUI' if ok else 'NON'}", flush=True)
        if not ok:
            print("  >>> 0x17 NON acquitte par le SEP (pas de '< 0x17') -> STOP (fail-closed). Dump de l'etat :", flush=True)
            dump_wall(ctx, POST_0X73_STEPS[0], 0); return mesa, False
        print(">>> 0x17 FRANCHI NATIVEMENT : le SEP a accepte le n° de serie capteur lu en direct. "
              "NE PAS conclure 'Touch ID marche' : reste le lockstep chiffre 0x15/0x16, les blobs, le match.", flush=True)
        return mesa, True
    except MesaError as e:
        print(f"  >>> capteur (MesaSPI) : {e} -> STOP (fail-closed).", flush=True)
        return mesa, False
    except Exception as e:
        print(f"  >>> erreur PHASE 3 : {e} -> STOP (fail-closed).", flush=True)
        return mesa, False

# ===========================================================================
# PHASE 4 — RELAIS key exchange 0x15/0x16 (performKeyExchange). L'AP = PUR RELAIS d'octets (aucune crypto,
#   aucun secret) : voir docs/sbio_keyexchange.md. On s'ARRETE juste apres ce 1er echange de cles.
# ===========================================================================
def spi_relay(mesa, cmd_opcode, blob, label="kx", expect_pending=None):
    """Relaie `blob` (octets OPAQUES du SEP) au capteur via la trame SPI `cmd_opcode` (0x72 = key exchange,
    0x73 = compteur), lit la reponse et la rend BRUTE. FACTORISE le relais SPI de sbio4 (etait spi_relay_0x72).
    Sequence = transport documente (sensor_hw.md / mesa_hello / sbio_keyexchange.md §9 / sbio_session.md §1) :
    emettre la commande, poll etat 0x10 pour la longueur en attente, demander 0x13, lire. DUMPE la reponse
    brute. Ne modifie JAMAIS les octets.
    La trame = build_spi_frame(cmd_opcode, blob) : en-tete 80 <cmd> <TAILLE TOTALE 16b BE> 000000 + blob, ou la
    LONGUEUR = 7 + len(blob) (VU macOS C19 ; seul l'opcode 0x72/0x73 est fixe, la taille vient du blob, PAS en
    dur). Rappel sbio4 : la longueur d'en-tete est la TOTALE (ex. 0x2f=47 pour le KX), PAS la charge (0x28)."""
    from analysis.mesa_spi_proxy import MesaError
    frame = build_spi_frame(cmd_opcode, blob)
    exp_total = 7 + len(blob)
    if len(frame) != exp_total:
        raise MesaError(f"trame 0x{cmd_opcode:02x} mal formee ({len(frame)} o, attendu {exp_total})")
    exp_txt = f" (attendu 0x{expect_pending:02x})" if expect_pending is not None else ""
    print(f"  SPI> trame 0x{cmd_opcode:02x} ({len(frame)} o) : en-tete {frame[:7].hex()} + {len(blob)} o opaques du SEP.", flush=True)
    mesa.xfer(frame, 0); time.sleep(0.01)                        # emettre la commande (rx_len=0, comme mesa_hello)
    # poll etat 0x10 : la longueur de la reponse en attente est dans st[12]|st[13]<<8 (cf. mesa_spi_proxy.hello)
    pending = 0; st = None
    for _ in range(50):
        st = mesa.status()
        pending = st[12] | (st[13] << 8)
        if pending:
            break
        time.sleep(0.01)
    print(f"  SPI< etat 0x10 : longueur en attente = 0x{pending:02x}{exp_txt}", flush=True)
    resp = b""
    if pending:
        req = bytes.fromhex("8013000b000000") + struct.pack("<I", pending)   # demande 0x13 de `pending` octets
        mesa.xfer(req, 0); time.sleep(0.01)
        resp = mesa.xfer(bytes(pending), pending)                # lecture full-duplex de `pending` octets
    outdir = os.environ.get("OUT")
    if outdir:
        try:
            if st is not None: open(os.path.join(outdir, f"spi_{label}_status.bin"), "wb").write(bytes(st))
            if resp: open(os.path.join(outdir, f"spi_{label}_resp_raw.bin"), "wb").write(resp)
        except Exception as e:
            print(f"    (ecriture dump SPI impossible : {e})", flush=True)
    print(f"  SPI< reponse 0x{cmd_opcode:02x} BRUTE ({len(resp)} o) tete={_hexhead(resp)}", flush=True)
    return resp, pending

def phase4(ctx, mesa):
    print("=== PHASE 4 — RELAIS key exchange 0x15/0x16 (performKeyExchange ; AP = pur relais d'octets) ===", flush=True)
    if mesa is None:
        print("  capteur non disponible : PHASE 4 non lancee (fail-closed).", flush=True); return
    from analysis.mesa_spi_proxy import MesaError
    # --- gabarits 0x15 / 0x16 (FORME du gt_packet ; DONNEES ; la charge du 0x16 sera remplacee live) ---
    t15 = _read_file(SBIO_0X15_TMPL)
    t16 = _read_file(SBIO_0X16_TMPL)
    if t15 is None or len(t15) < GT_PAYLOAD + 4 or t15[GT_OP] != 0x15 or t15[GT_LEN] != 0x04:
        print(f"  gabarit 0x15 absent/malforme ({SBIO_0X15_TMPL!r}) -> STOP (fail-closed).", flush=True); return
    if t16 is None or len(t16) < GT_PAYLOAD + KX_BLOB_LEN or t16[GT_OP] != 0x16 or t16[GT_LEN] != KX_BLOB_LEN:
        print(f"  gabarit 0x16 absent/malforme ({SBIO_0X16_TMPL!r}) -> STOP (fail-closed).", flush=True); return
    print(f"  gabarits OK : 0x15 ({os.path.basename(SBIO_0X15_TMPL)}, sessionType={t15[GT_PAYLOAD:GT_PAYLOAD+4].hex()}) "
          f"; 0x16 ({os.path.basename(SBIO_0X16_TMPL)}, charge 40 o a remplacer).", flush=True)

    # --- (1) sbio 0x15 : le SEP rend un blob opaque de 40 o ---
    try:
        iface.writemem(ctx["phys_A8"], b"\x00" * ctx["SZ8"])
        dart_rw(ctx["sid_A8"], ctx["IOVA_A8"], data=t15[:ctx["SZ8"]])
    except Exception as e:
        print(f"  ecriture 0x15 dans A8 impossible : {e} -> STOP (fail-closed).", flush=True); return
    pump_ep0(); sep.msgs[0x08].clear()
    print_dart_fault("avant 0x15 (baseline)")
    print("  envoi EP 0x08 TAG=0xfc TYPE=0x15 (performKeyExchange, sessionType=1)...", flush=True)
    sep.send_msg(SEPMessage(EP=0x08, TAG=0xfc, TYPE=0x15, PARAM=0x00, DATA=0x00000000))
    got = []; t0 = time.time()
    while time.time() - t0 < 6:
        pump_ep0()
        while sep.msgs[0x08]:
            m = sep.msgs[0x08].popleft(); got.append((m.TAG, m.TYPE))
            print(f"    SEP> EP=0x08 TAG=0x{m.TAG:02x} TYPE=0x{m.TYPE:02x} PARAM=0x{m.PARAM:02x} DATA=0x{m.DATA:08x}", flush=True)
        time.sleep(0.02)
    print_dart_fault("apres 0x15")
    try: b8 = iface.readmem(ctx["phys_B8"], ctx["SZ8"])
    except Exception: b8 = b""
    if b8 and os.environ.get("OUT"):
        try: open(os.path.join(os.environ["OUT"], "kx_0x15_B.bin"), "wb").write(b8)
        except Exception: pass
    blob_op  = b8[GT_OP]  if len(b8) > GT_OP  else -1
    blob_len = b8[GT_LEN] if len(b8) > GT_LEN else -1
    print(f"  B8 apres 0x15 : tete={_hexhead(b8)} ; +0x14=0x{blob_op:02x} +0x18=0x{blob_len:02x} (attendu 0x15 / 0x{KX_BLOB_LEN:02x})", flush=True)
    # FAIL-CLOSED : la taille du blob SEP DOIT etre 0x28 (offset +0x1c CONFIRME par la capture 000306_08_B.bin).
    if not (len(b8) >= GT_PAYLOAD + KX_BLOB_LEN and blob_op == 0x15 and blob_len == KX_BLOB_LEN):
        print(f"  >>> reponse 0x15 INATTENDUE (type != 0x15 ou taille != 0x{KX_BLOB_LEN:02x}) -> STOP+dump (fail-closed, on ne devine pas).", flush=True)
        dump_wall(ctx, POST_0X73_STEPS[1], 1); return
    sep_blob = bytes(b8[GT_PAYLOAD:GT_PAYLOAD + KX_BLOB_LEN])
    print(f"  blob KX du SEP (40 o, +0x1c, OPAQUE) = {sep_blob.hex()}", flush=True)

    # --- (2) relais SPI : 40 o -> capteur (trame 0x72) -> 40 o ---
    try:
        resp, pending = spi_relay(mesa, 0x72, sep_blob, label="0x72", expect_pending=0x33)
    except MesaError as e:
        print(f"  >>> relais SPI 0x72 : {e} -> STOP+dump (fail-closed).", flush=True)
        dump_wall(ctx, POST_0X73_STEPS[1], 1); return
    # extraction best-effort : charge a SPI_RESP_OFF (defaut 9 ; parsing d'enveloppe SPI non 100% reverse, sbio_keyexchange.md §8).
    if len(resp) < SPI_RESP_OFF + KX_BLOB_LEN:
        print(f"  >>> reponse SPI trop courte ({len(resp)} o) pour extraire 40 o a l'offset {SPI_RESP_OFF} "
              f"-> STOP+dump (fail-closed, on ne devine pas). Reponse brute dans $OUT/spi_0x72_resp_raw.bin.", flush=True)
        dump_wall(ctx, POST_0X73_STEPS[1], 1); return
    sensor_resp = bytes(resp[SPI_RESP_OFF:SPI_RESP_OFF + KX_BLOB_LEN])
    print(f"  reponse capteur extraite (40 o @ offset {SPI_RESP_OFF}, OPAQUE) = {sensor_resp.hex()}", flush=True)

    # --- (3) sbio 0x16 : renvoyer au SEP les 40 o du capteur (charge remplacee dans le gabarit) ---
    cmd16 = bytearray(t16); cmd16[GT_PAYLOAD:GT_PAYLOAD + KX_BLOB_LEN] = sensor_resp
    try:
        iface.writemem(ctx["phys_A8"], b"\x00" * ctx["SZ8"])
        dart_rw(ctx["sid_A8"], ctx["IOVA_A8"], data=bytes(cmd16)[:ctx["SZ8"]])
    except Exception as e:
        print(f"  ecriture 0x16 dans A8 impossible : {e} -> STOP (fail-closed).", flush=True); return
    pump_ep0(); sep.msgs[0x08].clear()
    print("  envoi EP 0x08 TAG=0xfc TYPE=0x16 (reponse capteur relayee au SEP)...", flush=True)
    sep.send_msg(SEPMessage(EP=0x08, TAG=0xfc, TYPE=0x16, PARAM=0x00, DATA=0x00000000))
    got16 = []; t0 = time.time()
    while time.time() - t0 < 6:
        pump_ep0()
        while sep.msgs[0x08]:
            m = sep.msgs[0x08].popleft(); got16.append((m.TAG, m.TYPE))
            print(f"    SEP> EP=0x08 TAG=0x{m.TAG:02x} TYPE=0x{m.TYPE:02x} PARAM=0x{m.PARAM:02x} DATA=0x{m.DATA:08x}", flush=True)
        time.sleep(0.02)
    print_dart_fault("apres 0x16")
    try: b8b = iface.readmem(ctx["phys_B8"], ctx["SZ8"])
    except Exception: b8b = b""
    if b8b and os.environ.get("OUT"):
        try: open(os.path.join(os.environ["OUT"], "kx_0x16_B.bin"), "wb").write(b8b)
        except Exception: pass
    print(f"  B8 apres 0x16 : tete={_hexhead(b8b)}", flush=True)

    # --- (4) VERDICT auto-verifiant ---
    ok16 = any(typ == 0x16 for _, typ in got16)
    if ok16:
        print(">>> KEY EXCHANGE RELAYE : le SEP a ACQUITTE 0x16 (< EP=0x08 TYPE=0x16). Le 1er dialogue chiffre "
              "SEP<->capteur a ete relaye NATIVEMENT en lockstep (grand pas). NE PAS conclure 'Touch ID marche' : "
              "restent 0x42/0x18, le patch capteur, les params chiffres, le match, l'enrolement.", flush=True)
    else:
        print(">>> 0x16 NON acquitte par le SEP : le parsing de la reponse SPI est PROBABLEMENT faux "
              f"(offset {SPI_RESP_OFF} ?) -> STOP+dump pour inspection (reponse SPI brute dans $OUT/spi_0x72_resp_raw.bin ; "
              "re-essayer avec un autre SPI_RESP_OFF). Fail-closed.", flush=True)
        dump_wall(ctx, POST_0X73_STEPS[2], 2)

    # --- (5) si 0x16 acquitte -> ENCHAINER la Phase 5 (compteur) ; sinon STOP (fail-closed) ---
    if ok16:
        print("=== PHASE 4 terminee (key exchange relaye) : on ENCHAINE la Phase 5 (compteur 0x42/0x18). ===", flush=True)
    else:
        print("=== PHASE 4 : key exchange NON relaye -> Phase 5 (compteur) NON lancee (fail-closed). ===", flush=True)
    return ok16

# ===========================================================================
# PHASE 5 — RELAIS compteur de sequence 0x42/0x18 (initializeSequenceCounter). MEME recette de relais que la
#   Phase 4 (AP = pur relais d'octets). Si 0x18 acquitte -> ENCHAINE la Phase 6 (patch 0x5f : RECON + PUSH).
# ===========================================================================
def phase5(ctx, mesa):
    print("=== PHASE 5 — RELAIS compteur de sequence 0x42/0x18 (initializeSequenceCounter ; AP = pur relais) ===", flush=True)
    if mesa is None:
        print("  capteur non disponible : PHASE 5 non lancee (fail-closed).", flush=True); return
    from analysis.mesa_spi_proxy import MesaError
    # --- gabarits 0x42 / 0x18 (FORME du gt_packet ; DONNEES ; la charge du 0x18 sera remplacee live) ---
    t42 = _read_file(SBIO_0X42_TMPL)
    t18 = _read_file(SBIO_0X18_TMPL)
    if t42 is None or len(t42) <= GT_LEN or t42[GT_OP] != 0x42:
        print(f"  gabarit 0x42 absent/malforme ({SBIO_0X42_TMPL!r}) -> STOP (fail-closed).", flush=True); return
    if t18 is None or len(t18) < GT_PAYLOAD + CNT_BLOB_LEN or t18[GT_OP] != 0x18 or t18[GT_LEN] != CNT_BLOB_LEN:
        print(f"  gabarit 0x18 absent/malforme ({SBIO_0X18_TMPL!r}) -> STOP (fail-closed).", flush=True); return
    inject_len = t18[GT_LEN]           # taille a injecter dans 0x18 = longueur du gt_packet (du gabarit, PAS en dur)
    print(f"  gabarits OK : 0x42 ({os.path.basename(SBIO_0X42_TMPL)}, charge d'entree vide) "
          f"; 0x18 ({os.path.basename(SBIO_0X18_TMPL)}, charge {inject_len} o a remplacer).", flush=True)

    # --- (1) sbio 0x42 : le SEP rend un blob opaque de 64 o ---
    try:
        iface.writemem(ctx["phys_A8"], b"\x00" * ctx["SZ8"])
        dart_rw(ctx["sid_A8"], ctx["IOVA_A8"], data=t42[:ctx["SZ8"]])
    except Exception as e:
        print(f"  ecriture 0x42 dans A8 impossible : {e} -> STOP (fail-closed).", flush=True); return
    pump_ep0(); sep.msgs[0x08].clear()
    print_dart_fault("avant 0x42 (baseline)")
    print("  envoi EP 0x08 TAG=0xfc TYPE=0x42 (initializeSequenceCounter)...", flush=True)
    sep.send_msg(SEPMessage(EP=0x08, TAG=0xfc, TYPE=0x42, PARAM=0x00, DATA=0x00000000))
    got = []; t0 = time.time()
    while time.time() - t0 < 6:
        pump_ep0()
        while sep.msgs[0x08]:
            m = sep.msgs[0x08].popleft(); got.append((m.TAG, m.TYPE))
            print(f"    SEP> EP=0x08 TAG=0x{m.TAG:02x} TYPE=0x{m.TYPE:02x} PARAM=0x{m.PARAM:02x} DATA=0x{m.DATA:08x}", flush=True)
        time.sleep(0.02)
    print_dart_fault("apres 0x42")
    try: b8 = iface.readmem(ctx["phys_B8"], ctx["SZ8"])
    except Exception: b8 = b""
    if b8 and os.environ.get("OUT"):
        try: open(os.path.join(os.environ["OUT"], "cnt_0x42_B.bin"), "wb").write(b8)
        except Exception: pass
    blob_op  = b8[GT_OP]  if len(b8) > GT_OP  else -1
    blob_len = b8[GT_LEN] if len(b8) > GT_LEN else -1
    print(f"  B8 apres 0x42 : tete={_hexhead(b8)} ; +0x14=0x{blob_op:02x} +0x18=0x{blob_len:02x} (attendu 0x42 / 0x{CNT_BLOB_LEN:02x})", flush=True)
    # FAIL-CLOSED : taille du blob SEP lue a +0x18, VERIFIEE coherente avec le VU C19 (0x40). On ne devine pas.
    if not (len(b8) >= GT_PAYLOAD + CNT_BLOB_LEN and blob_op == 0x42 and blob_len == CNT_BLOB_LEN):
        print(f"  >>> reponse 0x42 INATTENDUE (type != 0x42 ou taille +0x18 != 0x{CNT_BLOB_LEN:02x}) "
              f"-> STOP+dump (fail-closed, on ne devine pas).", flush=True)
        dump_wall(ctx, POST_0X73_STEPS[3], 3); return
    sep_blob = bytes(b8[GT_PAYLOAD:GT_PAYLOAD + blob_len])
    print(f"  blob compteur du SEP ({blob_len} o, +0x1c, OPAQUE) = {sep_blob.hex()}", flush=True)

    # --- (2) relais SPI : 64 o -> capteur (trame 0x73) -> 64 o ---
    try:
        resp, pending = spi_relay(mesa, 0x73, sep_blob, label="0x73", expect_pending=CNT_PENDING)
    except MesaError as e:
        print(f"  >>> relais SPI 0x73 : {e} -> STOP+dump (fail-closed).", flush=True)
        dump_wall(ctx, POST_0X73_STEPS[3], 3); return
    if len(resp) < SPI_RESP_OFF + inject_len:
        print(f"  >>> reponse SPI 0x73 trop courte ({len(resp)} o) pour extraire {inject_len} o a l'offset {SPI_RESP_OFF} "
              f"-> STOP+dump (fail-closed, on ne devine pas). Reponse brute dans $OUT/spi_0x73_resp_raw.bin.", flush=True)
        dump_wall(ctx, POST_0X73_STEPS[3], 3); return
    sensor_resp = bytes(resp[SPI_RESP_OFF:SPI_RESP_OFF + inject_len])
    print(f"  reponse capteur extraite ({inject_len} o @ offset {SPI_RESP_OFF}, OPAQUE) = {sensor_resp.hex()}", flush=True)

    # --- (3) sbio 0x18 : renvoyer au SEP les 64 o du capteur (charge remplacee dans le gabarit) ---
    cmd18 = bytearray(t18); cmd18[GT_PAYLOAD:GT_PAYLOAD + inject_len] = sensor_resp
    try:
        iface.writemem(ctx["phys_A8"], b"\x00" * ctx["SZ8"])
        dart_rw(ctx["sid_A8"], ctx["IOVA_A8"], data=bytes(cmd18)[:ctx["SZ8"]])
    except Exception as e:
        print(f"  ecriture 0x18 dans A8 impossible : {e} -> STOP (fail-closed).", flush=True); return
    pump_ep0(); sep.msgs[0x08].clear()
    print("  envoi EP 0x08 TAG=0xfc TYPE=0x18 (reponse capteur relayee au SEP)...", flush=True)
    sep.send_msg(SEPMessage(EP=0x08, TAG=0xfc, TYPE=0x18, PARAM=0x00, DATA=0x00000000))
    got18 = []; t0 = time.time()
    while time.time() - t0 < 6:
        pump_ep0()
        while sep.msgs[0x08]:
            m = sep.msgs[0x08].popleft(); got18.append((m.TAG, m.TYPE))
            print(f"    SEP> EP=0x08 TAG=0x{m.TAG:02x} TYPE=0x{m.TYPE:02x} PARAM=0x{m.PARAM:02x} DATA=0x{m.DATA:08x}", flush=True)
        time.sleep(0.02)
    print_dart_fault("apres 0x18")
    try: b8b = iface.readmem(ctx["phys_B8"], ctx["SZ8"])
    except Exception: b8b = b""
    if b8b and os.environ.get("OUT"):
        try: open(os.path.join(os.environ["OUT"], "cnt_0x18_B.bin"), "wb").write(b8b)
        except Exception: pass
    print(f"  B8 apres 0x18 : tete={_hexhead(b8b)}", flush=True)

    # --- (4) VERDICT auto-verifiant ---
    ok18 = any(typ == 0x18 for _, typ in got18)
    if ok18:
        print(">>> COMPTEUR DE SEQUENCE RELAYE : le SEP a ACQUITTE 0x18 (< EP=0x08 TYPE=0x18). Le relais du "
              "compteur 0x42/0x18 a MARCHE en lockstep. NE PAS conclure 'Touch ID marche' : restent le patch "
              "capteur (0x5f), les params chiffres, le match, l'enrolement.", flush=True)
    else:
        print(">>> 0x18 NON acquitte par le SEP : le parsing de la reponse SPI 0x73 est PROBABLEMENT faux "
              f"(offset {SPI_RESP_OFF} ?) -> STOP+dump (reponse SPI brute dans $OUT/spi_0x73_resp_raw.bin ; "
              "re-essayer avec un autre SPI_RESP_OFF). Fail-closed.", flush=True)
        dump_wall(ctx, POST_0X73_STEPS[4], 4)

    # --- (5) si 0x18 acquitte -> ENCHAINER la Phase 6 (patch 0x5f : RECON + PUSH) ; sinon STOP (fail-closed) ---
    if ok18:
        print("=== PHASE 5 terminee (compteur relaye) : on ENCHAINE la Phase 6 (patch 0x5f : RECON + PUSH). ===", flush=True)
    else:
        print("=== PHASE 5 : compteur NON relaye -> Phase 6 (patch 0x5f + push) NON lancee (fail-closed). ===", flush=True)
    return ok18

# ===========================================================================
# PHASE 6 — RECON du patch 0x5f (LoadPatch) PUIS PUSH au capteur. On ENVOIE 0x5f au SEP, on RECOIT le patch
#   ~22 Ko qu'il livre en fragments OOL (poignee fe/fd), on le REASSEMBLE, on le VERIFIE, on le DUMPE, on
#   CONSTRUIT la trame SPI de push (prelude 0x60 + bloc), puis on l'EMET AU CAPTEUR (prelude puis bloc 22 Ko en
#   UN xfer FIFO scrute, rx_len=0, timeout eleve), on relit l'etat capteur (0x10) avant/apres, on rend le
#   VERDICT (status bien forme = push emis ; timeout/status casse = FIFO ne tient pas -> DMA SIO sbio8), et on
#   S'ARRETE (pas de params 0x5d...). Teardown capteur dans le finally EXTERNE (power_off recupere un mi-patche).
# ===========================================================================
def recv_patch_fragment(label):
    """Attend le prochain message EP 0x08 TYPE=0x5f du SEP, lit B8 et renvoie (tag, buf_B8). Fail-closed : rend
    (None, b'') si rien n'arrive. Ne modifie pas B8 (lecture seule cote AP)."""
    got = []; t0 = time.time()
    while time.time() - t0 < 6:
        pump_ep0()
        while sep.msgs[0x08]:
            m = sep.msgs[0x08].popleft(); got.append((m.TAG, m.TYPE, m.PARAM, m.DATA))
            print(f"    SEP> EP=0x08 TAG=0x{m.TAG:02x} TYPE=0x{m.TYPE:02x} PARAM=0x{m.PARAM:02x} DATA=0x{m.DATA:08x}", flush=True)
            if m.TYPE == PATCH_OP:
                try: b8 = iface.readmem(ctx_B8_phys, ctx_B8_sz)
                except Exception as e:
                    print(f"    (lecture B8 impossible : {e})", flush=True); b8 = b""
                return m.TAG, b8
        time.sleep(0.02)
    return None, b""

ctx_B8_phys = None; ctx_B8_sz = None  # renseignes par phase6 (evite de trop passer d'arguments au helper)

def phase6(ctx, mesa):
    global ctx_B8_phys, ctx_B8_sz
    print("=== PHASE 6 — patch 0x5f (LoadPatch) : RECEVOIR + REASSEMBLER + DUMPER, PUIS PUSH au capteur (prelude 0x60 + bloc 22Ko) ===", flush=True)
    ctx_B8_phys = ctx["phys_B8"]; ctx_B8_sz = ctx["SZ8"]
    outdir = os.environ.get("OUT")
    # --- gabarit 0x5f (FORME du gt_packet ; entree 2 o relayee telle quelle) ---
    t5f = _read_file(SBIO_0X5F_TMPL)
    if t5f is None or len(t5f) <= GT_LEN or t5f[GT_OP] != PATCH_OP:
        print(f"  gabarit 0x5f absent/malforme ({SBIO_0X5F_TMPL!r}) -> STOP (fail-closed).", flush=True); return
    print(f"  gabarit 0x5f OK : {os.path.basename(SBIO_0X5F_TMPL)} (entree {t5f[GT_LEN]} o).", flush=True)

    # --- (1) envoyer 0x5f (commande LoadPatch) ---
    try:
        iface.writemem(ctx["phys_A8"], b"\x00" * ctx["SZ8"])
        dart_rw(ctx["sid_A8"], ctx["IOVA_A8"], data=t5f[:ctx["SZ8"]])
    except Exception as e:
        print(f"  ecriture 0x5f dans A8 impossible : {e} -> STOP (fail-closed).", flush=True); return
    pump_ep0(); sep.msgs[0x08].clear()
    print_dart_fault("avant 0x5f (baseline)")
    print("  envoi EP 0x08 TAG=0xfc TYPE=0x5f (LoadPatch : demande du patch au SEP)...", flush=True)
    sep.send_msg(SEPMessage(EP=0x08, TAG=0xfc, TYPE=PATCH_OP, PARAM=0x00, DATA=0x00000000))

    # --- (2) reassemblage multi-fragment (poignee fe/fd) ---
    reasm = bytearray(); total = None; frag_idx = 0; last_tag = None
    while True:
        tag, buf = recv_patch_fragment(f"frag{frag_idx}")
        if tag is None:
            print(f"  >>> pas de fragment 0x5f #{frag_idx} recu (SEP muet) -> STOP+dump (fail-closed).", flush=True)
            if outdir and reasm:
                open(os.path.join(outdir, "patch_partial.bin"), "wb").write(bytes(reasm))
            dump_wall(ctx, POST_0X73_STEPS[5], 5); return
        last_tag = tag
        # dump brut du fragment (tel que livre dans B8)
        if outdir and buf:
            try: open(os.path.join(outdir, f"patch_frag{frag_idx}_B.bin"), "wb").write(buf)
            except Exception: pass
        try:
            h = parse_frag_header(buf)
        except Exception as e:
            print(f"  >>> fragment #{frag_idx} illisible : {e} -> STOP+dump (fail-closed).", flush=True)
            dump_wall(ctx, POST_0X73_STEPS[5], 5); return
        print(f"  fragment #{frag_idx} (TAG=0x{tag:02x}) : op=0x{h['op']:02x} kind={h['kind']} total=0x{h['total']:x} "
              f"offset=0x{h['offset']:x} fraglen=0x{h['fraglen']:x} ; tete charge={h['payload'][:8].hex()}", flush=True)
        # garde-fous fail-closed : op attendu, kind=1, fragments EN ORDRE, total coherent
        if h["op"] != PATCH_OP or h["kind"] != 1:
            print(f"  >>> fragment #{frag_idx} inattendu (op=0x{h['op']:02x} kind={h['kind']}) -> STOP+dump.", flush=True)
            dump_wall(ctx, POST_0X73_STEPS[5], 5); return
        if total is None:
            total = h["total"]
        elif h["total"] != total:
            print(f"  >>> total incoherent (0x{h['total']:x} != 0x{total:x}) -> STOP+dump.", flush=True)
            dump_wall(ctx, POST_0X73_STEPS[5], 5); return
        if h["offset"] != len(reasm):
            print(f"  >>> fragment hors ordre : offset=0x{h['offset']:x} attendu 0x{len(reasm):x} -> STOP+dump.", flush=True)
            dump_wall(ctx, POST_0X73_STEPS[5], 5); return
        reasm += h["payload"]
        frag_idx += 1
        # complet ?
        if len(reasm) >= total:
            if tag != PATCH_TAG_LAST:
                print(f"  (note : patch complet mais dernier TAG=0x{tag:02x} != 0x{PATCH_TAG_LAST:02x} attendu — on continue le verdict)", flush=True)
            break
        # pas complet -> reclamer la suite (TAG=0xfe), tampon A INCHANGE
        if frag_idx >= MAX_FRAGS:
            print(f"  >>> trop de fragments ({frag_idx} >= MAX_FRAGS={MAX_FRAGS}) sans completion -> STOP+dump (fail-closed).", flush=True)
            dump_wall(ctx, POST_0X73_STEPS[5], 5); return
        pump_ep0(); sep.msgs[0x08].clear()
        print(f"  patch incomplet ({len(reasm)}/{total} o) -> reclame le fragment suivant (EP 0x08 TAG=0x{PATCH_TAG_MORE:02x} TYPE=0x5f)...", flush=True)
        sep.send_msg(SEPMessage(EP=0x08, TAG=PATCH_TAG_MORE, TYPE=PATCH_OP, PARAM=0x00, DATA=0x00000000))

    # --- (3) verdict auto-verifiant + dump du patch reassemble ---
    ok, why = verify_reassembled_patch(reasm, total)
    if outdir:
        try: open(os.path.join(outdir, "patch_reassembled.bin"), "wb").write(bytes(reasm))
        except Exception as e: print(f"  (ecriture patch_reassembled.bin impossible : {e})", flush=True)
    if not ok:
        print(f"  >>> RECON RATE : reassemblage INCOHERENT ({why}) -> STOP+dump. Patch partiel dans $OUT/patch_reassembled.bin.", flush=True)
        dump_wall(ctx, POST_0X73_STEPS[5], 5); return
    print(f">>> PATCH RECU + REASSEMBLE : {len(reasm)} o en {frag_idx} fragment(s), total declare 0x{total:x}, "
          f"prefixe 2 o == total-2 (forme VU C12/C19). La LIVRAISON du patch SEP->AP a MARCHE nativement. "
          f"On ENCHAINE le PUSH au capteur (ci-dessous). NE PAS conclure 'Touch ID marche' : restent les params, "
          f"la calibration, le match, l'enrolement.", flush=True)

    # --- (4) construire la trame SPI de push : prelude 0x60 + bloc brut (dump avant d'emettre) ---
    block = bytes(reasm)
    push = PATCH_PRELUDE + block
    if outdir:
        try:
            open(os.path.join(outdir, "patch_spi_prelude.bin"), "wb").write(PATCH_PRELUDE)
            open(os.path.join(outdir, "patch_spi_push.bin"), "wb").write(push)
        except Exception as e: print(f"  (ecriture dump push impossible : {e})", flush=True)
    print(f"  trame de push CONSTRUITE : prelude {PATCH_PRELUDE.hex()} (7 o) + bloc {len(block)} o "
          f"= {len(push)} o. Dumpee dans $OUT/patch_spi_push.bin.", flush=True)

    # --- (5) PUSH du patch AU CAPTEUR (NOUVEAU sbio7) : prelude 0x60 puis le bloc en UN xfer FIFO scrute ---
    #     ⚠️ CS-HOLD : un transfert FIFO de 22 Ko doit garder CS asserte tout du long. On ne peut PAS le tester
    #     hors-ligne ; mesa.xfer remplit le FIFO des qu'il y a de la place (le plus continu possible) et on
    #     allonge le timeout. Si le controleur de-asserte CS en cours (FIFO vide entre deux remplissages) le
    #     patch arrive casse : issue traitee comme un echec (STOP+dump -> DMA SIO sbio8).
    if mesa is None:
        print("  capteur non disponible : PUSH non lance (fail-closed).", flush=True); return
    from analysis.mesa_spi_proxy import MesaError, STATUS_HEAD

    def _read_sensor_status(when):
        """Lit l'etat capteur (0x10) et le dumpe. Rend (body|None). Ne leve pas : rend None en cas d'echec."""
        try:
            st = mesa.status()
        except Exception as e:
            print(f"  SPI< etat capteur {when} : LECTURE IMPOSSIBLE ({e})", flush=True); return None
        if outdir:
            try: open(os.path.join(outdir, f"push_status_{when}.bin"), "wb").write(bytes(st))
            except Exception: pass
        well = len(st) >= 4 and bytes(st[:4]) == STATUS_HEAD
        print(f"  SPI< etat capteur {when} ({len(st)} o) : {bytes(st).hex()} "
              f"[en-tete {'OK (80 20 00 10)' if well else 'INATTENDU'}]", flush=True)
        return bytes(st)

    # (a) etat capteur AVANT le push (baseline)
    st_before = _read_sensor_status("avant")

    # (b) emettre le prelude (7 o, rx_len=0) — petit, sans risque
    try:
        print(f"  SPI> prelude du push {PATCH_PRELUDE.hex()} (7 o, rx_len=0)...", flush=True)
        mesa.xfer(PATCH_PRELUDE, 0); time.sleep(0.01)
    except MesaError as e:
        print(f"  >>> prelude 0x60 ECHOUE : {e} -> STOP+dump (fail-closed).", flush=True)
        dump_wall(ctx, POST_0X73_STEPS[5], 5); return

    # (c) emettre le bloc patch en UN xfer (rx_len=0, timeout eleve) — LE test CS-hold
    print(f"  SPI> bloc patch {len(block)} o en UN transfert (rx_len=0, timeout {PATCH_PUSH_TIMEOUT_S:.0f}s). "
          f"⚠️ CS-maintenu NON TESTE hors-ligne.", flush=True)
    t_push = time.time()
    try:
        mesa.xfer(block, 0, timeout=PATCH_PUSH_TIMEOUT_S)
    except MesaError as e:
        dt = time.time() - t_push
        print(f"  >>> PUSH du bloc {len(block)} o ECHOUE apres {dt:.1f}s : {e}", flush=True)
        print("  >>> VERDICT : le FIFO scrute NE TIENT PAS les 22 Ko (timeout / CS lache mi-parcours). "
              "Il faut le DMA SIO (sbio8). Le capteur est peut-etre MI-PATCHE : le teardown (power_off) le "
              "power-cycle et le recupere.", flush=True)
        _read_sensor_status("apres-echec")
        dump_wall(ctx, POST_0X73_STEPS[5], 5); return
    dt = time.time() - t_push
    print(f"  bloc patch EMIS en {dt:.1f}s (prelude 0x60 + bloc en 2 transferts SPI, pas de read-back attendu).", flush=True)

    # (d) etat capteur APRES le push
    st_after = _read_sensor_status("apres")

    # (e) ecouter un court instant si le SEP enchaine spontanement (EP 0x08) — diagnostic
    pump_ep0(); spont = []; t0 = time.time()
    while time.time() - t0 < WALL_LISTEN:
        pump_ep0()
        while sep.msgs[0x08]:
            m = sep.msgs[0x08].popleft(); spont.append((m.TAG, m.TYPE, m.PARAM, m.DATA))
            print(f"    SEP> EP=0x08 TAG=0x{m.TAG:02x} TYPE=0x{m.TYPE:02x} PARAM=0x{m.PARAM:02x} DATA=0x{m.DATA:08x}", flush=True)
        time.sleep(0.02)
    if not spont:
        print("  (aucun message EP 0x08 spontane apres le push : comme macOS, le SEP ATTEND que l'AP pilote la "
              "commande suivante (0x5d applySensorParams) — NON envoyee ce run.)", flush=True)

    # (f) VERDICT du push : le patch = status only (pas de read-back, sbio_session.md §3). On juge sur l'etat
    #     capteur relu : bien forme (en-tete 80 20 00 10) = push emis + capteur repond ; illisible = push casse.
    well_after = st_after is not None and len(st_after) >= 4 and st_after[:4] == STATUS_HEAD
    changed = (st_before is not None and st_after is not None and st_after != st_before)
    if well_after:
        print(f">>> PUSH EMIS : le bloc patch {len(block)} o a ete transmis au capteur en FIFO scrute SANS timeout, "
              f"et l'etat capteur relu (0x10) est BIEN FORME{' (et a CHANGE vs avant)' if changed else ''}. "
              "Le patch = status only (pas de read-back, sbio_session.md §3) : status lisible = signe que le push "
              "a ete accepte. ⚠️ NE PAS conclure 'CS tenu prouve' sans recouper l'etat 'patch charge' (C19 "
              "'00 29 01 00 7c'...) ; et surtout PAS 'Touch ID marche' : restent les params 0x5d/0x5c/0x55, la "
              "calibration, le match, l'enrolement.", flush=True)
    else:
        print(">>> PUSH EMIS mais ETAT CAPTEUR APRES ILLISIBLE/INCOHERENT (en-tete != 80 20 00 10) : le push est "
              "PROBABLEMENT casse (CS lache en cours ?) -> il faut le DMA SIO (sbio8). STOP+dump.", flush=True)
        dump_wall(ctx, POST_0X73_STEPS[5], 5)

    # --- (6) STOP : on n'enchaine PAS les params. Teardown capteur dans le finally EXTERNE. ---
    print("=== PHASE 6 terminee (PUSH teste). On N'ENCHAINE PAS les params (0x5d...) ce run. Le capteur est remis "
          "dans l'etat d'iBoot (power_off + restore) dans le finally EXTERNE, MEME si le push a casse. ===", flush=True)

# ===========================================================================
# PHASE 1 — boucle native PERSIST (identique a sep_native_sbio2.sh) : ACK + STOCKE les SAVE.
# ===========================================================================
counts = defaultdict(int); nsave = 0; last = time.time(); verdict = "idle"
print(f"=== PHASE 1 — PERSIST : on ACQUITTE + STOCKE les SAVE (ecriture), budget {MAX_SAVES}, idle {IDLE}s ===", flush=True)
while time.time() - last < IDLE:
    m = next_sep_13(timeout_s=2)
    if m is None: continue
    last = time.time(); op = m.TYPE; counts[op] += 1; name = OPNAME.get(op, f"op_0x{op:02x}")
    if op == OP_FWBOOT:
        write_A(b""); send(m, RESP_DONE, 0x00, 0x00000100); print(f"  {name} TAG=0x{m.TAG:02x} -> ack", flush=True)
    elif op == OP_OSUUID:
        if OS_UUID_MODE == "none": send(m, 0x02, 0x00, 0x00000000); print(f"  {name} -> pas d'UUID (TYPE=0x02)", flush=True)
        else: write_A(LINUX_OS_UUID); send(m, RESP_DONE, 0x00, 0x00000000); print(f"  {name} -> UUID Linux", flush=True)
    elif op == OP_FETCH_MASTER:
        print(f"  {name} TAG=0x{m.TAG:02x} DATA=0x{m.DATA:08x} -> {serve_master(m)}", flush=True)
    elif op == OP_FETCH_GL:
        print(f"  {name} TAG=0x{m.TAG:02x} -> {serve_gl(m)}", flush=True)
    elif op == OP_ABSENT:
        send(m, RESP_DONE, 0x00, 0x00000000); print(f"  {name} TAG=0x{m.TAG:02x} -> ack", flush=True)
    elif op == OP_ANNOUNCE:
        send(m, RESP_ANNOUNCE, 0x00, m.DATA & ACK_MASK)
        ep = "".join(chr((m.DATA >> (i*8)) & 0xff) for i in (2,1,0))
        print(f"  {name} ('{ep}') -> ack 0x16", flush=True)
    elif op in (OP_SAVE_XART, OP_SAVE_LOCKER):
        nsave += 1; tag, ln = handle_save(m)
        print(f"  {name} TAG=0x{m.TAG:02x} -> ACK + STOCKE {tag} ({ln}o) [SAVE #{nsave}/{MAX_SAVES}]", flush=True)
        if nsave >= MAX_SAVES:
            verdict = "budget_atteint"; print(f"  >>> {MAX_SAVES} SAVE sans stabilisation = MEME MUR QUE VOIE C. STOP.", flush=True); break
    else:
        verdict = "op_inconnue"; print(f"  op INCONNUE 0x{op:02x} TAG=0x{m.TAG:02x} -> STOP (fail-closed).", flush=True); break

print("--- bilan : " + ", ".join(f"{OPNAME.get(o,hex(o))}x{c}" for o, c in sorted(counts.items())), flush=True)
print(f"--- verdict flux : {verdict} (idle = le SEP s'est stabilise apres les SAVE)", flush=True)
print("endpoints finaux : " + ", ".join(f"0x{n:02x}:{nm}" for n, nm in sorted(sep.epnum2name.items())), flush=True)
print(f"store apres run : maitres={sorted(store_masters)}, gl={len(store_gls)}, gl_bruts={len(gl_raw)} (dans {XART_STORE})", flush=True)

# ---------------------------------------------------------------------------
# PHASE 2 + 3 + 4 + 5 + 6 : seulement si le SEP s'est STABILISE (idle) ET a annonce sbio (0x08).
#   Le capteur (MesaSPI) est alimente en Phase 3 et VIT jusqu'a la fin ; le TEARDOWN (power_off + restore)
#   est ICI, dans le finally EXTERNE, et s'execute MEME en cas d'erreur de la Phase 3, 4, 5 ou 6.
#   La Phase 6 EMET le push AU CAPTEUR (spi2) ; le power_off du finally power-cycle un eventuel etat mi-patche.
# ---------------------------------------------------------------------------
if verdict != "idle":
    print(f">>> Flux non stabilise (verdict={verdict}) : sonde + franchissement NON lances (fail-closed).", flush=True)
elif 0x08 not in sep.epnum2name:
    print(">>> SEP stabilise mais sbio (0x08) non annonce : rien a sonder.", flush=True)
else:
    ctx = probe_sbio()
    mesa = None
    try:
        mesa, crossed = phase3(ctx)
        if crossed and mesa is not None:
            kx_ok = phase4(ctx, mesa)
            if kx_ok:
                cnt_ok = phase5(ctx, mesa)
                if cnt_ok:
                    phase6(ctx, mesa)
                else:
                    print(">>> compteur non relaye : Phase 6 (patch 0x5f + push) non lancee (fail-closed).", flush=True)
            else:
                print(">>> key exchange non relaye : Phase 5 (compteur 0x42/0x18) non lancee (fail-closed).", flush=True)
        else:
            print(">>> 0x17 non franchi : Phase 4 (key exchange 0x15/0x16) non lancee (fail-closed).", flush=True)
    finally:
        # TEARDOWN capteur EXTERNE : remettre spi2 + broche 196 dans l'etat d'iBoot, MEME en cas d'erreur.
        if mesa is not None:
            try: mesa.power_off(); print("  capteur ETEINT (power_off).", flush=True)
            except Exception as e: print(f"  (power_off a echoue : {e})", flush=True)
            try: mesa.restore(); print("  spi2 + broche 196 REMIS dans l'etat d'iBoot (restore).", flush=True)
            except Exception as e: print(f"  (restore a echoue : {e})", flush=True)
PY
