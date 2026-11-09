# driver/linux : sonde du capteur Touch ID (hors ligne, rien n'a tourne)

Ces fichiers n'ont jamais ete compiles ni lances. Ils servent de depart pour un 2e Linux sur la partition d'Albert.

- `t6001-j314c-mesa.dtsi` : decrit le capteur sous le bus `spi2`, avec ce qui a ete LU dans l'ADT
  (8 MHz, interruption gpio0 195, alimentation gpio0 0xc4, delais 7 et 10). Les lignes "A VERIFIER" sont des suppositions.
- `mesa_probe.c` : petit module. Il allume le capteur par GPIO, lit 16 octets sur le bus SPI, les affiche, puis coupe.
  Il n'envoie RIEN au SEP et n'ecrit rien sur le bus. Il ne fait rien tant qu'on ne charge pas `enable=1`.

## Ce qui se teste sur le 2e Linux
1. Le noyau compile avec le .dtsi (le bus spi2 existe-t-il vraiment a cette adresse ?).
2. `modprobe mesa_probe enable=1` : le GPIO s'allume-t-il, la lecture SPI repond-elle ?
3. Les 16 octets commencent-ils par `80 20 00 10 00 00 00` (vu sous macOS, 16 sur 16) ?
4. L'interruption 195 arrive-t-elle, et avec quel type (front/niveau) ?
5. Faut-il une phase d'horloge (spi-cpha) pour avoir une reponse coherente ?

## Ce qui reste inconnu
- Horloge, type d'interruption. (Adresse de spi2 et alimentation ps_spi2 : lues. Broches 48/49/50 : hypothese.)
- Chip-select, phase, sens actif de l'alimentation (flags 0x101), unite des delais.
- Le reset du capteur : il semble passer par l'AOP, rien de public sous Linux. Sans lui, l'alimentation seule peut ne pas suffire.
- Faut-il envoyer une demande avant le statut ? Le module lit sans rien envoyer.
- Une image de 0x7200 octets sans DMA : non essaye.
- Tout le reste du protocole (SEP, SKS, xART) : hors de ce dossier, aucune ecriture.
