#!/usr/bin/env python3
"""Greedy LZSS used by the C64 map-plane chunks.

Flag bytes are LSB first, including a short final group. A set bit is a
literal byte. A clear bit is a match: offset_lo, then
((offset >> 4) & 0xF0) | (length - 3). Offset is 1..4095. Length is 3..18.
Equal lengths keep the smaller offset. Length never exceeds the offset.
"""

from __future__ import annotations

_WINDOW = 4095
_MAX_LEN = 18
_MIN_LEN = 3


def encode(data: bytes) -> bytes:
    """Compress data. The result round-trips through decode(src, len(data))."""
    raw = bytes(data)
    n = len(raw)
    heads: dict[bytes, list[int]] = {}
    for j in range(n - 2):
        heads.setdefault(raw[j : j + 3], []).append(j)

    out = bytearray()
    i = 0
    while i < n:
        flag_at = len(out)
        out.append(0)
        flag = 0
        for bit in range(8):
            if i >= n:
                break
            length, offset = _best(raw, i, heads)
            if length >= _MIN_LEN:
                out.append(offset & 0xFF)
                out.append(((offset >> 4) & 0xF0) | (length - _MIN_LEN))
                i += length
            else:
                out.append(raw[i])
                flag |= 1 << bit
                i += 1
        out[flag_at] = flag
    return bytes(out)


def decode(src: bytes, dest_len: int) -> bytes:
    """Expand src until dest_len bytes are written.

    Raises ValueError if src ends early or a match offset is not yet written.
    A match that would pass dest_len stops on the boundary.
    """
    comp = bytes(src)
    out = bytearray()
    i = 0
    n = len(comp)
    while len(out) < dest_len:
        if i >= n:
            raise ValueError("lzss source ended early")
        flag = comp[i]
        i += 1
        for bit in range(8):
            if len(out) >= dest_len:
                break
            if flag & (1 << bit):
                if i >= n:
                    raise ValueError("lzss source ended early")
                out.append(comp[i])
                i += 1
                continue
            if i + 1 >= n:
                raise ValueError("lzss source ended early")
            lo = comp[i]
            hi = comp[i + 1]
            i += 2
            offset = lo | ((hi & 0xF0) << 4)
            length = (hi & 0x0F) + _MIN_LEN
            if offset < 1 or offset > len(out):
                raise ValueError("lzss bad offset")
            for _ in range(length):
                if len(out) >= dest_len:
                    break
                out.append(out[len(out) - offset])
    return bytes(out)


def _best(data: bytes, i: int, heads: dict[bytes, list[int]]) -> tuple[int, int]:
    """Longest match at i. Ties keep the smaller offset.

    Length is capped at the offset so the copy does not overlap itself.
    """
    n = len(data)
    if i + _MIN_LEN > n:
        return 0, 0
    cands = heads.get(data[i : i + _MIN_LEN])
    if not cands:
        return 0, 0
    window = i - _WINDOW
    if window < 0:
        window = 0
    best_len = 0
    best_off = 0
    # Nearest first, and only a strictly longer match replaces it.
    for j in reversed(cands):
        if j >= i:
            continue
        if j < window:
            break
        offset = i - j
        max_len = _MAX_LEN
        remain = n - i
        if remain < max_len:
            max_len = remain
        if offset < max_len:
            max_len = offset
        # A shorter cap is not a match. Do not keep the 3-byte key length.
        if max_len < _MIN_LEN or max_len <= best_len:
            continue
        length = _MIN_LEN
        while length < max_len and data[j + length] == data[i + length]:
            length += 1
        if length > best_len:
            best_len = length
            best_off = offset
            if best_len == _MAX_LEN:
                break
    if best_len < _MIN_LEN:
        return 0, 0
    return best_len, best_off
