#!/usr/bin/env bash
# =============================================================================
# pending/recable_boot_image.sh — RECÂBLER LE BOOT D'ALARM après restauration
#                                  par IMAGE BLOC (dd de alarm_p5.img sur p8)
# =============================================================================
# CONTEXTE : le DFU Restore a tout effacé. On a réinstallé Asahi en "UEFI only"
#            (option 5 → m1n1 + U-Boot + une ESP neuve, SANS OS ni GRUB), puis
#            copié l'image bloc d'ALARM (LUKS 123dfd25…) par dd sur la nouvelle
#            partition Linux. Tout le système chiffré (y compris /boot : noyau,
#            initramfs, modules GRUB) est restauré À L'OCTET PRÈS.
#            Il MANQUE seulement le lanceur sur l'ESP : grubaa64.efi + grub.cfg
#            (l'ancienne ESP n'était PAS dans la sauvegarde — vérifié).
#
# BUT      : depuis l'ALARM restauré DÉMARRÉ EN TETHERED (tools/tethered_boot.sh
#            alarm, noyau envoyé par USB depuis le PC), régénérer le lanceur sur
#            la NOUVELLE ESP et recâbler m1n1, pour que le Mac reboote ensuite
#            tout seul sur ALARM.
#
# CE QUE ÇA FAIT (dans l'ALARM tethered, en root) :
#   1. identifie la nouvelle ESP (vfat "EFI - ALARM") et vérifie le LUKS 123dfd25…
#   2. corrige l'UUID de l'ESP dans /etc/fstab (ancienne 979C-1809 -> nouvelle)
#   3. grub-install --removable vers la nouvelle ESP (embarque cryptodisk+luks+btrfs)
#   4. grub-mkconfig  (UUID LUKS 123dfd25… conservé -> inchangé)
#   5. update-m1n1    (rafraîchit m1n1 sur l'ESP ; non bloquant)
#
# CE QUE ÇA NE FAIT PAS : aucune écriture SEP, aucun dd, aucun partitionnement,
#            aucune commande Apple (bputil/kmutil/csrutil/nvram). On n'écrit QUE
#            sur la nouvelle ESP et dans le système restauré (fstab, /boot).
#
# RISQUE   : grub-install --removable écrit /EFI/BOOT/BOOTAA64.EFI sur l'ESP
#            choisie. Si on désigne la MAUVAISE partition, on abîme un autre
#            lanceur. => le script affiche tout et demande OUI avant d'écrire.
#            Boot policy / install m1n1 = domaine d'Albert : c'est LUI qui lance.
#
# PRÉREQUIS : lancé EN ROOT dans l'ALARM restauré tethered-booté. LUKS 123dfd25…
#            déjà ouvert et "/" monté (c'est le cas en mode `alarm`).
# -----------------------------------------------------------------------------
set -euo pipefail

DISK=/dev/nvme0n1
LUKS_UUID_ATTENDU="123dfd25-0a64-4837-87fe-ec02441992da"
OLD_ESP_UUID="979C-1809"          # ancienne ESP (dans l'fstab restauré)

red()  { printf '\e[31m%s\e[0m\n' "$*"; }
grn()  { printf '\e[32m%s\e[0m\n' "$*"; }
step() { printf '\n\e[1;34m==> %s\e[0m\n' "$*"; }
ask()  { read -rp "$1 [tape OUI] " r; [ "$r" = OUI ] || { red "Annulé."; exit 1; }; }

[ "$(id -u)" = 0 ] || { red "À lancer en root, dans l'ALARM tethered."; exit 1; }

step "0/5 Vérif qu'on est bien dans l'ALARM restauré"
echo "Racine montée :"; findmnt -no SOURCE,FSTYPE / || true
if ! grep -q "$LUKS_UUID_ATTENDU" /etc/default/grub 2>/dev/null; then
  red "ATTENTION : LUKS $LUKS_UUID_ATTENDU pas trouvé dans /etc/default/grub."
  red "On n'est peut-être pas dans le bon système. Je m'arrête."
  exit 1
fi
grn "OK : /etc/default/grub référence bien le LUKS d'ALARM."

step "1/5 Repérage de la nouvelle ESP"
echo "Partitions vfat sur $DISK :"
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,UUID "$DISK" | grep -E 'NAME|vfat' || true
echo
echo "Le LUKS restauré (doit afficher UUID=$LUKS_UUID_ATTENDU) :"
blkid | grep -i crypto_LUKS || true
echo
CAND=$(blkid -t TYPE=vfat -o device | while read -r d; do
         lbl=$(blkid -s LABEL -o value "$d" 2>/dev/null || true)
         case "$lbl" in *ALARM*|*EFI*) echo "$d";; esac
       done | head -1 || true)
read -rp "Partition ESP à utiliser [${CAND:-?}] : " ESP; ESP=${ESP:-$CAND}
[ -b "$ESP" ] || { red "ESP invalide : $ESP"; exit 1; }
NEW_ESP_UUID=$(blkid -s UUID -o value "$ESP")
echo "ESP choisie : $ESP (UUID $NEW_ESP_UUID)"
red "VÉRIFIE que c'est bien la NOUVELLE ESP (~500 Mo, label EFI - ALARM), PAS une partition macOS."
ask "C'est la bonne ESP ?"

step "2/5 Montage ESP + correction fstab (UUID ESP)"
mkdir -p /efi
mountpoint -q /efi && umount /efi || true
mount "$ESP" /efi
ls -la /efi; echo
if grep -q "$OLD_ESP_UUID" /etc/fstab; then
  cp /etc/fstab /etc/fstab.pre-recable
  sed -i "s/$OLD_ESP_UUID/$NEW_ESP_UUID/g" /etc/fstab
  echo "fstab : UUID ESP $OLD_ESP_UUID -> $NEW_ESP_UUID (sauvegarde : /etc/fstab.pre-recable)"
else
  echo "fstab ne contient pas $OLD_ESP_UUID (déjà corrigé ?) — ligne /efi actuelle :"
  grep -E '/efi' /etc/fstab || true
fi

step "3/5 grub-install vers la nouvelle ESP"
echo "Contenu actuel de /etc/default/grub (rappel, LUKS conservé) :"
grep -E 'CRYPTODISK|rd.luks' /etc/default/grub || true
ask "Lancer grub-install --removable sur $ESP (écrit /EFI/BOOT/BOOTAA64.EFI) ?"
grub-install --target=arm64-efi --efi-directory=/efi --removable --boot-directory=/boot --recheck
ls -la /efi/EFI/BOOT/ || true

step "4/5 grub-mkconfig"
grub-mkconfig -o /boot/grub/grub.cfg
grep -c cryptomount /boot/grub/grub.cfg >/dev/null && grn "grub.cfg généré (cryptomount présent)." || \
  red "ATTENTION : pas de cryptomount dans grub.cfg — vérifier GRUB_ENABLE_CRYPTODISK=y."

step "5/5 update-m1n1 (non bloquant)"
if command -v update-m1n1 >/dev/null; then
  update-m1n1 || red "update-m1n1 a échoué (non bloquant — m1n1 de l'installeur reste en place)."
else
  red "update-m1n1 absent (paquet asahi-scripts ?) — m1n1 de l'installeur reste en place."
fi

sync
step "Terminé"
echo "Vérifie /etc/fstab (ligne /efi) puis, pour revenir proprement :"
echo "  umount -R /efi 2>/dev/null; sync"
echo "Ensuite power-cycle du Mac : m1n1 -> U-Boot -> GRUB (passphrase LUKS) -> ALARM."
echo "Si le boot tombe en urgence sur /efi : ajouter 'nofail' à la ligne /efi de fstab et refaire grub-mkconfig."
