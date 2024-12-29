bits 64
default rel

npxldr:
    ; CreateFileA requires 3 on-stack arguments and a buffer of at least MAX_PATH + 1 bytes
    ; GetProcAddress(SetFileInformationByHandle) and SetFileInformationByHandle(FileRenameInfo) requires a 32-byte buffer
varsize equ 20h + 110h

%define var_args (rsp + 20h)
%define var_sbuf (rsp + 20h + 20h)
%define var_rbx (rsp + 20h + varsize)
%define var_r12 (rsp + 20h + varsize + 8 + 8 + 0)
%define var_r13 (rsp + 20h + varsize + 8 + 8 + 8)
%define var_r14 (rsp + 20h + varsize + 8 + 8 + 10h)
%define var_r15 (rsp + 20h + varsize + 8 + 8 + 18h)

    ; ---

    sub rsp, 20h + varsize + 8
    mov [var_rbx], rbx
    mov [var_r12], r12
    mov [var_r13], r13
    mov [var_r14], r14
    mov [var_r15], r15

    ; --- 1. Locate KERNEL32

    mov rax, gs:[60h] ; PEB
    mov rax, [rax + 18h] ; PEB_LDR_DATA
    mov rax, [rax + 20h] ; InMemoryOrderModuleList (#0 Self)
    mov rax, [rax] ; #1 NTDLL
    mov rax, [rax] ; #2 KERNEL32
    mov rbx, [rax - 10h + 30h] ; DllBase

    ; --- 2. Locate GetProcAddress

    mov eax, [rbx + 3Ch] ; IMAGE_DOS_HEADER.e_lfanew
    add rax, rbx
    mov eax, [rax + 18h + 70h + 0 + 0] ; IMAGE_NT_HEADERS.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress
    add rax, rbx

    mov r9, 'GetProcA'
    mov edx, [rax + 20h] ; IMAGE_EXPORT_DIRECTORY.AddressOfNames
    add rdx, rbx
    xor rcx, rcx
    dec rcx
.next:
    inc rcx
    mov r8d, [rdx + 4 * rcx]
    mov r8, [rbx + r8]
    cmp r8, r9
    jne .next

    mov edx, [rax + 24h] ; IMAGE_EXPORT_DIRECTORY.AddressOfNameOrdinals
    add rdx, rbx
    mov cx, [rdx + 2 * rcx]
    movzx ecx, cx

    mov eax, [rax + 1Ch] ; IMAGE_EXPORT_DIRECTORY.AddressOfFunctions
    add rax, rbx
    mov r12d, [rax + 4 * rcx]
    add r12, rbx

    ; --- 3. Get temp path and fill in sbuf

    ; GetProcAddress(GetTempPathA)
    mov rdx, 'GetTempP'
    mov [var_args], rdx
    mov rdx, 'athA'
    mov [var_args + 8], rdx
    mov rcx, rbx
    lea rdx, [var_args]
    call r12

    ; GetTempPathA(MAX_PATH + 1, sbuf)
    mov ecx, 260 + 1
    lea rdx, [var_sbuf]
    call rax

    ; GetProcAddress(GetTempFileNameA)
    mov rdx, 'GetTempF'
    mov [var_args], rdx
    mov rdx, 'ileNameA'
    mov [var_args + 8], rdx
    and byte [var_args + 10h], 0
    mov rcx, rbx
    lea rdx, [var_args]
    call r12

    ; GetTempFileNameA(sbuf, "npx", 0, sbuf)
    mov rdx, 'npx'
    mov [var_args], rdx
    lea rcx, [var_sbuf]
    lea rdx, [var_args]
    xor r8d, r8d
    mov r9, rcx
    call rax

    ; --- 4. Write out the bundled EXE

    ; GetProcAddress(CreateFileA)
    mov rdx, 'CreateFi'
    mov [var_args], rdx
    mov rdx, 'leA'
    mov [var_args + 8], rdx
    mov rcx, rbx
    lea rdx, [var_args]
    call r12
    mov r13, rax

    ; GetProcAddress(CloseHandle)
    mov rdx, 'CloseHan'
    mov [var_args], rdx
    mov rdx, 'dle'
    mov [var_args + 8], rdx
    mov rcx, rbx
    lea rdx, [var_args]
    call r12
    mov r14, rax

    ; CreateFileA(sbuf, GENERIC_WRITE, ...)
    lea rcx, [var_sbuf]
    mov edx, 40000000h ; GENERIC_WRITE
    mov r8d, 00000001h | 00000004h ; FILE_SHARE_READ | FILE_SHARE_DELETE
    xor r9, r9
    mov dword [var_args], 4 ; OPEN_ALWAYS
    mov dword [var_args + 8], 00000100h ; FILE_ATTRIBUTE_TEMPORARY
    and qword [var_args + 10h], 0
    call r13
    mov r15, rax

    ; GetProcAddress(WriteFile)
    mov rdx, 'WriteFil'
    mov [var_args], rdx
    mov rdx, 'e'
    mov [var_args + 8], rdx
    mov rcx, rbx
    lea rdx, [var_args]
    call r12

    ; WriteFile(hfile, _exedata, _exedata.dwImageSize, NULL, NULL)
    mov rcx, r15
    lea rdx, [_exedata]
    mov r8d, [rdx + 1Ch] ; IMAGE_DOS_HEADER.e_res[0 : 2]
    xor r9, r9
    and qword [var_args], 0
    call rax

    ; --- 5. LoadLibrary

    ; NOTE: LoadLibrary won't work if someone's holding the writer lock
    ; Opening new handle before the last one closes, prevent TOCTOU issues

    ; CreateFileA(sbuf, DELETE, ...)
    lea rcx, [var_sbuf]
    mov edx, 00010000h ; DELETE
    mov r8d, 00000001h | 00000002h | 00000004h ; FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE
    xor r9, r9
    mov dword [var_args], 3 ; OPEN_EXISTING
    mov dword [var_args + 8], 00000100h ; FILE_ATTRIBUTE_TEMPORARY
    and qword [var_args + 10h], 0
    call r13
    xchg r15, rax

    ; CloseHandle(hfile)
    mov rcx, rax
    call r14

    ; GetProcAddress(LoadLibraryA)
    mov rdx, 'LoadLibr'
    mov [var_args], rdx
    mov rdx, 'aryA'
    mov [var_args + 8], rdx
    mov rcx, rbx
    lea rdx, [var_args]
    call r12

    ; LoadLibraryA(sbuf)
    lea rcx, [var_sbuf]
    call rax

    ; Save entrypoint ptr
    ; From now on API errors can be ignored
    mov edx, [_exedata + 20h] ; IMAGE_DOS_HEADER.e_res[2 : 4]
    add rax, rdx
    mov [.entrypoint], rax

    ; --- 6. Delete the temp file
    ; ::$DATA renaming trick, via. https://github.com/LloydLabs/delete-self-poc

    ; GetProcAddress(SetFileInformationByHandle)
    mov rdx, 'SetFileI'
    mov [var_args], rdx
    mov rdx, 'nformati'
    mov [var_args + 8], rdx
    mov rdx, 'onByHand'
    mov [var_args + 10h], rdx
    mov rdx, 'le'
    mov [var_args + 18h], rdx
    mov rcx, rbx
    lea rdx, [var_args]
    call r12
    mov r12, rax ; This is the last needed proc

    ; (sizeof(FILE_RENAME_INFO) + 4 * sizeof(WCHAR)) == 32
    xorps xmm0, xmm0
    movaps [var_args], xmm0
    movaps [var_args + 10h], xmm0

    mov rdx, __?utf16?__(':NPX')
    mov dword [var_args + 10h], 8 ; FILE_RENAME_INFO.FileNameLength
    mov [var_args + 14h], rdx ; FILE_RENAME_INFO.FileName

    ; SetFileInformationByHandle(hfile, FileRenameInfo, args, 32)
    mov rcx, r15
    mov edx, 3 ; FileRenameInfo
    lea r8, [var_args]
    mov r9d, 32
    call r12

    ; Need another handle since the last one now "points to" the renamed ADS

    ; CreateFileA(sbuf, DELETE, ...)
    lea rcx, [var_sbuf]
    mov edx, 00010000h ; DELETE
    mov r8d, 00000001h | 00000004h ; FILE_SHARE_READ | FILE_SHARE_DELETE
    xor r9, r9
    mov dword [var_args], 3 ; OPEN_EXISTING
    mov dword [var_args + 8], 00000100h ; FILE_ATTRIBUTE_TEMPORARY
    and qword [var_args + 10h], 0
    call r13
    xchg r15, rax

    ; CloseHandle(hfile)
    mov rcx, rax
    call r14

    mov byte [var_args], 1 ; FILE_DISPOSITION_INFO.DeleteFile

    ; SetFileInformationByHandle(hfile, FileDispositionInfo, args, 1)
    mov rcx, r15
    mov edx, 4 ; FileDispositionInfo
    lea r8, [var_args]
    mov r9d, 1
    call r12

    ; CloseHandle(hfile)
    mov rcx, r15
    call r14

    ; ---

.end:
    mov r15, [var_r15]
    mov r14, [var_r14]
    mov r13, [var_r13]
    mov r12, [var_r12]
    mov rbx, [var_rbx]
    add rsp, 20h + varsize + 8

    mov rax, [.entrypoint]
    test rax, rax
    jz .end_failed
    jmp rax
.end_failed:
    ret

.entrypoint:
    dq 0

_exedata:
    ;

