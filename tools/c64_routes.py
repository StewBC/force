"""Precomputed C64 routing states; mirrors move.asm terrain and room rules."""
from collections import deque

from c64_layout import LAYOUT
ROUTE_PORTALS_HOME = LAYOUT["routing_homes"]["portals"]
ROUTE_DOORS_HOME = LAYOUT["routing_homes"]["doors"]


def bake_routes(rooms, tiles, paper, width, height, classes, blocked, decks, portals):
    def region(x, y):
        return next((i for i, r in enumerate(rooms)
                     if r.x0 <= x < r.x0 + r.w and r.y0 <= y < r.y0 + r.h), 255)

    def opened(x, y):
        if not (0 <= x < width and 0 <= y < height) or (x, y) in decks:
            return False
        t = tiles[y * width + x]
        return t == 81 or (t != 80 and paper[y * width + x] & 15 != 6
                           and classes[t] not in blocked)

    def seam(a, b):
        ra, rb = rooms[a], rooms[b]
        if ra.x0 + ra.w == rb.x0:
            return (0, ra.x0 + ra.w - 1, rb.x0, max(ra.y0, rb.y0), min(ra.y0 + ra.h, rb.y0 + rb.h))
        if rb.x0 + rb.w == ra.x0:
            return (0, ra.x0, rb.x0 + rb.w - 1, max(ra.y0, rb.y0), min(ra.y0 + ra.h, rb.y0 + rb.h))
        if ra.y0 + ra.h == rb.y0:
            return (1, ra.y0 + ra.h - 1, rb.y0, max(ra.x0, rb.x0), min(ra.x0 + ra.w, rb.x0 + rb.w))
        if rb.y0 + rb.h == ra.y0:
            return (1, ra.y0, rb.y0 + rb.h - 1, max(ra.x0, rb.x0), min(ra.x0 + ra.w, rb.x0 + rb.w))
        return None

    def positions(s):
        if s is None:
            return []
        mode, here, other, lo, hi = s
        return [p for p in range(lo, hi)
                if (opened(p, here) and opened(p, other) if mode
                    else opened(here, p) and opened(other, p))]

    pf, pt = [255] * 24, [255] * 24
    for i, (x, y) in enumerate(portals):
        pf[i] = region(x, y)
        adjacent = [region(x + dx, y + dy) for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0))]
        adjacent = [r for r in adjacent if r != 255 and r != pf[i]]
        if pf[i] != 255 and len(adjacent) == 1:
            pt[i] = adjacent[0]

    linked = [[False] * len(rooms) for _ in rooms]
    doors, pool = [], []
    for a in range(len(rooms)):
        for b in range(a + 1, len(rooms)):
            s = seam(a, b)
            ps = positions(s)
            linked[a][b] = linked[b][a] = bool(ps) or any(
                (f, t) in ((a, b), (b, a)) for f, t in zip(pf, pt))
            if s is not None and 0 <= s[4] - s[3] <= 20 and ps:
                if len(doors) >= 24 or len(pool) + len(ps) > 176:
                    raise ValueError('routing exceeds doorway storage')
                doors.append((a, b, len(ps), len(pool), s, seam(b, a)))
                pool.extend(ps)

    hops = [255] * 256
    for source in range(len(rooms)):
        seen = {source}
        queue = deque([source])
        while queue:
            a = queue.popleft()
            for b in range(len(rooms)):
                if b not in seen and linked[a][b]:
                    seen.add(b)
                    hops[source * 16 + b] = b if a == source else hops[source * 16 + a]
                    queue.append(b)
    door_bytes = bytearray([len(doors), len(pool)])
    for field in range(4):
        door_bytes.extend([d[field] for d in doors] + [0] * (24 - len(doors)))
    door_bytes.extend(pool + [0] * (176 - len(pool)))
    for direction in (4, 5):
        for field in range(5):
            door_bytes.extend([d[direction][field] for d in doors] + [0] * (24 - len(doors)))
    return bytes(pf + pt + hops) + door_bytes


def bridge_variants(rooms, tiles, paper, width, height, classes, blocked, decks, portals):
    """Fixed doorway slots and shared reversible page patches for every state."""
    relevant = []
    masks = [0] * 16
    for i, (x, y) in enumerate(decks):
        r = next((r for r in rooms if r.x0 <= x < r.x0+r.w and r.y0 <= y < r.y0+r.h), None)
        if r is None or x in (r.x0, r.x0+r.w-1) or y in (r.y0, r.y0+r.h-1):
            masks[i] = 1 << len(relevant)
            relevant.append(i)
    if len(relevant) > 8:
        raise ValueError('bridge routing exceeds eight state bits')
    if 16 + (1 << len(relevant)) > 256:
        raise ValueError("bridge routing state index exceeds the 256-byte program")
    images = []
    for state in range(1 << len(relevant)):
        terrain = list(tiles)
        closed = set(decks)
        for bit, i in enumerate(relevant):
            if state & (1 << bit):
                x, y = decks[i]
                terrain[y * width + x] = 81
                closed.remove((x, y))
        images.append(bake_routes(rooms, terrain, paper, width, height, classes, blocked, closed, portals))
    # Reserve each possible doorway and its maximum crossing capacity once.
    walls = {}
    parsed = []
    for image in images:
        entries = {}
        for i in range(image[304]):
            key = (image[306+i], image[330+i])
            n, at = image[354+i], image[378+i]
            positions = image[402+at:402+at+n]
            geom = tuple(image[578+24*f+i] for f in range(10))
            entries[key] = (positions, geom)
            old = walls.get(key, (0, geom))
            walls[key] = (max(old[0], n), geom)
        parsed.append(entries)
    keys = sorted(walls)
    if len(keys) > 24 or sum(walls[k][0] for k in keys) > 176:
        raise ValueError('bridge variants exceed doorway storage')
    normalized = []
    for image, entries in zip(images, parsed):
        out = bytearray(image[:304]) + bytearray(514)
        out[304] = len(keys)
        offset = 0
        for i, key in enumerate(keys):
            cap, geom = walls[key]
            positions = entries.get(key, (b'', geom))[0]
            out[306+i], out[330+i] = key
            out[354+i], out[378+i] = len(positions), offset
            out[402+offset:402+offset+len(positions)] = positions
            for f, value in enumerate(geom):
                out[578+24*f+i] = value
            offset += cap
        out[305] = offset
        normalized.append(bytes(out))
    # Patch addresses are fixed by BSS layout; generator reads them from homes
    # shared with assembly (see ROUTE_* constants in gen_c64 / equ.inc).
    addresses = list(range(ROUTE_PORTALS_HOME, ROUTE_PORTALS_HOME + 304)) + list(range(ROUTE_DOORS_HOME, ROUTE_DOORS_HOME + 514))
    base = normalized[0]
    groups, lists = {}, []
    for image in normalized:
        pages = {}
        for address, old, new in zip(addresses, base, image):
            if old != new:
                pages.setdefault(address >> 8, bytearray()).extend((address & 255, old, new))
        group_list = []
        for page, triples in sorted(pages.items()):
            group = bytes((page, len(triples)//3)) + triples
            groups.setdefault(group, None)
            group_list.append(group)
        lists.append(tuple(group_list))
    unique_lists = dict.fromkeys(lists)
    program = bytearray(masks) + bytearray(len(images))
    for group in groups:
        if len(program) + len(group) > 256:
            raise ValueError("bridge routing patches exceed the 256-byte program")
        groups[group] = len(program)
        program += group
    list_offsets = {}
    for group_list in unique_lists:
        if len(program) + 1 + len(group_list) > 256:
            raise ValueError("bridge routing patches exceed the 256-byte program")
        list_offsets[group_list] = len(program)
        program += bytes((len(group_list),)) + bytes(groups[g] for g in group_list)
    for state, group_list in enumerate(lists):
        program[16+state] = list_offsets[group_list]
    if len(program) > 256:
        raise ValueError(f'bridge routing patches need {len(program)} bytes; cap is 256')
    return normalized[0], bytes(program).ljust(256, b'\0'), normalized, len(program)
