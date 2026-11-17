#!/usr/bin/env bash
# =============================================================================
# pending/dfu_restore.sh  —  BOUTON « DFU RESET » (RESTORE USINE DU MAC)
# =============================================================================
# BUT      : restaurer (RESET usine) le MacBook Pro 14" M1 Max (j314c) depuis ce
#            PC Linux, en mode DFU, avec idevicerestore. Remet la puce (SEP) et le
#            firmware à zéro → répare le bootloop côté Apple.
#
# RISQUE   : *** DESTRUCTIF *** — EFFACE TOUT LE DISQUE INTERNE DU MAC :
#            macOS, le macOS 13.5 du projet, ALARM (Linux quotidien) ET le Linux
#            de test. Tout part. Restaure le macOS le PLUS RÉCENT (27.2.1), pas 13.5.
#            Une coupure (USB / courant) pendant l'opération peut rendre le Mac
#            inutilisable jusqu'à une nouvelle restauration DFU → garder le portable
#            sur secteur, ne rien débrancher.
#
# RÉSULTAT ATTENDU : idevicerestore téléverse l'IPSW au Mac en DFU, le Mac reboote
#            sur un macOS 27.2.1 neuf (assistant de configuration). Ensuite : Verrou
#            d'activation possible (identifiant Apple + mot de passe exigés).
#
# AVANT DE LANCER (3 verrous — à confirmer soi-même, le script ne peut pas vérifier) :
#   1. SAUVEGARDE d'ALARM faite et VÉRIFIÉE (données récupérables). <-- actuellement
#      illisible : dépôt restic derrière le pool ZFS `latif` (module ZFS pas construit
#      pour le noyau courant). Faire une sauvegarde fraîche AVANT.
#   2. Identifiant Apple + mot de passe du Mac CONNUS (sinon Verrou d'activation bloque).
#   3. Accepter que les 4 partitions soient effacées.
#
# Ce script NE LANCE RIEN tant que : l'IPSW n'est pas présent ET son sha256 exact,
# l'outil pas installé, usbmuxd pas lancé, ou le Mac pas vu en DFU. Confirmation
# tapée obligatoire (sauf YES=1). Lancé par Albert uniquement (jamais l'agent).
# -----------------------------------------------------------------------------
set -euo pipefail

IPSW="${IPSW:-$HOME/mac-dfu/UniversalMac_27.2.1_26B131_Restore.ipsw}"
SHA256_ATTENDU="233e85a09887579d47d0b195e7db72be7f204261059c6946f719acf6b300814f"

red()  { printf '\033[31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[32m%s\033[0m\n' "$*"; }
die()  { red "ARRÊT : $*"; exit 1; }

echo "=== Vérifications avant DFU restore ==="

# 1) IPSW présent + complet
[ -f "$IPSW" ] || die "firmware introuvable : $IPSW (le téléchargement n'est pas fini ?)"
taille=$(stat -c%s "$IPSW")
echo "Firmware : $IPSW ($taille octets)"
[ "$taille" = "25595954706" ] || die "taille inattendue ($taille, attendu 25595954706) → téléchargement incomplet. Relancer le téléchargement."

# 2) sha256 exact
echo "Vérification sha256 (peut prendre ~1 min)…"
sha=$(sha256sum "$IPSW" | awk '{print $1}')
[ "$sha" = "$SHA256_ATTENDU" ] || die "sha256 NON conforme → firmware corrompu. Attendu $SHA256_ATTENDU, obtenu $sha."
grn "sha256 OK."

# 3) outil présent
command -v idevicerestore >/dev/null || die "idevicerestore absent. L'installer d'abord :  yay -S idevicerestore usbmuxd libirecovery"

# 4) usbmuxd lancé
if ! pgrep -x usbmuxd >/dev/null; then
  echo "usbmuxd pas lancé → démarrage (sudo)…"
  sudo systemctl start usbmuxd 2>/dev/null || sudo usbmuxd || true
  pgrep -x usbmuxd >/dev/null || die "usbmuxd ne démarre pas. L'installer/activer :  sudo systemctl enable --now usbmuxd  (ou  sudo usbmuxd )"
fi
grn "usbmuxd actif."

# 5) Mac vu en DFU sur l'USB (Apple = vendeur 05ac)
echo "Recherche du Mac en DFU sur l'USB…"
if ! lsusb -d 05ac: 2>/dev/null | grep -qi "."; then
  red "Aucun appareil Apple (05ac:) détecté sur l'USB."
  red "→ Mets le Mac en DFU AVANT de continuer (voir docs/RECUPERATION_MAC.md),"
  red "  câble USB-C data direct (pas de hub), et relance ce script."
  die "Mac pas en DFU."
fi
echo "Appareil Apple détecté :"
lsusb -d 05ac:
echo "(l'écran du Mac doit rester NOIR = DFU ; s'il affiche un logo, ce n'est pas du DFU)"

# 6) Confirmation destructrice
echo
red "############################################################"
red "#  CECI EFFACE TOUT LE DISQUE DU MAC. IRRÉVERSIBLE.        #"
red "#  Sauvegarde ALARM vérifiée ? Identifiant Apple connu ?   #"
red "############################################################"
if [ "${YES:-}" != "1" ]; then
  read -r -p 'Taper exactement  EFFACER-ET-RESTAURER  pour lancer : ' rep
  [ "$rep" = "EFFACER-ET-RESTAURER" ] || die "annulé (confirmation non saisie)."
fi

echo
grn ">>> Lancement de la restauration. NE RIEN DÉBRANCHER. Garder le Mac sur secteur."
echo ">>> Commande : sudo idevicerestore -e \"$IPSW\""
echo
exec sudo idevicerestore -e "$IPSW"
