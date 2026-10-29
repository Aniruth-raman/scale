import json

def a7(cid, payload):
    b = [0xA7, (cid >> 8) & 0xFF, cid & 0xFF, len(payload)] + payload
    s = sum(b[1:]) & 0xFF
    return b + [s, 0x7A]

def a6(payload):
    b = [0xA6, len(payload)] + payload
    s = sum(b[1:]) & 0xFF
    return b + [s, 0x6A]

def hx(b):
    return ' '.join(f'{x:02x}' for x in b)

items = []

def add(name, cid, payload, expected):
    frame = a7(cid, payload)
    items.append({
        'name': name,
        'kind': 'a7',
        'cid': cid,
        'payload_hex': hx(payload),
        'frame_hex': hx(frame),
        'expected': expected,
    })

add('weight_scale_live_70_00_kg', 86, [0x01, 0x00, 0x1B, 0x58, 0x20],
    {'type': 'reading', 'value': 70.0, 'unit': 'kg', 'decimals': 2, 'stable': False})
add('weight_scale_stable_70_00_kg', 86, [0x02, 0x00, 0x1B, 0x58, 0x20],
    {'type': 'reading', 'value': 70.0, 'unit': 'kg', 'decimals': 2, 'stable': True})
add('weight_scale_complete', 86, [0x0A], {'type': 'completion', 'requires_stable': True})
add('weight_scale_jin_140_0', 86, [0x02, 0x00, 0x05, 0x78, 0x11],
    {'type': 'reading', 'value': 140.0, 'unit': 'jin', 'decimals': 1, 'stable': True})
add('weight_scale_st_lb_154_3', 86, [0x02, 0x00, 0x06, 0x07, 0x14],
    {'type': 'reading', 'value': 154.3, 'unit': 'st:lb', 'decimals': 1, 'stable': True})
add('weight_scale_lb_154_3', 86, [0x02, 0x00, 0x06, 0x07, 0x16],
    {'type': 'reading', 'value': 154.3, 'unit': 'lb', 'decimals': 1, 'stable': True})
add('weight_scale_unknown_unit_2', 86, [0x02, 0x00, 0x1B, 0x58, 0x02],
    {'type': 'error'})
add('eight_scale_weight_70_00_kg', 50, [0x01, 0x01, 0x00, 0x1B, 0x58, 0x20],
    {'type': 'reading', 'value': 70.0, 'unit': 'kg', 'decimals': 2, 'stable': False})
add('eight_scale_complete', 50, [0x0F], {'type': 'completion', 'requires_stable': False})
add('eight_scale_bodycomp_1', 50, [0x09, 0x01, 0x00, 0xE1, 0x00, 0xC8, 0x01, 0x90, 0x00, 0x0C, 0x00, 0x0D],
    {'type': 'body', 'metrics': {'bmi': 22.5, 'bodyFatPercent': 20.0, 'musclePercent': 40.0,
                                  'fatMassLeftArmKg': 1.2, 'fatMassRightArmKg': 1.3}})
add('dual_mcu_bodycomp_5', 104, [0x09, 0x05, 0x00, 0x64, 0x01, 0x2C, 0x00, 0x00, 0x00, 0x00,
                                  0x00, 0x78, 0x01, 0x90, 0x02, 0x58],
    {'type': 'body', 'metrics': {'fatMassKg': 10.0, 'waterKg': 30.0, 'proteinMassKg': 12.0,
                                  'muscleMassKg': 40.0, 'weightWithoutKg': 60.0}})

# Synthetic A6 get-version request (documented, not a measurement).
items.append({
    'name': 'a6_get_version_probe',
    'kind': 'a6',
    'payload_hex': '0e',
    'frame_hex': hx(a6([0x0E])),
    'expected': {'type': 'info'},
})

# Corrupt checksum by changing one payload byte after frame construction.
frame = a7(86, [0x02, 0x00, 0x1B, 0x58, 0x20])
frame[-2] = (frame[-2] + 1) & 0xFF
items.append({
    'name': 'corrupt_checksum',
    'kind': 'a7',
    'cid': 86,
    'payload_hex': '02 00 1b 58 02',
    'frame_hex': hx(frame),
    'expected': {'type': 'error'},
})

with open('test/fixtures/synthetic_frames.json', 'w', encoding='utf-8') as f:
    json.dump({'note': 'Synthetic AILink frames. No real measurements or personal data.', 'frames': items}, f, indent=2)
print('wrote', len(items))
