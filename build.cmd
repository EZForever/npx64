@echo off
pushd "%~dp0"

set "INFILE=infile.exe"
set "OUTFILE=outfile.exe"
set "NASM=nasm.exe"
set "LIBWIM=-"

:: Use this for better compression (if you have a copy of libwim DLL)
set "LIBWIM=libwim-15.dll"

nasm\nasm.exe -f bin npxldr64.asm -o npxldr64.bin
python npxpack.py "%INFILE%" "%OUTFILE%" "%NASM%" "%LIBWIM%"

popd