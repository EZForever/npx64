bits 32
default rel

image_base equ 00400000h

; ---

    org image_base
_image_dos_header:
    dw 'MZ'

_start:
    call .next
.next:
    pop ebx
    sub ebx, byte (.next - image_base)

    lea eax, [byte ebx + compressor_handle - image_base]
    push eax
    push 0
    push 5 ; COMPRESS_ALGORITHM_LZMS
    call [byte ebx + CreateDecompressor - image_base]

    lea eax, [ebx + compressed - image_base]
    mov ecx, compressed_size
    lea edx, [eax + ecx]
    push 0 ; UncompressedDataSize (a nullable pointer)
    push dword [eax + 8] ; LODWORD(COMPRESS_BUFFER_HEADER.qwUncompressedDataSize)
    push edx
    push ecx
    push eax
    push dword [byte ebx + compressor_handle - image_base]
    call [byte ebx + Decompress - image_base]

    jmp compressed + compressed_size

    times (3Ch - ($ - $$)) db 0
    dd _image_nt_headers - image_base

; ---

; NOTE: The directories are here for ease of access from code above

_image_iat_directory:
_image_iat_cabinet:
CreateDecompressor \
    dd 80000000h | 40 ; CreateDecompressor
Decompress \
    dd 80000000h | 43 ; Decompress
compressor_handle: ; NOTE: repurposed
    dd 0
_image_iat_directory_ends:
    ;

; ---

_image_import_directory:
    dd 0
    dd 0
    dd 0
    dd _image_import_name_cabinet - image_base
    dd _image_iat_cabinet - image_base
    
    dd 5 dup(0)
_image_import_directory_ends:
    ;

_image_import_name_cabinet:
    db 'CABINET', 0

; ---

_image_nt_headers:
    dd 'PE'

_image_file_header:
    dw 014Ch
    dw 0
    dd 0
    dd 0
    dd 0
    dw _image_optional_header_ends - _image_optional_header
    dw 0002h | 0100h ; IMAGE_FILE_EXECUTABLE_IMAGE | IMAGE_FILE_32BIT_MACHINE

_image_optional_header:
    dw 010Bh
    db 0, 0
    dd 0
    dd 0
    dd 0
    dd _start - image_base
    dd 0
    dd 0
    dd image_base
    dd 1
    dd 1
    dw 0, 0
    dw 0, 0
    dw 6, 0
    dd 0
    dd _image_ends - image_base
    dd 0
    dd 0
%ifdef NPXHDR_CLI
    dw 3 ; IMAGE_SUBSYSTEM_WINDOWS_CUI
%else
    dw 2 ; IMAGE_SUBSYSTEM_WINDOWS_GUI
%endif
    dw 0040h | 0100h | 8000h ; IMAGE_DLLCHARACTERISTICS_DYNAMIC_BASE | IMAGE_DLLCHARACTERISTICS_NX_COMPAT | IMAGE_DLLCHARACTERISTICS_TERMINAL_SERVER_AWARE
    dd 100000h
    dd 1000h
    dd 100000h
    dd 1000h
    dd 0
    dd 10h
_image_data_directories:
    dd 2 dup(0)
    dd _image_import_directory - image_base, _image_import_directory_ends - _image_import_directory
%ifdef NPXHDR_RSRC
    dd _image_resource_directory - image_base, _image_resource_directory_ends - _image_resource_directory
%else
    dd 2 dup(0)
%endif
    dd 2 dup(0)
    dd 2 dup(0)
    dd 2 dup(0)
    dd 2 dup(0)
    dd 2 dup(0)
    dd 2 dup(0)
    dd 2 dup(0)
    dd 2 dup(0)
    dd 2 dup(0)
    dd _image_iat_directory - image_base, _image_iat_directory_ends - _image_iat_directory
    dd 2 dup(0)
    dd 2 dup(0)
    dd 2 dup(0)
_image_optional_header_ends:
    ;

; ---

%ifdef NPXHDR_RSRC

_image_resource_directory:
    %include NPXHDR_RSRC
_image_resource_directory_ends:
    ;

%endif

; ---

compressed:
    incbin NPXHDR_PAYLOAD
compressed_size equ $ - compressed

; ---

    absolute $
    db NPXHDR_PAYLOAD_SIZE dup(?) ; The space for uncompressed npxldr

; ---

_image_ends:
    ;

