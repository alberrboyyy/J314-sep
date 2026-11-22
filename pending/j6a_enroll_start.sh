#!/usr/bin/env bash
# BUT : J6a = expérience E-ENROLL-START « avec doigt » (docs/j6_enroll_match_protocol.md §6, docs/hypotheses.md
#       E-ENROLL-START). Depuis un reboot : J5c pass2 INCHANGÉ (boot SEPOS, xART, sbio 0x73, 1re passe + 0x5b + 0x63,
#       2e passe jusqu'aux deux 0x63 = macOS), capteur LAISSÉ ALLUMÉ au repos final de macOS, puis :
#         1. UN SEUL sbio 0x03 commandStartEnroll, charge = enroll_indata_v2_t de 68 octets TOUS À ZÉRO
#            (sbio_gate::ENROLL_INDATA_MIN). Champ par champ :
#              - longueur 0x44 = 68 o : VU kext (sepTransact(0x03, in, inLen=0x44, out=0), docs/sbio_enroll.md §4) ;
#              - u32 +0x00 = 0 : VU kext que le kext lit ce u32 et garde son bit 0 comme drapeau ; SENS INCONNU ; 0 =
#                aucun drapeau posé (la proposition antérieure u32[0]=1 devinait le sens de ce bit : abandonnée) ;
#              - +0x04 .. +0x43 (64 o) = 0 : AUCUNE information (le kext ne les lit pas, aucun gabarit ni valeur par
#                défaut dans le kext ; producteur biometrickitd non reversé ; aucune capture d'enrôlement). Zéro = aucun
#                octet inventé, mais RIEN ne dit que le SEP accepte une structure nulle : HYPOTHÈSE.
#         2. ÉCOUTE 90 s : tout mot EP 0x08 du SEP (notification ou non) journalisé avec le dump hex de B8 ; IRQ gpio195
#            surveillée, UNE lecture d'état capteur par montée (motif macOS), rien d'autre sur SPI (l'image annoncée
#            n'est jamais lue). Guidage dans le journal : « POSEZ LE DOIGT » à t=5 s, « RETIREZ » à 15 s, « REPOSEZ » à
#            25 s, etc. (toutes les 10 s), « FIN » à 90 s. AUCUNE réponse au SEP : aucune requête SEP→AP n'a de réponse
#            établie dans j6_enroll_match_protocol.md (le relais d'image 0x65 est une commande AP de la capture, jamais
#            demandée par le SEP) ; une requête du SEP (TAG fc/fe/fd, opcode) est enregistrée, jamais servie.
#         3. VERDICT : réponse au 0x03 (ACK vide / réponse non conforme avec mot + B8 exacts / SILENCE 6 s / Halted) +
#            liste des mots sbio de l'écoute + nombre de montées d'IRQ et de lectures d'état.
#       Jamais : 0x06, 0x23, 0x09, 0x65, 0x6d, 0x6c, ni rien d'autre après le 0x03 (le noyau refuse toute commande
#       en écoute) ; jamais l'EP 0x12 (SKS) ; jamais de gigalocker.
# ENDPOINTS TOUCHÉS : ceux de pending/j5c_params_run.sh UPTO=pass2 (0xFF/0xFE boot, 0x00 CNTL, 0x13 xART avec SAVE
#       acquittés, 0x08 : 0x73 puis la liste blanche des deux passes), PLUS sur 0x08 un `> fc TYPE 0x03` (A8 = gt_packet
#       { 1, 0x44, 0, 0x03, 0x44 } + 68 zéros), une fois. Noyau : allow_sbio_params=3 allow_sbio_bio=1. Capteur : celui
#       de pass2, puis seulement des lectures d'état (80 10) après une montée de gpio0 195 (300 au plus) ; extinction
#       (gpio0 196 = 0) à la fin, dans tous les chemins.
# RISQUE : classe NEUVE d'écriture SEP (entrée en mode enrôlement, jamais faite hors macOS ; payload deviné) → 1er run =
#       « go » d'Albert. Le SEP peut se figer ou ne plus répondre (Halted côté noyau ou SEP muet) → power-cycle
#       (Albert). Effet sur l'état biométrique du SEP (mode enrôlement laissé ouvert, gabarit partiel, compteurs) :
#       INCONNU ; rien n'est persisté côté AP (pas de 0x6c), le xART frais de ce run peut avancer comme en J5c. Touch ID
#       macOS déjà sacrifié (accepté). Filet : alarm_p5.img + backup d'Albert + DFU.
# RÉSULTAT ATTENDU : ligne « VERDICT : E-ENROLL-START : réponse au 0x03 = … » de sbiod (l'expérience est réussie quelle
#       que soit la réponse : c'est elle qu'on veut) ; sinon « arrêt (fail-closed) : <raison> » (pass2 non conforme →
#       aucun 0x03 envoyé) ou HALTED dans dmesg. Prédiction (avant run) : refus avec un code dans B8 ou silence si le SEP
#       exige keybag / acmContext / un indata valide ; ACK vide s'il entre en mode enrôlement ; dans ce cas, avec doigt,
#       possible notification ou rien (la capture est pilotée par l'AP : 0x23/0x06/0x65, NON envoyés).
# PRÉPARÉ PAR : agent driver (session ALARM), 2026-11-22. JAMAIS LANCÉ ; 1er run = « go » d'Albert.
#
# Usage (root, après un reboot, doigt prêt mais RIEN sur le capteur avant « POSEZ LE DOIGT ») :
#   pending/j6a_enroll_start.sh [STORE]
#   Fichiers dans $J5 (défaut /home/albert/kbuild/j5) : ceux de j5c_params_run.sh, avec sep_native.ko J6a (paramètre
#   allow_sbio_bio) et sbiod J6a (--upto enroll-start).
set -euo pipefail
J5=${J5:-/home/albert/kbuild/j5}
REPO=$(cd "$(dirname "$0")/.." && pwd)
C12=$REPO/traces/20261108-032454_c12-boot-ho/sep.log.ool
CALIB=$J5/calib_0x5b.bin
SHA=d5a6117dc8b5482320ab4d86c94148f190a7b08530c6235735636b9abd23ddda
die() { echo "STOP : $*" >&2; exit 1; }
USAGE=$("$J5/sbiod" 2>&1 || true)
grep -q -- "enroll-start" <<<"$USAGE" || die "$J5/sbiod sans --upto enroll-start (binaire J6a ?)"
modinfo -F parm "$J5/sep_native.ko" | grep -q "^allow_sbio_params:.*3 = " || die "$J5/sep_native.ko sans le niveau 3"
modinfo -F parm "$J5/sep_native.ko" | grep -q "^allow_sbio_bio:.*1 = after the 2nd 0x63" || die "$J5/sep_native.ko sans allow_sbio_bio=1 (module J6a ?)"
[ -e "$CALIB" ] || "$J5/sbiod" calib-prepare --from "$C12" --out "$CALIB"
[ "$(sha256sum "$CALIB" | cut -d' ' -f1)" = "$SHA" ] || die "$CALIB : sha256 ≠ $SHA"
cat <<'TXT'
J6a E-ENROLL-START : 2e passe (~1 min), puis UN 0x03, puis ÉCOUTE 90 s.
  Doigt prêt, mais NE TOUCHEZ PAS le capteur avant la ligne « POSEZ LE DOIGT ».
  Suivez ensuite les lignes >>>>> POSEZ / RETIREZ / REPOSEZ <<<<< (toutes les 10 s).
TXT
echo "J6a : allow_sbio_params=3 allow_sbio_bio=1, sbiod --upto enroll-start --calib $CALIB"
SBIO_PARAMS=3 SBIO_BIO=1 SBIOD_ARGS="--upto enroll-start --calib $CALIB" exec "$REPO/pending/j5_sensor_run.sh" "$@"
