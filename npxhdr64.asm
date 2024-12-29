bits 64
default rel

image_base equ 0000000140000000h

; ---

    org image_base
_image_dos_header:
    dw 'MZ'

_start:
    lea rbx, [_image_dos_header] ;mov rbx, image_base

    xor edx, edx
    push rdx ; Stack alignment
    push rdx ; UncompressedDataSize (a nullable pointer)
    push rbx ; UncompressedBufferSize ; NOTE: Wrong, but should be reasonably large
    sub rsp, 20h ; shadow space

    xor ecx, ecx
    mov cl, 5 ; COMPRESS_ALGORITHM_LZMS
    ; rdx left as NULL
    lea r8, [byte rbx + compressor_handle - image_base]
    call [byte rbx + CreateDecompressor - image_base]

    mov rcx, [byte rbx + compressor_handle - image_base]
    lea rdx, [rbx + compressed - image_base]
    mov r8, [byte rbx + _compressed_size - image_base]
    lea r9, [rdx + r8]
    call [byte rbx + Decompress - image_base]

    add rsp, 20h + 10h + 8
    jmp compressed + compressed_size

    times (3Ch - ($ - $$)) db 0
    dd _image_nt_headers - image_base

; ---

; NOTE: The directories are here for ease of access from code above

_image_iat_directory:
_image_iat_cabinet:
CreateDecompressor \
    dq 8000000000000000h | 40 ; CreateDecompressor
Decompress \
    dq 8000000000000000h | 43 ; Decompress
compressor_handle: ; NOTE: repurposed
    dq 0
_image_iat_directory_ends:
    ;

; ---

_image_import_directory:
    dd 0
_compressed_size: ; NOTE: repurposed
    dd compressed_size
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
    dw 8664h
    dw 0
    dd 0
    dd 0
    dd 0
    dw _image_optional_header_ends - _image_optional_header
    dw 0002h | 0020h ; IMAGE_FILE_EXECUTABLE_IMAGE | IMAGE_FILE_LARGE_ADDRESS_AWARE

_image_optional_header:
    dw 020Bh
    db 0, 0
    dd 0
    dd 0
    dd 0
    dd _start - image_base
    dd 0
    dq image_base
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
    dq 100000h
    dq 1000h
    dq 100000h
    dq 1000h
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

