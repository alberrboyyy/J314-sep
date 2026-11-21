#!/usr/bin/env python3
"""Pont série -> TCP pour le PC Windows (remplace le relais 10.0.200.5).

Le Mac en mode m1n1 proxy expose un périphérique USB CDC-ACM composite = DEUX ports COM
sous Windows : l'interface if00 (proxy m1n1) et if02 (UART de l'hyperviseur). Ce script sert
chaque port COM sur un port TCP, en passthrough brut, pour que `tunnel.py` (côté Linux) s'y
connecte comme avant au relais et recrée /tmp/m1n1.

PUR TRANSPORT : on parle au port COM et à un socket, on n'envoie RIEN au SEP. Équivalent exact
du vieux relais socat/ser2net, côté Windows.

Prérequis (Windows, admin) :  py -m pip install pyserial
Usage (PowerShell/cmd), les DEUX ports du Mac, sur les ports attendus par tunnel.py :
    py tools\\win_serial_bridge.py COM5:4000 COM6:4001
  (COM5 = if00/proxy -> 4000 ; COM6 = if02/console -> 4001 ; adapte les numéros COM)

Si tu ne sais pas lequel est if00 : lance quand même, puis côté Linux teste le proxy ; s'il ne
répond pas, inverse les deux numéros COM. Ctrl+C pour arrêter.
"""
import socket
import sys
import threading
import time

try:
    import serial  # pyserial
except ImportError:
    sys.exit("pyserial manquant : lance  py -m pip install pyserial")

BAUD = 115200  # nominal : sur USB-CDC le débit est ignoré, mais pyserial exige une valeur


def pump_serial_to_sock(ser, sock, stop):
    while not stop.is_set():
        try:
            data = ser.read(4096)          # timeout court (réglé plus bas) -> réactif
        except Exception:
            break
        if data:
            try:
                sock.sendall(data)
            except Exception:
                break


def serve(com, port):
    ser = serial.Serial(com, BAUD, timeout=0.02, write_timeout=1, rtscts=False, dsrdtr=False)
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", port))
    srv.listen(1)
    print(f"[{com}] -> 0.0.0.0:{port}  (en attente d'un client tunnel)", flush=True)
    while True:
        sock, addr = srv.accept()
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        print(f"[{com}] client {addr[0]}:{addr[1]} connecté", flush=True)
        try:
            ser.reset_input_buffer()       # vide les octets périmés (comme restart_tunnel.sh)
        except Exception:
            pass
        stop = threading.Event()
        t = threading.Thread(target=pump_serial_to_sock, args=(ser, sock, stop), daemon=True)
        t.start()
        try:
            while True:
                data = sock.recv(4096)     # socket -> série
                if not data:
                    break
                ser.write(data)
        except Exception:
            pass
        finally:
            stop.set()
            try:
                sock.close()
            except Exception:
                pass
            print(f"[{com}] client déconnecté (le tunnel se reconnectera tout seul)", flush=True)


def main():
    pairs = []
    for arg in sys.argv[1:]:
        if ":" not in arg:
            sys.exit(f"argument invalide : {arg!r} (attendu COMx:port, ex. COM5:4000)")
        com, port = arg.rsplit(":", 1)
        pairs.append((com, int(port)))
    if not pairs:
        sys.exit(__doc__)
    threads = []
    for com, port in pairs:
        t = threading.Thread(target=serve, args=(com, port), daemon=True)
        t.start()
        threads.append(t)
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        print("\narrêt.")


if __name__ == "__main__":
    main()
