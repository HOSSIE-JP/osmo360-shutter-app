"""Render a geometric app icon without external image dependencies."""
import math
import struct
import zlib
from pathlib import Path

def png(size, maskable=False):
    rows=[]
    for y in range(size):
        row=bytearray([0])
        for x in range(size):
            dx=(x+.5-size/2)/size; dy=(y+.5-size/2)/size
            r=math.hypot(dx,dy); a=math.atan2(dy,dx)
            color=(11,17,25,255)
            if .242<r<.29: color=(101,224,219,255)
            if .1<r<.18: color=(33,70,77,255)
            if r<.096: color=(101,224,219,255)
            # Six shutter marks and north marker.
            if .183<r<.224 and abs(math.sin(a*3))<.2:color=(142,158,175,255)
            if abs(dx)<.017 and -.36<dy<-.315:color=(213,247,165,255)
            row.extend(color)
        rows.append(bytes(row))
    def chunk(tag,data):return struct.pack('!I',len(data))+tag+data+struct.pack('!I',zlib.crc32(tag+data)&0xffffffff)
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!IIBBBBB',size,size,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(rows)))+chunk(b'IEND',b'')

root=Path('web/icons');root.mkdir(parents=True,exist_ok=True)
for name,size in [('Icon-192.png',192),('Icon-512.png',512),('Icon-maskable-512.png',512)]:
    (root/name).write_bytes(png(size))
