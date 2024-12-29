#!/usr/bin/env python3
import io
import os
import sys
import tempfile
import subprocess

from contextlib import closing

from exeopt import ExeOptimizer
from mscompress import WimlibCompressor

# ---

infile = sys.argv[1]
outfile = sys.argv[2]

nasm = sys.argv[3] if len(sys.argv) > 3 else 'nasm.exe'
libwim = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] != '-' else None

npxhdrs = [ 'npxhdr.asm', 'npxhdr64.asm' ]
npxldrs = [ 'npxldr.msvc.bin', 'npxldr64.bin' ]

with tempfile.TemporaryDirectory(prefix = 'npx') as workdir:
    print('workdir =', workdir)

    with open(infile, 'rb') as fin:
        with closing(ExeOptimizer(fin)) as exeopt:
            exesize = exeopt.size()
            bits = exeopt.bits()
            is_cli = exeopt.is_cli()
            print('exe size =', exesize, ',', 'bits =', bits, ',', 'CLI' if is_cli else 'GUI')

            rsrc = os.path.join(workdir, 'rsrc.asm')
            with open(rsrc, 'w') as frsrc:
                if not exeopt.extract_resource(frsrc):
                    rsrc = None

            exeopt.optimize('2r')
            exeopt.prepare_for_npxldr()

            with open(npxldrs[int(bits == 64)], 'rb') as fldr:
                npxldr = fldr.read()
            with io.BytesIO() as fout:
                fout.write(npxldr)
                exeopt.finish(fout)

                npxldr = fout.getvalue()
                ldrsize = len(npxldr)
    
    with closing(WimlibCompressor(libwim)) as compressor:
        npxldr = compressor.compress(npxldr)
    with open(os.path.join(workdir, 'npxldr.bin'), 'wb') as fldr:
        fldr.write(npxldr)
        del npxldr

    args = [
        nasm,
        npxhdrs[int(bits == 64)],
        '-f', 'bin',
        '-w-number-overflow', # XXX
        '-o', outfile,
        '-d', f"NPXHDR_PAYLOAD='{os.path.join(workdir, 'npxldr.bin')}'",
        '-d', f'NPXHDR_PAYLOAD_SIZE={ldrsize}'
    ]
    if is_cli:
        args.extend(['-d', 'NPXHDR_CLI'])
    if rsrc is not None:
        args.extend(['-d', f"NPXHDR_RSRC='{rsrc}'"])
    #print(' '.join(args))
    subprocess.run(args, shell = False, check = True)

    outsize = os.path.getsize(outfile)
    print('out size =', outsize, ',', '%5.2f%%' % (outsize / exesize * 100))

