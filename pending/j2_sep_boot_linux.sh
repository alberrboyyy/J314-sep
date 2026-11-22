#!/usr/bin/env bash
# =============================================================================
# j2_sep_boot_linux.sh — J2 : faire démarrer SEPOS par le pilote Linux `sep.rs` (noyau ALARM stock), en
#                         tethered boot, avec un DTB qui active le SEP. RIEN n'est écrit sur le disque du Mac.
#
# BUT : premier démarrage de SEPOS **depuis Linux natif** (roadmap J2). Le noyau ALARM contient déjà le pilote
#   `drivers/soc/apple/sep.rs` (CONFIG_APPLE_SEP=y), mais il ne se lie à rien : le nœud `sep@396400000` est
#   `disabled` et il n'y a pas d'alias `sep`. Sans alias, m1n1 ne réserve pas la zone `sepfw`, et la sonde de
#   `sep.rs` échoue de toute façon (`reserved_mem_region_to_resource_byname("sepfw")`, sep.rs:346).
#   On démarre donc ALARM en tethered boot (tools/tethered_boot.sh, déjà éprouvé le 2026-11-11), avec le DTB
#   du noyau qui tourne + exactement 2 changements :
#     1. /aliases/sep = "/soc/sep@396400000"   → m1n1 (kboot, dt_set_sep) réserve SEPFW et copie les manifestes ;
#     2. /soc/sep@396400000 status = "okay"     → `sep.rs` se lie au SEP.
#   Au démarrage, `sep.rs` envoie de lui-même BOOT_TZ0 (EP 0xFF), attend 0x69 puis 0xD2, envoie BOOT_IMG4
#   (EP 0xFF, IOVA du firmware) + SET_SHMEM (EP 0xFE), attend 0x6A (sep.rs:198-252). Ce script N'ENVOIE RIEN
#   au SEP lui-même : c'est le pilote public du noyau qui le fait, au boot.
#
# ENDPOINTS TOUCHÉS : 0xFF (BOOT_TZ0, BOOT_IMG4) et 0xFE (SET_SHMEM), envoyés par sep.rs. sep.rs IGNORE tous les
#   autres EP (sep.rs:281 `_ => {}`) : il n'acquitte AUCUN message xART 0x13 (donc aucun SAVE, aucun compteur
#   scellé avancé), aucun 0x12 SKS, aucun 0x08 sbio. Rien vers le Secure Element « Stockholm ».
#
# RISQUE :
#   - Classe « boot IMG4 » = déjà éprouvée sous m1n1 (route native, CLAUDE.md) ; mais 1er run de CE script et
#     1er boot SEPOS par le pilote Linux → GO D'ALBERT OBLIGATOIRE.
#   - IMG4 refusé / malformé = panique SEP (doc Asahi) jusqu'au prochain reboot. Le firmware est celui préchargé
#     par iBoot (pas fabriqué par nous).
#   - Le SEP, une fois SEPOS lancé, enverra des requêtes (xART 0x13 etc.) que sep.rs ignore : il peut rester
#     bloqué en attente. Sans conséquence persistante attendue (aucun acquittement = aucune écriture scellée).
#   - macOS : déjà déclaré sacrifiable par Albert (2026-11-22). Filet : alarm_p5.img + DFU.
#   - Rien sur le disque, ni dans la chaîne de démarrage : un reboot normal du Mac revient au DTB stock (sans SEP).
#     Si le Mac fige : appui long sur le bouton d'alimentation, puis rallumage normal (power-cycle = Albert).
#
# RÉSULTAT ATTENDU (à lire dans le journal noyau d'ALARM après le boot) :
#   - succès : sonde `apple-sep` sans erreur, puis les ACK 0x69 → 0xD2 → 0x6A (sep.rs ne les affiche pas tous :
#     on compte sur l'absence d'erreur + la présence de messages de découverte 0xFD si le noyau les journalise) ;
#   - échec propre : « sep alias not found » côté m1n1, ou erreur de sonde `sepfw` → le pilote ne démarre pas.
#   Commande de lecture (sur ALARM) : `journalctl -k -b --no-pager | grep -iE 'sep|rtkit|396400000'`.
#
# PRÉCONDITIONS (vérifiées avant d'envoyer quoi que ce soit ; le script s'arrête sinon) :
#   P1. À vérifier par la session PC dans m1n1/src/kboot.c : le chemin `proxyclient/tools/linux.py` appelle bien
#       `kboot_prepare_dt` → `dt_set_sep` (sinon l'alias ne sert à rien en tethered boot).
#   P2. Noyau + initramfs = ceux du noyau ALARM qui tourne (7.2.12-3-1-ARCH), copiés depuis /boot d'ALARM, et
#       DTB source = /usr/lib/modules/7.2.12-3-1-ARCH/dtbs/t6001-j314c.dtb (DTB complet : clavier, écran).
#   P3. Le DTB produit ne diffère du DTB source QUE par ces 2 propriétés (contrôle par diff dts).
#   P4. Mac en mode câble (m1n1 proxy), câble USB-C sur le PC ; filet disque + DFU en place.
#
# Se lance SUR LE PC (là où sont m1n1/proxyclient et le câble), pas sur ALARM.
#
# PRÉPARÉ PAR : Claude (session ALARM sep-touchid-b9, Opus 5.5), 2026-11-22. JAMAIS LANCÉ.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/../tools/env.sh"

J2DIR="${J2DIR:-$HOME/alarm-recovery/j2}"
KERNEL="${KERNEL:-$J2DIR/vmlinuz-linux-asahi}"
INITRAMFS="${INITRAMFS:-$J2DIR/initramfs-linux-asahi.img}"
DTB_SRC="${DTB_SRC:-$J2DIR/t6001-j314c.dtb}"
DTB_OUT="${DTB_OUT:-$J2DIR/t6001-j314c-sep.dtb}"
SEP_PATH="/soc/sep@396400000"

for t in dtc fdtget fdtput; do command -v "$t" >/dev/null || die "outil absent : $t (paquet dtc)"; done
for f in "$KERNEL" "$INITRAMFS" "$DTB_SRC"; do [ -f "$f" ] || die "fichier absent : $f (cf. P2 : copier depuis ALARM)"; done

# --- construction du DTB : source + espace libre + 2 propriétés ---------------------------------------------
[ "$(fdtget -t s "$DTB_SRC" "$SEP_PATH" compatible 2>/dev/null)" = "apple,sep" ] || die "nœud $SEP_PATH absent ou pas apple,sep"
fdtget "$DTB_SRC" /smbios compatible >/dev/null 2>&1 && die "le DTB source a un nœud smbios (cf. journal 2026-11-11) : mauvais DTB"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cp "$DTB_SRC" "$tmp/edit.dtb"
fdtput -t s "$tmp/edit.dtb" "$SEP_PATH" status okay
fdtput -t s "$tmp/edit.dtb" /aliases sep "$SEP_PATH"
# Espace libre EN DERNIER (fdtput recompacte) : m1n1 kboot ajoute des nœuds au DTB (cf. journal 2026-11-11).
dtc -q -I dtb -O dtb -p 32768 -o "$DTB_OUT" "$tmp/edit.dtb"
[ "$(( $(stat -c %s "$DTB_OUT") - $(stat -c %s "$DTB_SRC") ))" -ge 32000 ] || die "DTB : espace libre non ajouté"

# --- P3 : exactement 2 lignes changées ---------------------------------------------------------------------
dtc -q -I dtb -O dts -o "$tmp/a.dts" "$DTB_SRC"
dtc -q -I dtb -O dts -o "$tmp/b.dts" "$DTB_OUT"
changes="$(diff "$tmp/a.dts" "$tmp/b.dts" | grep -E '^[<>]' || true)"
echo "Différences DTB (attendu : status disabled→okay + alias sep) :"; echo "$changes"
nplus=$(echo "$changes" | grep -c '^>' || true); nminus=$(echo "$changes" | grep -c '^<' || true)
[ "$nplus" -eq 2 ] && [ "$nminus" -eq 1 ] || die "DTB : changements inattendus (+$nplus/-$nminus), arrêt (fail-closed)"
echo "$changes" | grep -q 'status = "okay"' && echo "$changes" | grep -q 'sep = "/soc/sep@396400000"' \
  || die "DTB : les 2 changements attendus ne sont pas là"
[ "$(fdtget -t s "$DTB_OUT" /aliases sep)" = "$SEP_PATH" ] || die "alias sep absent"

echo
echo "DTB prêt : $DTB_OUT"
echo "⚠️  1er boot de SEPOS par Linux. Lancer seulement avec le GO d'Albert (P1..P4 vérifiées)."
[ "${YES:-}" = 1 ] || { read -r -p "Tethered boot d'ALARM avec le SEP activé ? [oui/N] " ok; [ "$ok" = oui ] || die "annulé."; }

YES=1 KERNEL="$KERNEL" INITRAMFS="$INITRAMFS" DTB="$DTB_OUT" exec "$(dirname "$0")/../tools/tethered_boot.sh" alarm
