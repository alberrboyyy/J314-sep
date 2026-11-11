# 🔴 RÉCUPÉRATION DU MAC — À FAIRE EN PRIORITÉ (session fraîche)

> Lire ce fichier EN ENTIER avant toute action.
> Le Mac n'est plus utilisable normalement. On NE relance AUCUN essai SEP (voie C) tant
> qu'il n'est pas récupéré.

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

## 🟠 SOLUTION 2 — DFU RESTORE + réinstall (dernier recours, DESTRUCTIF, BESOIN D'UN 2e MAC)
- Nécessite un **deuxième Mac** (Apple Configurator). Entrer en DFU (Mac éteint → power + Maj-droite
  + Option-gauche + Contrôle-gauche ~10 s, puis garder power). Puis clic droit → **Restaurer**
  (cette fois **Restaurer**, qui **EFFACE TOUT** le disque — les 4 partitions).
- Ensuite **réinstaller Asahi ALARM depuis le backup** d'Albert.
- Remet la puce/menu à zéro (règle le problème), mais long et destructif. À ne faire que si la
  solution 1 échoue, et **backup confirmé**.

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
