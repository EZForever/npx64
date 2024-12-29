# npx64

*PoC naive packer for x64 executables*

> [!NOTE]
> This repository is part of my *Year-end Things Clearance 2024* code dump, which implies the following things:
> 
> 1. The code in this repo is from one of my personal hobby projects (mainly) developed in 2024
> 2. Since it's a hobby project, expect PoC / alpha-quality code, and an *astonishing* lack of documentation
> 3. The project is archived by the time this repo goes public; there will (most likely) be no future updates
> 
> In short, if you wish to use the code here for anything good, think twice.

This project originates from my research in January 2024, which looks into the legendary [kkrunchy](https://github.com/farbrausch/fr_public/tree/master/kkrunchy) packer used by the demoscene groups, and aims to answer the question of: “How well a packer could do by delegating most of its work to preexisting code?” So far, the answer seems to be “pretty good, at least better than UPX in many scenarios”.

Many techniques are used to offload unpack stub functionality to Windows, making it as small as possible:

- The packed executable contains no section. Due to a obsolete feature in PE format standard supported by Windows, this enables the mapped address space to be RWX from start. Combined with a large enough `SizeOfImage` value, memory allocation could be completely avoided.
- The actual decompression is delegated to [Windows Compression API](https://learn.microsoft.com/en-us/windows/win32/cmpapi/-compression-portal), specifically using its LZMS support. LZMS is Microsoft's take on implementing LZMA, with  BCJ-like x86 instruction filter. Thus, it compresses better, and allows the phase 1 unpack code (in `npxhdr64.asm`) to fit entirely within the DOS header.
- With a [custom wrapper](mscompress.py) around wimlib, one can create even more compressed executable than just using Windows API for packing.
- Phase 2 (`npxldr64.asm`), aka the PE loading part, works by simply writing a file and calling `LoadLibrary()`. It turns out that most programs (at least the ones used by the demoscene group) doesn't really care if it's being loaded as a DLL; by converting them to DLLs at pack time, we can just let Windows do all the parsing and loading work for us.
- Resources are a special case: they tend to be fetched by the handle of running executable (via GetModuleHandle(NULL)), rather than the base address of calling code. To remedy this, resources are extracted and removed from original executable, and added to the packed one after compression.
- While converting the original executable, the packer also took the opportunity to erase several kinds of garbage data from the executable, making the compression more efficent.
- To avoid temp DLLs released by phase 2 code from wasting disk space, logic from [LloydLabs/delete-self-poc](https://github.com/LloydLabs/delete-self-poc) is added to remove the temp DLL from disk *immediately after it is loaded*. The program would still run just fine, just that any attempt to read that temp DLL would fail.
- Despite the repository name, this packer actually has experimental support for 32-bit x86 executables. (Well, this whole project is experimental, but this feature even more so.) It's just that due to WoW64 and UAC shenanigans, both phase 1 and 2 requires more bloat to work, and that added bloat makes the packer less effective that kkrunchy. If you wish to try it, compile `npxldr.cpp` into a shellcode-esque binary named `npxldr.bin`, and follow the instructions below. Don't expect it to work, though.

If you haven't realized yet, this packer is hacky *AF*, and I wouldn't recommend it for any serious and non-serious purposes. It also comes with the following free limitations:

- Windows Compression API requires Windows 8+, so the packed executable will not run on any system older than that.
- DLLs cannot be packed, at least not with current code. There is no plan for adding support either.
- You will most certainly run into problems if trying to pack anything bigger than a demo player, as that DLL loading method is not foolproof, and there has been zero testing about application compatibility.

If that still doesn't scare you off and you still want to give it a shot, you'll need a copy of NASM on PATH, and optionally wimlib DLL (usually named `libwim-15.dll`) in this directory. Then edit `build.cmd`, modify `INFILE` and `INFILE` variables (PoC code, remember?), and you're ready to go.

