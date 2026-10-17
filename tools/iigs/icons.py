"""Build a native IIgs Finder icon file from editable four-bit pixel grids.

Apple File Type Note $CA: 26-byte file header, IconData records, zero terminator.
Each normal/small QuickDraw Icon has type,size,height,width then pixels and mask.
"""
from pathlib import Path
import struct
from probe import png

PALETTE=(0x000,0xD03,0x009,0xD2D,0x072,0x555,0x22F,0x6AF,
         0x850,0xF60,0xAAA,0xF98,0x1D0,0xFF0,0x4F9,0xFFF)


def grid(path):
    rows=[line.strip() for line in path.read_text().splitlines() if line.strip() and not line.startswith('#')]
    if not rows or len({len(row) for row in rows})!=1:
        raise ValueError(f'{path}: nonrectangular icon')
    if any(c not in '.0123456789ABCDEF' for row in rows for c in row):
        raise ValueError(f'{path}: invalid pixel')
    return rows


def pstring(value,size):
    raw=value.encode('ascii')
    if len(raw)>=size:raise ValueError('Icon name is too long')
    return bytes([len(raw)])+raw+bytes(size-len(raw)-1)


def icon(rows):
    # Finder 640-mode pixels are narrow: duplicate each authored pixel in X.
    width=len(rows[0])*2;height=len(rows);data=bytearray();mask=bytearray()
    for row in rows:
        for c in row:
            data.append(0 if c=='.' else int(c,16)*17)
            mask.append(0 if c=='.' else 255)
    return struct.pack('<4H',0x8000,len(data),height,width)+data+mask


def preview(rows,path):
    scale=8;rgb=bytearray()
    for y,row in enumerate(rows):
        line=bytearray()
        for x,c in enumerate(row):
            if c=='.':color=(238,238,238) if (x//3+y//3)%2 else (255,255,255)
            else:
                value=PALETTE[int(c,16)]
                color=tuple(((value>>shift)&15)*17 for shift in (8,4,0))
            line.extend(bytes(color)*scale)
        rgb.extend(line*scale)
    png(path,bytes(rgb),len(rows[0])*scale,len(rows)*scale)


def generate(root,out):
    source=root/'assets/iigs/icons';out.mkdir(parents=True,exist_ok=True)
    normal=grid(source/'grenade.txt');small=grid(source/'grenade-small.txt')
    big=icon(normal);little=icon(small)
    length=86+len(big)+len(little)
    header=struct.pack('<IHI',0,1,0)+pstring('FORCE.ICON',16)
    record=struct.pack('<H',length)+bytes(64)+pstring('FORCE',16)+struct.pack('<HH',0xB3,0xDB03)+big+little
    path=out/'FORCE.ICON';path.write_bytes(header+record+bytes(2))
    (out/'_FileInformation.txt').write_text('FORCE.ICON=Type(CA),AuxType(0000),VersionCreate(00),MinVersion(80),Access(E3),FolderInfo1(000000000000000000000000000000000000),FolderInfo2(000000000000000000000000000000000000)\n')
    preview(normal,out/'grenade-preview.png');preview(small,out/'grenade-small-preview.png')
    return path

if __name__=='__main__':
    root=Path(__file__).resolve().parents[2]
    print(generate(root,root/'build/iigs/icons'))
