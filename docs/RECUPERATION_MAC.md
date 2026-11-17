# ✅ RÉCUPÉRATION DU MAC — TERMINÉE (2026-11-17)

> **RÉSOLU.** Le Mac est récupéré : **DFU Restore (16/11)** → macOS 27.2.1 neuf + SEP propre, puis
> **réinstall ALARM par image bloc** (`dd` de `alarm_p5.img`) + **GRUB refabriqué** → **ALARM boote
> nativement** (m1n1→U-Boot→GRUB→LUKS→ALARM, confirmé par Albert). macOS et Linux marchent tous les deux.
> Perdu et non réinstallés : **macOS 13.5** et le **Fedora de test (10.0.200.4)**.
> Détail : [[mac-boot-casse-recuperation]] et docs/handoff.md (bandeau 2026-11-17).
> Le texte ci-dessous est l'**historique** de la procédure (gardé pour référence) — plus rien à faire ici.

---

## Historique (procédure d'origine, résolue)

> État au moment de la rédaction : le Mac n'était plus utilisable normalement ; on ne relançait aucun
> essai SEP (voie C) tant qu'il n'était pas récupéré.

## Ce qui s'est passé (2026-11-11)
Pendant les essais « voie C » (rejeu de lockers xART au SEP, lancés par Albert), l'état
scellé de la puce (SEP) a été bousculé. Depuis :
- **macOS boucle** (bootloop) et ne démarre plus.
- **Le menu de démarrage (Startup Options) ET la récupération 1TR ne se chargent plus** :
  maintien de power, double-appui maintenu, maintien 15 s → tout **bootloop** et retombe sur m1n1.
- **Seul m1n1 (boot permissif) démarre** → écran noir « Running proxy… » (le mode proxy backdoor
  est donc **DÉJÀ actif**).
- Un **DFU Revive** a été fait (firmware rafraîchi) → **n'a PAS réparé** le menu (Revive ne remet
  pas à zéro l'état scellé du SEP). Message final attendu : « Gave up waiting … RestoreOS → BootedOS »
  = normal car le Mac boote m1n1 et pas un macOS ; le firmware a bien été réinstallé.

## État des données
- **Asahi ALARM (Linux quotidien) + données = intactes** : aucune écriture disque n'a jamais été
  faite par le projet, et Revive n'efface rien.
- Backup de la partition Linux disponible.
- Le Mac **n'est pas brické** (m1n1 démarre).
- m1n1 a été mis en défaut volontairement (pour faciliter les reboots du projet) : c'est pour ça
  que ça boote m1n1. Le Linux est juste « plus sélectionnable » car le menu est cassé.

## Partitions du Mac (d'après Albert)
1. macOS (principal)  2. macOS 13.5 + m1n1 (projet)  3. **Asahi ALARM (Linux quotidien = la cible)**
4. Asahi test (projet, jetable, = root@10.0.200.4)

## OBJECTIF
Récupérer l'accès à **Asahi ALARM sans rien effacer**, puis re-régler le démarrage par défaut dessus.

---

## ✅ SOLUTION 1 — TETHERED BOOT (recommandée, NON destructive, SANS 2e Mac)
Booter un noyau Linux depuis le **PC Linux** via le proxy m1n1, par câble USB-C. Ne touche pas au
disque (le noyau est envoyé en RAM). **Pas besoin d'un Mac.** Doc : https://asahilinux.org/docs/sw/tethered-boot/

### Matériel (Albert)
- Le **MacBook branché DIRECTEMENT sur le PC Linux** en **USB-C data** (quand ils sont côte à côte,
  plus besoin du relais 10.0.200.5 / du Mac d'Erdem). Port Thunderbolt côté Mac.
- Si à distance : le montage relais/tunnel actuel marche aussi (le proxy passe déjà par là).
- Le mode « Running proxy… » est **déjà actif** → **pas besoin de 1TR** (cassé de toute façon).

### À RÉSOUDRE AVANT de lancer (l'agent doit préparer ça avec Albert) :
1. **root= : quelle partition est la racine d'ALARM** → `root=/dev/nvme0n1pX` (trouver X ; Albert le
   sait peut-être, sinon l'identifier). ⚠️ un mauvais `root=` peut corrompre une AUTRE partition.
2. **Noyau + DTB + initramfs** compatibles **M1 Max 14"** :
   - **DTB = `apple/t6001-j314c.dtb`** (PAS `t6000-j314s` = M1 Pro). Mauvais DTB → plantage.
   - Le noyau n'a PAS besoin de venir d'ALARM : n'importe quel **noyau linux-asahi ARM64 pour
     t6001-j314c** convient, avec `root=` pointant sur ALARM. Il faut un noyau avec NVMe + pilotes
     intégrés, ou un **initramfs** contenant les modules + `/lib/firmware/{brcm,apple}`.
   - Pistes pour les obtenir : (a) paquet `linux-asahi` Arch (config :
     https://github.com/AsahiLinux/PKGBUILDs/blob/main/linux-asahi/config) ; (b) sources linux-asahi
     déjà présentes pour le Linux de test du projet ; (c) extraire depuis la partition ALARM si on
     arrive à la monter autrement. Le DTB `t6001-j314c.dtb` se construit avec le noyau.

### Commandes (schéma — adapter les chemins et X)
```bash
# Lien direct USB : M1N1DEVICE = le vrai /dev/serial/by-id (pas /tmp/m1n1 du tunnel).
# Vérifier le lien proxy :
python3 m1n1/proxyclient/tools/shell.py        # ^D pour sortir
# Booter le noyau (ordre : noyau, DTB, initramfs en dernier) :
python3 m1n1/proxyclient/tools/linux.py \
  -b 'earlycon rootwait root=/dev/nvme0n1pX' \
  /chemin/Image.gz /chemin/apple-t6001-j314c.dtb /chemin/initramfs.img
```
Succès = logos « pingouins » au framebuffer, puis le boot Linux d'ALARM à l'écran du Mac.

### Risques
- Le noyau **monte la racine en écriture** → un mauvais `root=` ou un mauvais DTB peut **corrompre**
  des fichiers. Donc : **backup confirmé** avant, et bien vérifier X + le DTB. Les commandes
  elles-mêmes n'écrivent pas sur le disque (noyau envoyé en RAM par USB).

### Une fois DANS ALARM
- Re-définir le **démarrage par défaut sur ALARM** pour que le Mac reboote normalement ensuite.
  - Piste : `asahi-bless` (à confirmer) ou la procédure « bless » Asahi. **NON couvert** par la doc
    tethered-boot → l'agent vérifie d'abord, ne devine pas.
  - ⚠️ Ligne rouge projet : l'agent ne touche PAS à `nvram` / boot policy ; **c'est Albert qui fait**,
    à la main, une commande prête à coller.

---

## 🟠 SOLUTION 2 — DFU RESTORE DEPUIS LE PC LINUX (DESTRUCTIF, SANS 2e MAC) — PRÊT À LANCER

> Corrige l'ancienne version de cette section : **pas besoin d'un 2e Mac.** La restauration DFU
> d'un Mac Apple Silicon se fait depuis ce PC Linux avec **`idevicerestore`** (libimobiledevice ;
> confirmé par marcan sur M1 ; wrapper `SimpleMacRestore`). Préparé le 2026-11-16.

**Ce que ça fait :** remet la puce (SEP) + le firmware à zéro → répare le bootloop. **EFFACE TOUT
le disque** (macOS, macOS 13.5 du projet, ALARM, Linux de test). Restaure le **macOS le plus récent
(27.2.1)** — le 13.5 n'est plus signé par Apple, on ne peut pas y revenir.

### ⛔ 3 VERROUS avant de cliquer (le script ne peut pas les vérifier à ta place)
1. **Sauvegarde d'ALARM faite ET vérifiée.** La sauvegarde restic est derrière le pool **ZFS `latif`**,
   or le module ZFS n'est pas construit pour le noyau courant du PC → **illisible pour l'instant**.
   → Faire une **sauvegarde fraîche** d'ALARM (sur le disque du PC, `/` a ~430 Go libres) AVANT.
   (`~/backup_mac_FULL` = vieux système ext4, **pas** ALARM actuel — ne pas s'y fier.)
2. **Identifiant Apple + mot de passe** du Mac connus (sinon **Verrou d'activation** bloque la
   reconfiguration après l'effacement).
3. Accepter que les 4 partitions soient effacées.

### Préparation (déjà faite par l'agent le 2026-11-16)
- Firmware : `~/mac-dfu/UniversalMac_27.2.1_26B131_Restore.ipsw` (25 595 954 706 o,
  sha256 `233e85a0…b300814f`). Téléchargé depuis le CDN Apple. **Unique pour tous les Mac Apple Silicon.**
- Bouton : `pending/dfu_restore.sh` (vérifie firmware+sha256, outil, usbmuxd, Mac en DFU ; refuse de
  partir sinon ; confirmation tapée obligatoire).

### À faire par Albert, dans l'ordre, le jour J
1. **Installer l'outil** (une fois) : `yay -S idevicerestore usbmuxd libirecovery`
   puis `sudo systemctl enable --now usbmuxd`.
2. **Brancher** le Mac au PC en **USB-C ↔ USB-C data** (pas Thunderbolt-only, **pas de hub**),
   Mac sur secteur, rien d'autre sur les ports.
3. **Mettre le Mac en DFU** (écran reste NOIR) :
   - Éteindre : maintenir le bouton power (Touch ID) ~10 s jusqu'à extinction.
   - Appuyer puis relâcher power ; **immédiatement** maintenir ensemble **Contrôle-gauche +
     Option-gauche + Maj-DROITE + power** ~10 s.
   - Relâcher tout **sauf power** ; garder **power** encore jusqu'à ~10 s.
   - L'écran reste noir = DFU. (Vérif PC : `lsusb -d 05ac:` montre un appareil Apple.)
4. **Cliquer le bouton** : `./pending/dfu_restore.sh` → taper `EFFACER-ET-RESTAURER`.
   **NE RIEN DÉBRANCHER, garder sur secteur** jusqu'à la fin (une coupure peut bloquer le Mac).
5. Le Mac reboote sur macOS 27.2.1 neuf → assistant de config (Apple ID requis).

### Après le Restore (pour reprendre Touch ID)
- Créer un compte, **ré-enrôler Touch ID** dans macOS → l'état scellé du SEP est de nouveau valide.
- Puis **réinstaller Asahi/ALARM** (installateur Asahi) et remonter les données depuis la sauvegarde.
- La reprise du projet (driver natif) repart de là, sur un SEP en état connu.

### Si ça échoue / s'interrompt
- Câble/hub = cause n°1 d'échec de détection DFU : câble USB-C data direct, sans hub.
- Coupure pendant le restore → refaire la séquence DFU et relancer le bouton (le Mac n'est pas
  perdu tant qu'on peut rentrer en DFU).
- `idevicerestore` sur portable Apple Silicon depuis Linux : voie non documentée officiellement
  (faite via SimpleMacRestore/marcan) → possible accroc ; ce n'est pas garanti « premier coup ».

---

## Liens utiles
- Tethered boot : https://asahilinux.org/docs/sw/tethered-boot/
- Tethered boot (hôte macOS) : https://asahilinux.org/docs/sw/tethered-boot-macos-host/
- Processus de boot Asahi : https://asahilinux.org/docs/alt/boot-process-guide/
- Guide m1n1 : https://asahilinux.org/docs/sw/m1n1-user-guide/
- Liste des appareils / DTB : https://asahilinux.org/docs/hw/devices/device-list/
- Config noyau linux-asahi : https://github.com/AsahiLinux/PKGBUILDs/blob/main/linux-asahi/config
- Revive/Restore Apple : https://support.apple.com/en-us/108900

## Matériel à prévoir
MacBook, câble USB-C data, MacBook branché direct sur le PC (idéal) ou via le relais/tunnel.
