#!/usr/bin/env python3
"""Bounded PE32+ release checks, not a Windows loader or execution proof.

exports FILE SYMBOL [SYMBOL ...] checks named, non-forwarded exports
(ordinal-valid, RVA-mapped; a section's zero-filled virtual tail counts
as mapped — BSS-backed data exports are legal). At least one SYMBOL is
required: an empty list is usage error, not a vacuous green.
imports FILE prints direct import DLL names; absent tables fail closed.
Exit codes: 0 success, 1 missing symbol, 2 invalid/unsupported input, 64 usage.
"""
import struct
import sys

MAX_FILE = 256 * 1024 * 1024
MAX_ITEMS = 65536


class PE:
    def __init__(self, data):
        self.data = data
        self.sections = []
        if len(data) > MAX_FILE or data[:2] != b"MZ":
            raise ValueError("invalid MZ image or file size")
        pe = self.unpack("<I", 0x3C)[0]
        self.span(pe, 24)
        if data[pe:pe + 4] != b"PE\0\0":
            raise ValueError("invalid PE signature")
        machine, count = self.unpack("<HH", pe + 4)
        size = self.unpack("<H", pe + 20)[0]
        opt = pe + 24
        self.span(opt, size)
        if machine != 0x8664 or not 1 <= count <= 96 or size < 112:
            raise ValueError("expected x64 PE32+ with bounded section table")
        if self.unpack("<H", opt)[0] != 0x20B:
            raise ValueError("expected PE32+")
        dirs = self.unpack("<I", opt + 108)[0]
        if dirs > (size - 112) // 8:
            raise ValueError("data directories exceed optional header")
        self.directories = [self.unpack("<II", opt + 112 + i * 8)
                            for i in range(dirs)]
        self.span(opt + size, count * 40)
        for i in range(count):
            vsize, va, rawsize, rawptr = self.unpack("<IIII", opt + size + i * 40 + 8)
            if rawsize:
                self.span(rawptr, rawsize)
                if rawptr < opt + size + count * 40:
                    raise ValueError("section data overlaps headers")
            vsize = max(vsize, rawsize)
            if va + vsize > 0x100000000:
                raise ValueError("section RVA overflow")
            for other_va, other_ptr, other_raw, other_size in self.sections:
                if vsize and other_size and va < other_va + other_size and other_va < va + vsize:
                    raise ValueError("overlapping section mappings")
                if rawsize and other_raw and rawptr < other_ptr + other_raw and other_ptr < rawptr + rawsize:
                    raise ValueError("overlapping section file ranges")
            # Retain zero-filled sections so metadata pointing into them fails closed.
            self.sections.append((va, rawptr, rawsize, vsize))


    @classmethod
    def read(cls, path):
        with open(path, "rb") as stream:
            return cls(stream.read(MAX_FILE + 1))

    def span(self, offset, size):
        if offset < 0 or size < 0 or offset > len(self.data) - size:
            raise ValueError("truncated file range")
        return offset

    def unpack(self, fmt, offset):
        self.span(offset, struct.calcsize(fmt))
        return struct.unpack_from(fmt, self.data, offset)

    def mapped(self, rva):
        for va, rawptr, rawsize, vsize in self.sections:
            if va <= rva < va + vsize:
                if rva < va + rawsize:
                    return rawptr + rva - va, va + rawsize - rva
                return None, va + vsize - rva  # loader zero-fills the virtual tail
        raise ValueError("RVA is not within any section")

    def offset(self, rva, size):
        offset, available = self.mapped(rva)
        if offset is None or size > available:
            raise ValueError("RVA range exceeds section data")
        return offset

    def string(self, rva):
        offset, available = self.mapped(rva)
        end = self.data.find(b"\0", offset, offset + min(available, 4096))
        if end < 0 or end == offset:
            raise ValueError("empty or unterminated name")
        return self.data[offset:end].decode("ascii")

    def directory(self, index, minimum):
        if index >= len(self.directories):
            raise ValueError("missing data directory")
        rva, size = self.directories[index]
        if not rva or size < minimum or rva + size > 0x100000000:
            raise ValueError("missing or invalid data directory")
        return rva, size, self.offset(rva, size)

    def exports(self):
        rva, size, offset = self.directory(0, 40)
        nfns, nnames, funcs, names, ordinals = self.unpack("<IIIII", offset + 20)
        if not 0 < nnames <= nfns <= MAX_ITEMS:
            raise ValueError("invalid export counts")
        ft = self.offset(funcs, nfns * 4)
        nt = self.offset(names, nnames * 4)
        ot = self.offset(ordinals, nnames * 2)
        result = {}
        for i in range(nnames):
            name = self.string(self.unpack("<I", nt + i * 4)[0])
            ordinal = self.unpack("<H", ot + i * 2)[0]
            if ordinal >= nfns or name in result:
                raise ValueError("invalid export ordinal or duplicate name")
            target = self.unpack("<I", ft + ordinal * 4)[0]
            if not target or rva <= target < rva + size:
                raise ValueError("null or forwarded export is unsupported")
            # An export may point into a section's zero-filled virtual tail
            # (BSS-backed static data: legal, but not stored in the file);
            # mapped() returns a None offset for that and still raises on
            # RVAs outside every section — fail-closed on real corruption.
            self.mapped(target)
            result[name] = target
        return result

    def imports(self):
        _, size, offset = self.directory(1, 20)
        if size // 20 > MAX_ITEMS:
            raise ValueError("import table exceeds limit")
        result = []
        for i in range(size // 20):
            descriptor = self.unpack("<IIIII", offset + i * 20)
            if not any(descriptor):
                if not result:
                    raise ValueError("empty import table")
                return result
            if not descriptor[3] or not descriptor[4]:
                raise ValueError("invalid import descriptor")
            name = self.string(descriptor[3])
            if not name.lower().endswith(".dll") or any(c in name for c in '/\\:'):
                raise ValueError("invalid import DLL name")
            result.append(name)
        raise ValueError("unterminated import descriptor table")


def check_exports(path, want):
    exports = PE.read(path).exports()
    missing = set(want) - exports.keys()
    for name in want:
        print(f"export {'MISS' if name in missing else 'OK'} {name}")
    return 1 if missing else 0


def list_imports(path):
    return PE.read(path).imports()


def main(argv):
    if len(argv) < 3 or argv[1] not in ("exports", "imports"):
        print(__doc__, file=sys.stderr)
        return 64
    if argv[1] == "imports" and len(argv) != 3:
        return 64
    try:
        if argv[1] == "exports":
            if len(argv) < 4:
                # A vacuous "0 of 0 symbols present" check would gate-green
                # on any binary; refuse to certify an empty symbol list.
                print("exports requires at least one SYMBOL", file=sys.stderr)
                return 64
            return check_exports(argv[2], argv[3:])
        for name in list_imports(argv[2]):
            print(name)
        return 0
    except (OSError, ValueError, struct.error) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
