# Pourquoi le catch proxy rate (diagnostic, 2026-11-21)

Ce matin le catch marchait (2 fois) ; l'après-midi plus — m1n1 file directement sur Arch, sans fenêtre.
Diagnostic depuis le code m1n1 (`src/main.c`, lecture autorisée). **Hypothèses honnêtes, à confirmer à l'écran.**

## Le mécanisme exact (VU dans m1n1/src/main.c `run_actions`)
```c
#ifdef EARLY_PROXY_TIMEOUT                                  // = 5, compilé si RELEASE && CHAINLOADING
    if (!cur_boot_args.video.display && lp_sip0 == 127) {  // <<< LES DEUX conditions de la fenêtre
        usb_init(); usb_iodev_init();
        printf("Waiting for proxy connection... ");         // <<< SI cette ligne s'affiche, la fenêtre s'ouvre
        for (i = 0; i < 5*100; i++) {                        // 5 secondes
            ... if (iodev_can_write(proxy) || iodev_can_write(vuart)) { uartproxy_run(); return; }  // host a ouvert if00 OU if02 -> RESTE en proxy
            mdelay(10);
        }
        printf(" Timed out\n");
    }
#endif
    // sinon / après timeout :
    payload_run();   // -> U-Boot -> GRUB -> ARCH  (PAS de fenêtre de catch)
```

**La fenêtre de catch (5 s) n'existe QUE si :**
1. `cur_boot_args.video.display == 0` — **aucun affichage actif** au boot (ex. recon du matin : `video: display: 0x0`) ;
2. `lp_sip0 == 127` — **politique de boot permissive** (le « sip0 = 127 » des logs) ;
3. m1n1 compilé RELEASE+CHAINLOADING (l'installé l'est, puisque ça marchait).
Si (1) OU (2) tombe → m1n1 saute la fenêtre → **Arch directement**. C'est le symptôme actuel.

Côté hôte, mon catcher agressif saisit if02 dès son apparition → ça suffit (`iodev_can_write(vuart)`), **à condition que la fenêtre s'ouvre**.

## LE test à faire au retour (1 regard à l'écran du Mac)
Allumer le Mac et **lire le texte blanc m1n1** au démarrage. Deux lignes décident :
- **« Boot policy: sip0 = N »** → N vaut-il **127** ? (si ≠127 → cause = politique de boot)
- **« video: … display: 0x… »** → vaut-il **0x0** ? (si ≠0 → cause = affichage actif)
- Et surtout : **la ligne « Waiting for proxy connection... » s'affiche-t-elle ?**
  - **OUI** → la fenêtre s'ouvre, c'est juste un souci de timing côté hôte → relancer le catcher agressif AVANT d'allumer, ça doit passer (ou allonger EARLY_PROXY_TIMEOUT).
  - **NON** → une des 2 conditions est fausse → voir ci-dessous.

## Arbre de décision (du moins au plus lourd)
1. **Si « display » ≠ 0x0** (affichage actif) : essayer de **booter lid fermé / écran éteint** (clamshell) pour que `display==0` → la fenêtre s'ouvre. **Non destructif, gratuit.**
2. **Si « sip0 » ≠ 127** : la backdoor (politique permissive, posée en 1TR via `csrutil`/`bputil`) a sauté.
   La remettre demande **1TR / recovery macOS** — or 1TR **bootloope**. → donc :
3. **DFU restore** (le filet préparé, déjà fait le 16-17/11) : reconstruit tout, puis réarmer la backdoor et
   réinstaller ALARM (`alarm_p5.img`). Procédure : `docs/RECUPERATION_MAC.md` + mémoire [[mac-boot-casse-recuperation]].
   ⚠️ c'est la solution lourde — à ne faire que si (1) ne marche pas et que sip0≠127 confirmé.

## Ce qui N'A PAS changé la politique
On n'a **jamais** lancé `bputil`/`nvram`/`csrutil` par un script (ligne rouge tenue). Cause probable :
les **coupures d'alim répétées** / tentatives de boot macOS ont fait basculer le disque de démarrage par
défaut (→ « passé sous macOS ») et/ou la LocalPolicy. **Non confirmé** — le regard à l'écran tranchera.
