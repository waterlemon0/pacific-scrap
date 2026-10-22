"""Binary FBX: copy with every Geometry's Vertices scaled. fbx_scale.py in out scale"""
import struct, zlib, sys

def read(b):
    ver = struct.unpack('<I', b[23:27])[0]
    big = ver >= 7500
    hs = 25 if big else 13

    def node(o):
        if big:
            end, np_, pl = struct.unpack('<QQQ', b[o:o + 24])
        else:
            end, np_, pl = struct.unpack('<III', b[o:o + 12])
        nl = b[o + hs - 1]
        if end == 0:
            return None, o + hs
        p = o + hs
        name = b[p:p + nl]; p += nl
        props = []
        for _ in range(np_):
            t = chr(b[p]); start = p; p += 1
            if t == 'Y': p += 2
            elif t == 'C': p += 1
            elif t in 'IF': p += 4
            elif t in 'DL': p += 8
            elif t in 'fdlib':
                n, enc, cl = struct.unpack('<III', b[p:p + 12]); p += 12 + cl
            elif t in 'SR':
                n = struct.unpack('<I', b[p:p + 4])[0]; p += 4 + n
            else:
                raise ValueError(t)
            props.append(b[start:p])
        kids = []
        has_null = False
        while p < end:
            k, p2 = node(p)
            if k is None:
                has_null = True; p = p2; break
            kids.append(k); p = p2
        return [name, props, kids, has_null], end

    o = 27; top = []
    while True:
        n, o2 = node(o)
        if n is None:
            break
        top.append(n); o = o2
    return b[:27], top, b[o2:], big, ver

def scale_array(raw, s):
    t = chr(raw[0])
    n, enc, cl = struct.unpack('<III', raw[1:13])
    data = raw[13:]
    if enc: data = zlib.decompress(data)
    fmt = {'d': 'd', 'f': 'f'}[t]
    vals = [v * s for v in struct.unpack('<%d%s' % (n, fmt), data)]
    data = struct.pack('<%d%s' % (n, fmt), *vals)
    if enc: data = zlib.compress(data)
    return raw[:1] + struct.pack('<III', n, enc, len(data)) + data

def walk(nodes, s, inGeo=False):
    for n in nodes:
        if n[0] == b'Vertices' and inGeo:
            n[1][0] = scale_array(n[1][0], s)
        walk(n[2], s, inGeo or n[0] == b'Geometry')

def write(head, top, tail, big):
    hs = 25 if big else 13
    out = bytearray(head)
    def emit(n):
        start = len(out)
        out.extend(b'\0' * hs)
        out.extend(n[0])
        pl = sum(len(p) for p in n[1])
        for p in n[1]: out.extend(p)
        for k in n[2]: emit(k)
        if n[2] or n[3]: out.extend(b'\0' * hs)
        end = len(out)
        if big:
            out[start:start + 24] = struct.pack('<QQQ', end, len(n[1]), pl)
        else:
            out[start:start + 12] = struct.pack('<III', end, len(n[1]), pl)
        out[start + hs - 1] = len(n[0])
    for n in top: emit(n)
    out.extend(b'\0' * hs)
    out.extend(tail)
    return bytes(out)

src, dst, s = sys.argv[1], sys.argv[2], float(sys.argv[3])
b = open(src, 'rb').read()
head, top, tail, big, ver = read(b)
# (round trip first: unchanged it must come out byte for byte)
assert write(head, top, tail, big) == b, "round trip differs"
walk(top, s)
open(dst, 'wb').write(write(head, top, tail, big))
print("ok", dst)
