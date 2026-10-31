"""
voice-stalled-reader.py PORT PROTOCOL PROFILE_ID NAME

A machine that has stopped reading its voice socket, for part 1 of
tests/test-1869-voice-negotiation.js (#5090). It joins the room on the voice
service at 127.0.0.1:PORT, with PROTOCOL as its Sec-WebSocket-Protocol, and
says each text message it reads on stdout as one JSON line, until the room's
roster has come. Then it says {"stalled": true} and reads nothing from the
socket until a line comes on stdin. After that it reads again, and says
every message, until the socket closes or stdin ends.

Its receive buffer is set before it connects, which fixes the window it
offers. A node socket left paused could not: its kernel kept taking more as
the receive window grew, so the service saw it drain a second or more after
it stopped, and the harness measured whatever the runner's kernel did then
rather than a socket that had stopped (31 Oct, GitHub's hosted Windows
runner). With the window fixed, this end takes nothing more until it reads
again, so once the service's own send buffer is full too, its socket stays
backed.

Only the standard library. Writes nothing but stdout.
"""
import base64
import json
import os
import socket
import struct
import sys
import threading

RECEIVE_BUFFER = 8192


def say(obj):
    sys.stdout.write(json.dumps(obj) + '\n')
    sys.stdout.flush()


def send_text(sock, obj):
    """A masked text frame, the way a browser sends one."""
    data = json.dumps(obj).encode('utf-8')
    mask = os.urandom(4)
    if len(data) < 126:
        head = struct.pack('!BB', 0x81, 0x80 | len(data))
    else:
        head = struct.pack('!BBH', 0x81, 0x80 | 126, len(data))
    sock.sendall(head + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))


class Frames:
    """The service's frames, which are never masked, read off the socket."""

    def __init__(self, sock, rest):
        self.sock = sock
        self.buf = rest

    def take(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                return None
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def next_text(self):
        """The next text message, parsed, or None once the socket is closed."""
        while True:
            head = self.take(2)
            if head is None:
                return None
            op, length = head[0] & 0x0F, head[1] & 0x7F
            if length == 126:
                more = self.take(2)
                if more is None:
                    return None
                length = struct.unpack('!H', more)[0]
            elif length == 127:
                more = self.take(8)
                if more is None:
                    return None
                length = struct.unpack('!Q', more)[0]
            body = self.take(length)
            if body is None or op == 8:
                return None
            if op != 1:
                continue
            try:
                return json.loads(body.decode('utf-8'))
            except ValueError:
                continue


def main():
    port, protocol, profile_id, name = int(sys.argv[1]), sys.argv[2], int(sys.argv[3]), sys.argv[4]
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, RECEIVE_BUFFER)
    sock.connect(('127.0.0.1', port))
    key = base64.b64encode(os.urandom(16)).decode('ascii')
    sock.sendall(('GET / HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n'
                  'Sec-WebSocket-Key: %s\r\nSec-WebSocket-Protocol: %s\r\nSec-WebSocket-Version: 13\r\n\r\n'
                  % (port, key, protocol)).encode('ascii'))
    head = b''
    while b'\r\n\r\n' not in head:
        chunk = sock.recv(4096)
        if not chunk:
            say({'error': 'the service closed the socket before its handshake answer'})
            return 1
        head += chunk
    at = head.index(b'\r\n\r\n') + 4
    frames = Frames(sock, head[at:])
    send_text(sock, {'t': 'join', 'profileId': profile_id, 'name': name})
    while True:
        m = frames.next_text()
        if m is None:
            say({'error': 'the service closed the socket before the roster came'})
            return 1
        say(m)
        if m.get('t') == 'peers':
            break
    say({'stalled': True})
    if not sys.stdin.readline():
        return 0

    def read_on():
        while True:
            m = frames.next_text()
            if m is None:
                return
            say(m)
    threading.Thread(target=read_on, daemon=True).start()
    sys.stdin.read()
    return 0


if __name__ == '__main__':
    sys.exit(main())
