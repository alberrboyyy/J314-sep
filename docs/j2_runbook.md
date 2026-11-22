# J2 : premier boot de SEPOS depuis Linux (sep_native), pas à pas

**Go d'Albert donné le 2026-11-22**, dans la session ALARM (« Oui, go J2 »). Ce go vaut pour ce premier run, pas pour
les suivants ni pour d'autres classes d'écriture SEP.

Principe : un tethered boot d'ALARM avec un DTB qui porte l'alias `sep`. m1n1 réserve alors `sepfw` et pose les
manifestes ; le nœud `apple,sep` reste `disabled`, donc `sep.rs` ne fait rien. Ensuite, sur ALARM, notre module
`sep_native` rejoue la séquence de boot de m1n1. Rien n'est écrit sur le disque du Mac. Un reboot normal efface tout.

Ce qui peut rater : le SEP refuse le firmware et panique jusqu'au prochain reboot, ou le Mac fige (appui long sur le
bouton, puis rallumage normal). Aucun ACK xART n'est envoyé, donc aucun compteur scellé n'avance.

Fichiers prêts sur ALARM dans `~/kbuild/j2/` (hors `/tmp`, survivent au reboot) : `vmlinuz-linux-asahi`,
`t6001-j314c.dtb`, `sep_native.ko`, `sep_native_ovl.ko`, `sep-native.dtbo`. Les modules sont compilés depuis le
commit qui contient ce fichier.

## 1. Sur ALARM, avant de redémarrer (Albert)
```
sudo install -m 600 -o albert /boot/initramfs-linux-asahi.img ~/kbuild/j2/
```
L'initramfs contient la clé LUKS (`/cryptkey.bin`) : il ne passe que par le WireGuard, jamais par le repo, et il est
effacé du PC après J2. Claude envoie ensuite `~/kbuild/j2/` au PC en scp (clés de l'agent ssh).

## 2. Mettre le Mac en mode câble (Albert)
Éteindre le Mac, le rallumer en mode câble (m1n1 proxy), câble USB-C sur le PC. La session Claude d'ALARM s'arrête ici :
c'est la session PC qui prend la suite.

## 3. Sur le PC (session PC)
```
J2DIR=~/alarm-recovery/j2 pending/j2_sep_boot_linux.sh
```
Le script vérifie que le DTB ne diffère que par l'alias `sep` et que le nœud reste `disabled`, puis lance
`tools/tethered_boot.sh alarm`. Ce boot n'envoie rien au SEP.

## 4. Sur ALARM démarré (Albert, sudo)
D'abord en lecture seule :
```
sudo cp ~/kbuild/j2/sep-native.dtbo /lib/firmware/
sudo insmod ~/kbuild/j2/sep_native_ovl.ko
sudo insmod ~/kbuild/j2/sep_native.ko
sudo journalctl -k -b --no-pager | grep -iE 'sep_native|sepfw'
```
Il faut y voir `sepfw` trouvé, les deux manifestes lus et la mailbox prise, sans aucun envoi. Si `sep_native_ovl`
refuse (« sepfw absent »), m1n1 n'a pas réservé la zone : on s'arrête là.

Puis le boot SEPOS (le go ci-dessus) :
```
sudo rmmod sep_native
sudo insmod ~/kbuild/j2/sep_native.ko allow_boot=1
sudo journalctl -k -b --no-pager | grep -iE 'sep_native' | tail -40
```
Résultat attendu : 0x66 (DATA 1), 0x69, 0xD2, 0x66 (DATA 2), 0x6A, « firmware démappé », puis la table des EP annoncés
en 0xFD. Après le premier envoi, `sep_native` ne se décharge plus (EBUSY) : c'est voulu, le SEP utilise la mémoire.

## 5. Après
Le reboot normal du Mac (sans câble) revient au boot stock : pas d'alias `sep`, SEP non démarré par Linux. Supprimer
`/lib/firmware/sep-native.dtbo` et l'initramfs copié sur le PC. Consigner le résultat brut dans `docs/journal.md`.
