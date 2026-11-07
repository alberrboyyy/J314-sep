# Setup du PC hôte (Arch Linux)

## Paquets

```
sudo pacman -S --needed git base-devel python python-pyserial python-construct \
  aarch64-linux-gnu-gcc imagemagick bc rustup dtc
rustup target add aarch64-unknown-none-softfloat
```

- `aarch64-linux-gnu-gcc` : cross-compilateur pour m1n1 et le kernel.
- **Rust est obligatoire** pour tout build m1n1 (le Makefile compile `rust/` dans tous les cas ;
  `CHAINLOADING=1` ajoute seulement une feature). Vu au build du 2026-11-07.
- Dépendances Python du proxyclient : d'après `m1n1/requirements.ini` / `requirements.txt` (commit 70757dc7) :
  `pyserial` (3.5), `construct` (2.10.70), **`asn1` (3.3.0)** (+ `enum-compat`, tiré par asn1).
  - `asn1` est importé en tête de `proxyclient/m1n1/hv/__init__.py` → **sans lui, `run_guest.py` plante au lancement.**
  - `asn1` **n'est pas dans les dépôts officiels Arch** (`pacman -Si python-asn1` : introuvable).
    Options (au choix d'Albert, non testées ici) :
    - AUR, si un paquet `python-asn1` y existe (non vérifié) ;
    - venv qui voit les paquets système :
      `python -m venv --system-site-packages ~/.venvs/m1n1 && ~/.venvs/m1n1/bin/pip install asn1==3.3.0`
      (recommandé ; il faudra alors que `tools/*.sh` utilisent ce python : à décider).
- `imagemagick` : `convert`, utilisé pour les logos au build de m1n1.
- **Extraction du kernelcache** : `pyimg4` (testé le 2026-11-07, version 0.8.9), dans un venv jetable :
  ```
  python -m venv /tmp/img4 && /tmp/img4/bin/pip install pyimg4
  /tmp/img4/bin/pyimg4 img4 extract -i macos/kernelcache -p /tmp/krnl.im4p   # IMG4 -> IM4P
  /tmp/img4/bin/pyimg4 im4p extract -i /tmp/krnl.im4p -o macos/kernel.macho  # IM4P -> Mach-O (LZFSE)
  ```
  `pyimg4 im4p extract` directement sur le kernelcache échoue : le fichier est un IMG4 complet (IM4P + IM4M).
  La doc Asahi (m1n1-hypervisor) utilise img4tool : `img4tool -ep out.im4p kernelcache` puis
  `img4tool -eo kernelcache.macho out.im4p` ; même résultat (Mach-O passé tel quel à `run_guest.py`,
  qui le charge via `hv.load_macho()` ; filesets supportés par `m1n1/macho.py`).

## Accès aux ports série sans root

```
sudo usermod -aG uucp $USER   # sur Arch, /dev/ttyACM* appartient au groupe uucp
```
Puis se reconnecter. (Au 2026-11-07, `albert` n'est **pas** dans `uucp`.)

## Clone

```
cd sep-touchid
git clone --recursive https://github.com/AsahiLinux/m1n1.git m1n1
git -C m1n1 switch -c sep-touchid
./tools/build_m1n1.sh
```

## Vérifier la connexion

Mac démarré sur l'entrée m1n1 dev, câble branché :
```
ls /dev/ttyACM*     # doit montrer ttyACM0 (proxy) et ttyACM1 (UART hyperviseur)
```
