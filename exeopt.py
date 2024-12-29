#!/usr/bin/env python3

__all__ = [
    'InvalidExeError',
    'ExeOptimizer'
]

# ---

import io

from typing import TextIO, BinaryIO

# ---

class InvalidExeError(RuntimeError):
    pass

class ExeOptimizer:
    def _readint(self, size: int) -> int:
        return int.from_bytes(self._exe.read(size), 'little')

    def _writeint(self, size: int, value: int) -> None:
        self._exe.write(value.to_bytes(size, 'little'))

    # (rva, vsize) -> (off, psize)
    def _rva_to_off(self, begin: int, size: int) -> tuple[int, int]:
        for vsize, rva, psize, off in self._sections:
            if rva <= begin < rva + vsize:
                delta = begin - rva
                if delta >= psize:
                    # Either BSS or null padding; abort
                    return -1, 0
                return off + delta, min(size, psize - delta)
        
        # Not found in any section; map to the header
        if begin >= self._size_exe:
            return -1, 0
        return begin, min(size, self._size_exe - begin)

    def _parse(self) -> None:
        # --- IMAGE_DOS_HEADER

        self._exe.seek(0)
        if self._readint(2) != 0x5A4D:
            raise InvalidExeError('Invalid IMAGE_DOS_HEADER signature')

        self._exe.seek(0x3C)
        self._off_nth = self._readint(4)

        # --- IMAGE_NT_HEADERS

        self._exe.seek(self._off_nth)
        if self._readint(4) != 0x00004550:
            raise InvalidExeError('Invalid IMAGE_NT_HEADERS signature')
        
        self._off_ifh = self._exe.tell()

        # --- IMAGE_FILE_HEADER

        machine = self._readint(2)
        if machine == 0x014C:
            self._bits = 32
        elif machine == 0x8664:
            self._bits = 64
        else:
            raise InvalidExeError('IMAGE_FILE_HEADER machine type not supported')

        section_count = self._readint(2)

        self._exe.seek(self._off_ifh + 16)
        size_oph = self._readint(2)
        
        self._ifh_flags = self._readint(2)
        if self._ifh_flags & 0x2000 != 0: # IMAGE_FILE_DLL
            raise InvalidExeError('DLL files are not supported')

        self._off_oph = self._exe.tell()
        self._off_sech = self._off_oph + size_oph

        # --- IMAGE_OPTIONAL_HEADER

        oph_sig = self._readint(2)
        if oph_sig not in (0x010B, 0x020B):
            raise InvalidExeError('Invalid IMAGE_OPTIONAL_HEADER signature')
        elif (oph_sig >> 4) * 2 != self._bits:
            raise InvalidExeError('IMAGE_OPTIONAL_HEADER signature mismatch')

        self._exe.seek(self._off_oph + 16)
        self._rva_ep = self._readint(4)
        if self._rva_ep == 0:
            raise InvalidExeError('Entrypoint RVA is null (should not happen on an EXE)')

        self._exe.seek(self._off_oph + 68)
        subsystem = self._readint(2)
        if subsystem == 2: # IMAGE_SUBSYSTEM_WINDOWS_GUI
            self._cli = False
        elif subsystem == 3: # IMAGE_SUBSYSTEM_WINDOWS_CUI
            self._cli = True
        else:
            raise InvalidExeError('IMAGE_FILE_HEADER subsystem not supported')

        self._exe.seek(self._off_oph + (92 if self._bits == 32 else 108))
        dir_count = self._readint(4)

        self._off_dir = self._exe.tell()

        # --- IMAGE_DATA_DIRECTORIES

        self._dirs = []
        for _ in range(dir_count):
            self._dirs.append((
                self._readint(4), # RVA
                self._readint(4), # Size
            ))

        # --- IMAGE_SECTION_HEADER
        
        self._sections = []
        self._exe.seek(self._off_sech)
        for _ in range(section_count):
            self._exe.read(8) # Name
            self._sections.append((
                self._readint(4), # Virtual size
                self._readint(4), # RVA
                self._readint(4), # Physical size
                self._readint(4), # Offset
            ))
            self._exe.read(16) # Other fields

    # ---

    def __init__(self, fin: BinaryIO):
        self._exe = io.BytesIO()
        try:
            while data := fin.read(0x1000):
                self._exe.write(data)
            self._size_exe = self._exe.tell()
            self._parse()
        except:
            self._exe.close()
            raise

    def close(self) -> None:
        if self._exe is not None:
            self._exe.close()
            self._exe = None

    def size(self) -> int:
        return self._size_exe

    def bits(self) -> int:
        return self._bits

    def is_cli(self) -> bool:
        return self._cli

    def finish(self, fout: BinaryIO) -> None:
        self._exe.seek(0)
        while data := self._exe.read(0x1000):
            fout.write(data)

    def optimize(self, steps: str) -> None:
        for step in steps:
            if step in self._OPT_STEP_GROUPS:
                self.optimize(self._OPT_STEP_GROUPS[step])
            elif step in self._OPT_STEPS:
                self._OPT_STEPS[step](self)
            else:
                raise ValueError('Invalid optimize step: ' + repr(step))

    # Extract the resource section to a npxhdr-compatible NASM listing
    # Run this before any optimization
    def extract_resource(self, fout: TextIO) -> bool:
        def __writeasm(size: int, value: int) -> None:
            __SIZE_TO_DIRECTIVE = {
                1: 'db',
                2: 'dw',
                4: 'dd',
                8: 'dq',
            }
            fout.write(f'{__SIZE_TO_DIRECTIVE[size]} {value}\n')

        def __readint_and_writeasm(size: int) -> int:
            value = self._readint(size)
            __writeasm(size, value)
            return value
        
        def __process_dir(base: int, off: int, levels: list[int], name: list[int], data_entry: list[int]) -> None:
            self._exe.seek(base + off)
            
            levels_str = '_'.join(str(x) for x in levels)
            fout.write(f'.dir_{levels_str}:\n')
            __readint_and_writeasm(4)
            __readint_and_writeasm(4)
            __readint_and_writeasm(2)
            __readint_and_writeasm(2)
            name_count = __readint_and_writeasm(2)
            id_count = __readint_and_writeasm(2)

            subdirs = []
            for i, has_name in enumerate([True] * name_count + [False] * id_count):
                fout.write(f'.dir_entry_{levels_str}_{i}:\n')
                if has_name:
                    fout.write(f'dd .name_{len(name)} - .begin\n')
                    name.append(self._readint(4))
                else:
                    __readint_and_writeasm(4)

                off_new = self._readint(4)
                if off_new & 0x80000000 == 0:
                    fout.write(f'dd .data_entry_{len(data_entry)} - .begin\n')
                    data_entry.append(off_new)
                else:
                    fout.write(f'dd 80000000h | (.dir_{levels_str}_{len(subdirs)} - .begin)\n')
                    subdirs.append(off_new & ~0x80000000)

            for i, x in enumerate(subdirs):
                levels.append(i)
                __process_dir(base, x, levels, name, data_entry)
                levels.pop()

        # ---

        rva_res, size_res = self._dirs[2]
        if rva_res == 0 or size_res == 0:
            return False # resource directory does not exist
        
        off_res, size_res = self._rva_to_off(rva_res, size_res)
        if off_res < 0:
            return False # resource directory in BSS?
        
        fout.write('.begin:\n')

        name = []
        data_entry = []
        __process_dir(off_res, 0, [0], name, data_entry)

        for i, x in enumerate(name):
            fout.write(f'.name_{i}:\n')
            __writeasm(2, len(x))
            fout.write(f'db {",".join(str(c) for c in x)}\n')
        
        data = []
        for i, x in enumerate(data_entry):
            self._exe.seek(off_res + x)

            fout.write(f'.data_entry_{i}:\n')
            rva = self._readint(4)
            fout.write(f'dd .data_{len(data)} - image_base\n')
            vsize = __readint_and_writeasm(4)
            __readint_and_writeasm(4)
            __readint_and_writeasm(4)

            off, psize = self._rva_to_off(rva, vsize)
            if off < 0:
                blob = b'\0' * vsize
            else:
                self._exe.seek(off)
                blob = self._exe.read(psize)
                if psize < vsize:
                    blob += b'\0' * (vsize - psize)

            data.append(blob)

        for i, x in enumerate(data):
            fout.write(f'.data_{i}:\n')
            fout.write(f'db {",".join(str(c) for c in x)}\n')
        
        return len(data_entry) > 0

    # Convert the EXE to a npxldr-compatible DLL
    # Run this after any optimization
    def prepare_for_npxldr(self) -> None:
        self._exe.seek(0x1C)
        if self._readint(8) != 0:
            raise RuntimeWarning('IMAGE_DOS_HEADER reserved fields are in use')
        
        self._exe.seek(0x1C)
        self._writeint(4, self._size_exe)
        self._writeint(4, self._rva_ep)

        self._exe.seek(self._off_ifh + 18)
        self._writeint(2, self._ifh_flags | 0x2000) # IMAGE_FILE_DLL

        self._exe.seek(self._off_oph + 16)
        self._writeint(4, 0)

    # ---

    # Remove DOS stub & Rich header
    def opt_headers(self) -> None:
        self._exe.seek(0)
        self._exe.write(b'\0' * self._off_nth)

        self._exe.seek(0)
        self._writeint(2, 0x5A4D)
        self._exe.seek(0x3C)
        self._writeint(4, self._off_nth)

    # Remove a specific data directory
    def opt_directory(self, idx: int) -> None:
        rva_res, size_res = self._dirs[idx]
        if rva_res != 0 and size_res != 0:
            off_res, size_res = self._rva_to_off(rva_res, size_res)
            if off_res >= 0:
                self._exe.seek(off_res)
                self._exe.write(b'\0' * size_res)
        
        self._exe.seek(self._off_dir + 8 * idx)
        self._writeint(8, 0)

    _OPT_STEPS = {
        'h': opt_headers,
        'r': lambda self: self.opt_directory(2), # Resource directory
        'c': lambda self: self.opt_directory(4), # Certificate directory
        'd': lambda self: self.opt_directory(6), # Debugging information directory
        # TODO
    }

    _OPT_STEP_GROUPS = {
        '0': '',
        '1': 'hrcd', # TODO
        '2': '1', # TODO
    }

