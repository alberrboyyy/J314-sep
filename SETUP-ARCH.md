# Setup du PC hôte (Arch Linux)

## Paquets

```
sudo pacman -S --needed git base-devel python python-pyserial python-construct \
  aarch64-linux-gnu-gcc imagemagick bc
```

- `aarch64-linux-gnu-gcc` : cross-compilateur pour m1n1 et le kernel.
- `python-pyserial`, `python-construct` : dépendances du proxyclient m1n1.
  Vérifie la liste à jour dans le repo m1n1 (README / proxyclient) après le clone : elle peut avoir bougé.
- `imagemagick` : `convert`, utilisé pour les logos au build de m1n1.
- **img4tool** (extraction du kernelcache) : depuis l'AUR, ou `pyimg4` via pip dans un venv.
- Rust n'est nécessaire que pour un build m1n1 avec `CHAINLOADING=1` (pas notre cas).

## Accès aux ports série sans root

```
sudo usermod -aG uucp $USER   # sur Arch, /dev/ttyACM* appartient au groupe uucp
```
Puis se reconnecter.

## Clone

```
cd sep-touchid
git init && git add -A && git commit -m "init"
git clone --recursive https://github.com/AsahiLinux/m1n1.git m1n1
git -C m1n1 switch -c sep-touchid
./tools/build_m1n1.sh
```

## Vérifier la connexion

Mac démarré sur l'entrée m1n1 dev, câble branché :
```
ls /dev/ttyACM*     # doit montrer ttyACM0 (proxy) et ttyACM1 (UART hyperviseur)
```
