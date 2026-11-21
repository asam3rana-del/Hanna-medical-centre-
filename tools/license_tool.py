#!/usr/bin/env python3
"""Hanna Installment — license key banane ka tool (sirf Hanna Solutions ke paas; private key KABHI share na karein).

Koi extra library nahi chahiye (pure Python Ed25519, RFC 8032). Phone par Termux ya PC par chalta hai.

  python3 license_tool.py genkey  hanna-license-private.key
        Nayi key jodi. Private key file mein; PUBLIC key screen par — woh lib/license/license_keys.dart mein jati hai.
        (Nayi jodi banane se pehle di hui SAARI keys bekaar ho jati hain.)

  python3 license_tool.py issue --key hanna-license-private.key --device ABCD-EFGH-JKMN-PQRS --type trial --days 15
  python3 license_tool.py issue --key hanna-license-private.key --device ABCD-EFGH-JKMN-PQRS --type annual --until 2027-11-30
        License key banata hai aur licenses.csv mein likhta hai (serial, device, type, expiry, customer).
        --customer "Ali Mobiles Bhikhi"  (sirf record ke liye, key mein nahi jata)
        --serial 1234                    (na do to licenses.csv ke aakhri serial + 1)

  python3 license_tool.py check --pub <public-key-hex> --key-text HI1-....
        Key ko app ki tarah check karta hai (type, device, expiry).

Key ka format (license_core.dart ke saath bilkul ek jaisa):
  payload 20 byte = [1 version][1 type: 1 trial, 2 annual][10 device code][2 issued day][2 expiry day][4 serial]
  day = 2024-01-01 se din (big-endian). Phir 64 byte Ed25519 dastakhat. Sab Base32 (RFC 4648, padding nahi),
  "HI1-" + 5-5 harf ke group.
"""
import argparse
import csv
import datetime as _dt
import hashlib
import os
import secrets
import sys

# ---------------------------------------------------------------- Ed25519 (RFC 8032 reference)
_p = 2**255 - 19
_L = 2**252 + 27742317777372353535851937790883648493
_d = -121665 * pow(121666, _p - 2, _p) % _p
_I = pow(2, (_p - 1) // 4, _p)


def _xrecover(y):
    xx = (y * y - 1) * pow(_d * y * y + 1, _p - 2, _p)
    x = pow(xx, (_p + 3) // 8, _p)
    if (x * x - xx) % _p != 0:
        x = (x * _I) % _p
    if x % 2 != 0:
        x = _p - x
    return x


_By = 4 * pow(5, _p - 2, _p) % _p
_B = (_xrecover(_By), _By, 1, _xrecover(_By) * _By % _p)


def _add(P, Q):
    A = (P[1] - P[0]) * (Q[1] - Q[0]) % _p
    B = (P[1] + P[0]) * (Q[1] + Q[0]) % _p
    C = 2 * P[3] * Q[3] * _d % _p
    D = 2 * P[2] * Q[2] % _p
    E, F, G, H = B - A, D - C, D + C, B + A
    return (E * F % _p, G * H % _p, F * G % _p, E * H % _p)


def _mul(s, P):
    Q = (0, 1, 1, 0)
    while s > 0:
        if s & 1:
            Q = _add(Q, P)
        P = _add(P, P)
        s >>= 1
    return Q


def _encode(P):
    zinv = pow(P[2], _p - 2, _p)
    x, y = P[0] * zinv % _p, P[1] * zinv % _p
    return int.to_bytes(y | ((x & 1) << 255), 32, 'little')


def _decode(b):
    y = int.from_bytes(b, 'little')
    sign = y >> 255
    y &= (1 << 255) - 1
    x = _xrecover(y)
    if (x & 1) != sign:
        x = _p - x
    P = (x, y, 1, x * y % _p)
    # curve check
    if (-x * x + y * y - 1 - _d * x * x * y * y) % _p != 0:
        raise ValueError('point not on curve')
    return P


def _h(m):
    return hashlib.sha512(m).digest()


def _secret_expand(seed):
    h = _h(seed)
    a = int.from_bytes(h[:32], 'little')
    a &= (1 << 254) - 8
    a |= 1 << 254
    return a, h[32:]


def public_key(seed):
    a, _ = _secret_expand(seed)
    return _encode(_mul(a, _B))


def sign(seed, msg):
    a, prefix = _secret_expand(seed)
    A = _encode(_mul(a, _B))
    r = int.from_bytes(_h(prefix + msg), 'little') % _L
    R = _encode(_mul(r, _B))
    k = int.from_bytes(_h(R + A + msg), 'little') % _L
    s = (r + k * a) % _L
    return R + int.to_bytes(s, 32, 'little')


def verify(pub, msg, sig):
    if len(sig) != 64:
        return False
    try:
        A = _decode(pub)
        R = _decode(sig[:32])
    except ValueError:
        return False
    s = int.from_bytes(sig[32:], 'little')
    if s >= _L:
        return False
    k = int.from_bytes(_h(sig[:32] + pub + msg), 'little') % _L
    sB = _mul(s, _B)
    hA = _add(R, _mul(k, A))
    return _encode(sB) == _encode(hA)


# ---------------------------------------------------------------- license format
_B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'
EPOCH = _dt.date(2024, 1, 1)
TYPES = {'trial': 1, 'annual': 2}
TYPE_NAMES = {v: k for k, v in TYPES.items()}


def b32enc(data):
    bits, val, out = 0, 0, []
    for byte in data:
        val = (val << 8) | byte
        bits += 8
        while bits >= 5:
            out.append(_B32[(val >> (bits - 5)) & 31])
            bits -= 5
    if bits:
        out.append(_B32[(val << (5 - bits)) & 31])
    return ''.join(out)


def b32dec(text):
    bits, val, out = 0, 0, bytearray()
    for ch in text:
        v = _B32.index(ch)
        val = (val << 5) | v
        bits += 5
        if bits >= 8:
            out.append((val >> (bits - 8)) & 0xFF)
            bits -= 8
    return bytes(out)


def norm(text):
    t = ''.join(c for c in text.upper() if c.isalnum())
    # aam ghaltiyan: 0->O, 1->I, 8->B (Base32 mein 0/1/8 nahi hote)
    return t.replace('0', 'O').replace('1', 'I').replace('8', 'B')


def device_bytes(code):
    t = norm(code)
    if len(t) != 16:
        raise SystemExit('Device code 16 harf ka hota hai (ABCD-EFGH-JKMN-PQRS)')
    return b32dec(t)


def day_of(date):
    return (date - EPOCH).days


def make_key(seed, device, ltype, issued, expiry, serial):
    if not (0 <= day_of(issued) < 65536 and 0 <= day_of(expiry) < 65536):
        raise SystemExit('tareekh had se bahar')
    payload = bytes([1, TYPES[ltype]]) + device_bytes(device) + day_of(issued).to_bytes(2, 'big') \
        + day_of(expiry).to_bytes(2, 'big') + int(serial).to_bytes(4, 'big')
    assert len(payload) == 20
    body = b32enc(payload + sign(seed, payload))
    return 'HI1-' + '-'.join(body[i:i + 5] for i in range(0, len(body), 5))


def parse_key(text):
    t = norm(text)
    if not t.startswith('HII'):  # "HI1" -> norm() -> "HII"
        raise ValueError('prefix HI1 nahi')
    raw = b32dec(t[3:])
    if len(raw) != 84:
        raise ValueError('lambai ghalat')
    return raw[:20], raw[20:]


def load_seed(path):
    data = open(path).read().strip()
    seed = bytes.fromhex(data.split()[-1])
    if len(seed) != 32:
        raise SystemExit('private key file kharab hai')
    return seed


def main():
    ap = argparse.ArgumentParser(description='Hanna Installment license tool')
    sub = ap.add_subparsers(dest='cmd', required=True)
    g = sub.add_parser('genkey')
    g.add_argument('out')
    i = sub.add_parser('issue')
    i.add_argument('--key', required=True)
    i.add_argument('--device', required=True)
    i.add_argument('--type', choices=list(TYPES), required=True)
    i.add_argument('--days', type=int, help='trial: kitne din (issue din samet)')
    i.add_argument('--until', help='annual: aakhri din YYYY-MM-DD (us din tak chalegi)')
    i.add_argument('--serial', type=int)
    i.add_argument('--customer', default='')
    i.add_argument('--log', default='licenses.csv')
    c = sub.add_parser('check')
    c.add_argument('--pub', required=True)
    c.add_argument('--key-text', required=True)
    a = ap.parse_args()

    if a.cmd == 'genkey':
        if os.path.exists(a.out):
            raise SystemExit(f'{a.out} pehle se hai — purani key mat mitao (us se di hui keys bekaar ho jayengi)')
        seed = secrets.token_bytes(32)
        with open(a.out, 'w') as f:
            f.write('# Hanna Installment license PRIVATE key — kisi ko na dein, backup rakhein\n' + seed.hex() + '\n')
        try:
            os.chmod(a.out, 0o600)
        except OSError:
            pass
        print('Private key:', a.out)
        print('PUBLIC key (license_keys.dart mein):', public_key(seed).hex())
        return

    if a.cmd == 'issue':
        seed = load_seed(a.key)
        today = _dt.date.today()
        if a.type == 'trial':
            if not a.days or not (1 <= a.days <= 60):
                raise SystemExit('trial ke liye --days 1..60')
            expiry = today + _dt.timedelta(days=a.days - 1)
        else:
            if not a.until:
                raise SystemExit('annual ke liye --until YYYY-MM-DD')
            expiry = _dt.date.fromisoformat(a.until)
            if expiry < today:
                raise SystemExit('--until guzar chuki tareekh hai')
        serial = a.serial
        if serial is None:
            serial = 1
            if os.path.exists(a.log):
                with open(a.log) as f:
                    rows = list(csv.DictReader(f))
                if rows:
                    serial = max(int(r['serial']) for r in rows) + 1
        key = make_key(seed, a.device, a.type, today, expiry, serial)
        new = not os.path.exists(a.log)
        with open(a.log, 'a', newline='') as f:
            w = csv.writer(f)
            if new:
                w.writerow(['serial', 'issued', 'type', 'expiry', 'device', 'customer', 'key'])
            w.writerow([serial, today.isoformat(), a.type, expiry.isoformat(), norm(a.device), a.customer, key])
        print(f'Serial {serial} | {a.type} | {today} -> {expiry} | device {norm(a.device)}')
        print(key)
        return

    if a.cmd == 'check':
        payload, sig = parse_key(a.key_text)
        ok = verify(bytes.fromhex(a.pub), payload, sig)
        dev = b32enc(payload[2:12])
        iss = EPOCH + _dt.timedelta(days=int.from_bytes(payload[12:14], 'big'))
        exp = EPOCH + _dt.timedelta(days=int.from_bytes(payload[14:16], 'big'))
        print('signature', 'OK' if ok else 'GHALAT')
        print('type', TYPE_NAMES.get(payload[1], '?'), '| device', '-'.join(dev[i:i + 4] for i in range(0, 16, 4)),
              '| issued', iss, '| expiry', exp, '| serial', int.from_bytes(payload[16:20], 'big'))
        sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
