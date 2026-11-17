#!/usr/bin/env python3
"""Add smooth vertex normals (NORMAL attribute) to .glb files that have none.

glTFast (Unity) refuses meshes that use a normal map but carry no normals
("Invalid mainBufferType Position, Tangent"), so the car bodies exported by
unity_prep_cars.py fell back to a placeholder box in Unity.

Usage: python tools/glb_add_normals.py unity_cars/*.glb
Only the standard library is needed. Files that already have normals are left alone.
"""
import json
import math
import struct
import sys
from array import array

COMP = {5120: 'b', 5121: 'B', 5122: 'h', 5123: 'H', 5125: 'I', 5126: 'f'}
NCOMP = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


def read_glb(path):
    d = open(path, 'rb').read()
    magic, ver, total = struct.unpack('<III', d[:12])
    assert magic == 0x46546C67, 'not a glb'
    jlen, jtype = struct.unpack('<II', d[12:20])
    j = json.loads(d[20:20 + jlen])
    o = 20 + jlen
    blen, btype = struct.unpack('<II', d[o:o + 8])
    return j, bytearray(d[o + 8:o + 8 + blen])


def write_glb(path, j, binbuf):
    js = json.dumps(j, separators=(',', ':')).encode()
    js += b' ' * ((4 - len(js) % 4) % 4)
    binbuf += b'\0' * ((4 - len(binbuf) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(binbuf)
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, total))
        f.write(struct.pack('<II', len(js), 0x4E4F534A) + js)
        f.write(struct.pack('<II', len(binbuf), 0x004E4942) + bytes(binbuf))


def read_accessor(j, binbuf, idx):
    a = j['accessors'][idx]
    bv = j['bufferViews'][a['bufferView']]
    fmt = COMP[a['componentType']]
    n = NCOMP[a['type']]
    size = struct.calcsize(fmt)
    stride = bv.get('byteStride', size * n)
    start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    cnt = a['count']
    if stride == size * n:
        out = array(fmt)
        out.frombytes(bytes(binbuf[start:start + cnt * n * size]))
        if sys.byteorder != 'little':
            out.byteswap()
        return out, n
    out = array(fmt)
    for i in range(cnt):
        o = start + i * stride
        out.extend(struct.unpack('<' + fmt * n, binbuf[o:o + size * n]))
    return out, n


def add_normals(path):
    j, binbuf = read_glb(path)
    changed = False
    for mesh in j.get('meshes', []):
        for prim in mesh['primitives']:
            attrs = prim['attributes']
            if 'NORMAL' in attrs or 'POSITION' not in attrs or prim.get('mode', 4) != 4:
                continue
            pos, _ = read_accessor(j, binbuf, attrs['POSITION'])
            nv = len(pos) // 3
            if 'indices' in prim:
                idx, _ = read_accessor(j, binbuf, prim['indices'])
            else:
                idx = range(nv)
            nrm = [0.0] * (nv * 3)
            for t in range(0, len(idx) - 2, 3):
                a, b, c = idx[t], idx[t + 1], idx[t + 2]
                ax, ay, az = pos[3 * a], pos[3 * a + 1], pos[3 * a + 2]
                ux, uy, uz = pos[3 * b] - ax, pos[3 * b + 1] - ay, pos[3 * b + 2] - az
                vx, vy, vz = pos[3 * c] - ax, pos[3 * c + 1] - ay, pos[3 * c + 2] - az
                # cross product (area weighted)
                nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
                for v in (a, b, c):
                    nrm[3 * v] += nx
                    nrm[3 * v + 1] += ny
                    nrm[3 * v + 2] += nz
            out = array('f')
            for v in range(nv):
                x, y, z = nrm[3 * v], nrm[3 * v + 1], nrm[3 * v + 2]
                l = math.sqrt(x * x + y * y + z * z)
                if l > 1e-20:
                    out.extend((x / l, y / l, z / l))
                else:
                    out.extend((0.0, 1.0, 0.0))
            if sys.byteorder != 'little':
                out.byteswap()
            binbuf += b'\0' * ((4 - len(binbuf) % 4) % 4)
            off = len(binbuf)
            data = out.tobytes()
            binbuf += data
            j['bufferViews'].append({'buffer': 0, 'byteOffset': off, 'byteLength': len(data), 'target': 34962})
            j['accessors'].append({'bufferView': len(j['bufferViews']) - 1, 'componentType': 5126,
                                   'count': nv, 'type': 'VEC3'})
            attrs['NORMAL'] = len(j['accessors']) - 1
            changed = True
    if changed:
        binbuf += b'\0' * ((4 - len(binbuf) % 4) % 4)
        j['buffers'][0]['byteLength'] = len(binbuf)
        write_glb(path, j, binbuf)
    return changed


if __name__ == '__main__':
    for p in sys.argv[1:]:
        print(('added normals: ' if add_normals(p) else 'unchanged:     ') + p)
