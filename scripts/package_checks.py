"""Release payload gates, including files missed by extension-only dylib scans."""
import pathlib
import struct


def macho_types(data):
    if len(data) < 4:
        return []
    magic = data[:4]
    if magic in (b'\xfe\xed\xfa\xce', b'\xfe\xed\xfa\xcf',
                 b'\xce\xfa\xed\xfe', b'\xcf\xfa\xed\xfe'):
        endian = '>' if magic[:2] == b'\xfe\xed' else '<'
        return [struct.unpack_from(endian + 'I', data, 12)[0]]
    if magic in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf',
                 b'\xbe\xba\xfe\xca', b'\xbf\xba\xfe\xca'):
        endian = '>' if magic[:2] == b'\xca\xfe' else '<'
        wide = magic in (b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca')
        count = struct.unpack_from(endian + 'I', data, 4)[0]
        types = []
        for i in range(count):
            offset = 8 + i * (32 if wide else 20)
            start, size = struct.unpack_from(endian + ('QQ' if wide else 'II'), data, offset + 8)
            if start + size > len(data):
                raise ValueError('Truncated fat Mach-O')
            part = macho_types(data[start:start + size])
            if not part:
                raise ValueError('Invalid fat Mach-O slice')
            types.extend(part)
        return types
    return []


def check_payload_file(name, data):
    if any(part.lower().endswith('.dsym') for part in pathlib.PurePosixPath(name).parts):
        raise ValueError('Debug symbols must be outside Payload: ' + name)
    types = macho_types(data)
    # ldid supports executables, dylibs and bundles; MH_DSYM (10) is not signable.
    if any(kind not in (2, 6, 8) for kind in types):
        raise ValueError('Unsupported Mach-O type {}: {}'.format(types, name))
    return types


def check_payload_directory(payload):
    for path in sorted(payload.rglob('*')):
        if path.is_file():
            check_payload_file(path.relative_to(payload).as_posix(), path.read_bytes())
