"""Platform-neutral executed-state snapshots for C64 / IIgs parity fixtures.

Call only at a stopped, matched logical boundary with the same initial state,
inputs and RNG. Addresses, pointers and renderer scratch are deliberately absent.
"""
UNIT_FIELDS = ('unit_x', 'unit_y', 'unit_section', 'unit_count', 'unit_kind',
               'unit_glyph', 'unit_region', 'unit_cover', 'unit_over_verb',
               'unit_over_x', 'unit_over_y', 'unit_move_wait', 'unit_hp',
               'unit_fire_wait', 'unit_fx', 'weapon_ammo')
SECTION_FIELDS = ('section_lead', 'section_last_x', 'section_last_y',
                  'section_strength', 'section_flags', 'section_order_verb',
                  'section_order_x', 'section_order_y', 'section_order_force',
                  'section_order_str')
SCALARS = ('map_w', 'map_h', 'play_x', 'play_y', 'play_w', 'play_h',
           'win_x', 'win_y', 'win_w', 'win_h', 'room_count', 'script_pc',
           'script_waiting', 'script_wait_pred0', 'script_wait_pred1',
           'script_wait_beat', 'spawn_room', 'spawn_job_rem', 'spawn_job_letter',
           'spawn_job_room', 'spawn_job_batch', 'spawn_job_period',
           'spawn_job_wait', 'spawn_job_type', 'script_fired', 'script_outcome')


def snapshot(read_symbol):
    """read_symbol(name, count) must return bytes from executed guest memory."""
    counts = read_symbol('unit_count', 32)
    columns = {name: read_symbol(name, 32) for name in UNIT_FIELDS}
    result = {'units': [dict(slot=i, **{name: values[i] for name, values in columns.items()})
                        for i in range(32) if counts[i]],
              'sections': {name: list(read_symbol(name, 16)) for name in SECTION_FIELDS},
              'state': {name: read_symbol(name, 1)[0] for name in SCALARS},
              'script_clock': int.from_bytes(read_symbol('script_clock', 2), 'little')}
    for name, size in (('cover_claim', 20), ('grenade_rem', 2), ('grenade_wait', 2),
                       ('nade_fx_x', 2), ('nade_fx_y', 2), ('nade_fx_ttl', 2),
                       ('room_approach', 16), ('room_flags', 16), ('room_heat', 16),
                       ('form_n', 16), ('form_cell', 144), ('portal_from', 24),
                       ('portal_to', 24), ('next_hop', 256), ('door_n', 514)):
        result[name] = list(read_symbol(name, size))
    return result


def differences(expected, actual, path=''):
    """Return only semantic differences; never silently normalize a mismatch."""
    if type(expected) is not type(actual):
        return [dict(path=path, expected=expected, actual=actual)]
    if isinstance(expected, dict):
        found = []
        for key in sorted(set(expected) | set(actual)):
            child = path + '.' + str(key) if path else str(key)
            if key not in expected or key not in actual:
                found.append(dict(path=child, expected=expected.get(key), actual=actual.get(key)))
            else:
                found.extend(differences(expected[key], actual[key], child))
        return found
    if isinstance(expected, list):
        found = []
        if len(expected) != len(actual):
            found.append(dict(path=path+'.length', expected=len(expected), actual=len(actual)))
        for i, (a, b) in enumerate(zip(expected, actual)):
            found.extend(differences(a, b, f'{path}[{i}]'))
        return found
    return [] if expected == actual else [dict(path=path, expected=expected, actual=actual)]
