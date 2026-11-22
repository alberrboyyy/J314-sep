#!/usr/bin/env python3
"""Tunnel serie m1n1 robuste : PTY STABLE + TCP auto-reconnectant.

Remplace le tunnel socat. Difference cle : le PTY (/tmp/m1n1 et /tmp/m1n1-console)
est cree UNE fois et garde le MEME descripteur pour toute la duree du tunnel, meme
quand la connexion TCP au relais tombe (typiquement : re-enumeration USB du Mac
pendant un chainload m1n1). Les octets font une pause pendant la coupure puis
reprennent ; la session proxyclient en cours n'est PAS cassee (son fd reste valide).

Le socat precedent, lui, recreait le PTY a chaque coupure -> le fd du proxyclient
devenait invalide -> UartTimeout / "device disconnected".

Ce script est pur transport (il parle a un socket TCP, pas au materiel) : equivalent
du tunnel socat d'Albert, pas un acces hardware. Rien n'est envoye au SEP ici.

Usage : ./tunnel.py            (relais par defaut 10.0.200.5, ports 4000/4001)
         TUNNEL_RELAY=x.x.x.x ./tunnel.py
"""
import os, pty, select, socket, termios, tty, time, threading, sys

RELAY = os.environ.get("TUNNEL_RELAY", "10.0.200.5")
# Ports surchargeables (ex. appli Android "USB Serial Telnet Server" sur 2323, une seule interface).
# TUNNEL_CONSOLE=0 => on ne connecte QUE le proxy (les scripts natifs n'utilisent pas la console if02).
_PROXY_PORT = int(os.environ.get("TUNNEL_PROXY_PORT", "4000"))
_CONSOLE_PORT = int(os.environ.get("TUNNEL_CONSOLE_PORT", "4001"))
LINKS = {"/tmp/m1n1": _PROXY_PORT}
if os.environ.get("TUNNEL_CONSOLE", "1") == "1":
    LINKS["/tmp/m1n1-console"] = _CONSOLE_PORT


def make_pty(link):
    master, slave = pty.openpty()
    tty.setraw(slave)                 # passthrough brut : ni echo ni traitement de ligne
    name = os.ttyname(slave)
    try:
        if os.path.islink(link) or os.path.exists(link):
            os.unlink(link)
    except FileNotFoundError:
        pass
    os.symlink(name, link)
    os.set_blocking(master, False)
    # On GARDE `slave` ouvert pour toute la vie du thread : ainsi, quand le proxyclient
    # ferme sa propre ouverture du slave en fin de commande, le master ne recoit PAS de
    # raccrochage (HUP) et le PTY reste vivant. C'est ce qui rend le lien stable entre
    # deux commandes.
    return master, slave, name


def _close(sock):
    if sock is not None:
        try:
            sock.close()
        except OSError:
            pass


def bridge(link, port):
    master, slave, name = make_pty(link)   # `slave` reste reference -> ouvert
    print(f"{link} -> {name}  (relais {RELAY}:{port})", flush=True)
    sock = None
    to_sock = b""   # octets lus du PTY, en attente d'envoi au relais
    to_pty = b""    # octets recus du relais, en attente d'ecriture vers le PTY
    while True:
        if sock is None:
            try:
                sock = socket.create_connection((RELAY, port), timeout=5)
                sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                sock.setblocking(False)
                # une coupure a deja casse le protocole proxy en cours : on repart propre
                to_sock = b""
                to_pty = b""
                print(f"[{port}] connecte au relais", flush=True)
            except OSError:
                time.sleep(0.5)
                continue
        rset = [master, sock]
        wset = []
        if to_sock:
            wset.append(sock)
        if to_pty:
            wset.append(master)
        try:
            r, w, _ = select.select(rset, wset, [], 1.0)
        except (OSError, ValueError):
            _close(sock)
            sock = None
            continue
        # --- lectures ---
        if master in r:
            try:
                d = os.read(master, 65536)
            except OSError:
                d = b""               # EIO passager (pas de lecteur slave) : on ignore
            if d:
                to_sock += d
        if sock in r:
            try:
                d = sock.recv(65536)
            except OSError:
                d = b""
            if d == b"":
                _close(sock)
                sock = None
                print(f"[{port}] coupure (relais), reconnexion...", flush=True)
                continue
            to_pty += d
        # --- ecritures avec contre-pression (on garde ce qui n'a pas pu partir) ---
        if sock is not None and sock in w and to_sock:
            try:
                n = sock.send(to_sock)
                to_sock = to_sock[n:]
            except OSError:
                _close(sock)
                sock = None
                print(f"[{port}] coupure (envoi), reconnexion...", flush=True)
                continue
        if master in w and to_pty:
            try:
                n = os.write(master, to_pty)
                to_pty = to_pty[n:]
            except (BlockingIOError, InterruptedError):
                pass                  # tampon PTY plein : on reessaiera au prochain tour
            except OSError:
                to_pty = b""          # pas de lecteur slave : on jette


def main():
    threads = []
    for link, port in LINKS.items():
        t = threading.Thread(target=bridge, args=(link, port), daemon=True)
        t.start()
        threads.append(t)
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
