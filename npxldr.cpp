#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winternl.h>

#pragma code_seg("NPXLDR")

// ---

typedef int(APIENTRY* ExeEntrypoint_t)();

#include <pshpack2.h>

typedef struct
{
	DWORD dwImageSize;
	DWORD dwEntryRva;
} NPXLDR_HEADER;

#include <poppack.h>

// ---

static IMAGE_DOS_HEADER* _pexedata();

__declspec(dllexport)
int npxldr()
{
	auto peb = NtCurrentTeb()->ProcessEnvironmentBlock;
	auto entry = peb->Ldr->InMemoryOrderModuleList.Flink; // #0 self
	entry = entry->Flink; // #1 ntdll
	entry = entry->Flink; // #2 kernel32

	auto kernel32 = (PBYTE)CONTAINING_RECORD(entry, LDR_DATA_TABLE_ENTRY, InMemoryOrderLinks)->DllBase;
	auto idh = (IMAGE_DOS_HEADER*)kernel32;
	auto inh = (IMAGE_NT_HEADERS*)(kernel32 + idh->e_lfanew);
	auto ied = (IMAGE_EXPORT_DIRECTORY*)(kernel32 + inh->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress);

	auto names = (DWORD*)(kernel32 + ied->AddressOfNames);
	auto ords = (WORD*)(kernel32 + ied->AddressOfNameOrdinals);
	auto funcs = (DWORD*)(kernel32 + ied->AddressOfFunctions);
	int i = 0;
	while (*(DWORD64*)(kernel32 + names[i]) != 0x41636F7250746547) // 'GetProcA'
	{
		i++;
	}

	auto pGetProcAddress = (decltype(GetProcAddress)*)(kernel32 + funcs[ords[i]]);

	// ---

	struct { DWORD64 v[4]; } strbuf;

#define KERNEL32_FUNC(name, ...) \
	strbuf = { { __VA_ARGS__ } }; \
	auto p##name = (decltype(name)*)pGetProcAddress((HMODULE)kernel32, (LPCSTR)&strbuf);

	KERNEL32_FUNC(GetTempPathA, 0x50706D6554746547, 0x0000000041687461);
	KERNEL32_FUNC(GetTempFileNameA, 0x46706D6554746547, 0x41656D614E656C69);
	KERNEL32_FUNC(CreateFileA, 0x6946657461657243, 0x000000000041656C);
	KERNEL32_FUNC(WriteFile, 0x6C69466574697257, 0x0000000000000065);
	KERNEL32_FUNC(LoadLibraryA, 0x7262694C64616F4C, 0x0000000041797261);
	KERNEL32_FUNC(CloseHandle, 0x6E614865736F6C43, 0x0000000000656C64);
	KERNEL32_FUNC(SetFileInformationByHandle, 0x49656C6946746553, 0x6974616D726F666E, 0x646E614879426E6F, 0x000000000000656C);

#ifdef _M_IX86
	strbuf = { { 0x3233495041564441 } }; // 'ADVAPI32'
	HMODULE advapi32 = pLoadLibraryA((LPCSTR)&strbuf);

#define ADVAPI32_FUNC(name, ...) \
	strbuf = { { __VA_ARGS__ } }; \
	auto p##name = (decltype(name)*)pGetProcAddress(advapi32, (LPCSTR)&strbuf);

	KERNEL32_FUNC(GetCurrentProcess, 0x6572727543746547, 0x7365636F7250746E, 0x0000000000000073);
	ADVAPI32_FUNC(OpenProcessToken, 0x636F72506E65704F, 0x6E656B6F54737365);
	ADVAPI32_FUNC(GetTokenInformation, 0x6E656B6F54746547, 0x74616D726F666E49, 0x00000000006E6F69);
	ADVAPI32_FUNC(SetTokenInformation, 0x6E656B6F54746553, 0x74616D726F666E49, 0x00000000006E6F69);
#endif

#undef KERNEL32_FUNC

	// ---

	// NOTE: https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-gettemppatha#return-value
	char temppath[MAX_PATH + 1];
	strbuf = { { 0x000000000078706E } }; // 'npx'
	pGetTempPathA(MAX_PATH + 1, temppath);
	pGetTempFileNameA(temppath, (LPCSTR)&strbuf, 0, temppath);

	idh = _pexedata();
	auto npxh = (NPXLDR_HEADER*)idh->e_res;

	HANDLE tempfile = pCreateFileA(temppath, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_DELETE, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_TEMPORARY, NULL);
	pWriteFile(tempfile, idh, npxh->dwImageSize, NULL, NULL);
	
	// LoadLibrary() won't work if someone's holding the writer lock
	// Opening new handle before the last one closes, prevent TOCTOU issues
	HANDLE tempfile2 = pCreateFileA(temppath, DELETE, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_TEMPORARY, NULL);
	pCloseHandle(tempfile);

	auto exe = (PBYTE)pLoadLibraryA(temppath);
	auto entrypoint = (ExeEntrypoint_t)(exe + npxh->dwEntryRva);

	// ---

	// Delete the temp file using the ::$DATA renaming trick
	// via. https://github.com/LloydLabs/delete-self-poc
	
#ifdef _M_IX86
	// This is for disabling UAC virtualization since it interferes with SetFileInformationByHandle renaming a NTFS ADS
	// Wow64DisableWow64FsRedirection is tested to be not working
	// https://github.com/LloydLabs/delete-self-poc/issues/3#issuecomment-1097483662

	HANDLE hToken;
	pOpenProcessToken(pGetCurrentProcess(), TOKEN_QUERY | TOKEN_ADJUST_DEFAULT, &hToken);

	DWORD uacinfoold;
	DWORD uacinfosize;
	pGetTokenInformation(hToken, TokenVirtualizationEnabled, &uacinfoold, sizeof(uacinfoold), &uacinfosize);

	DWORD uacinfo = 0;
	pSetTokenInformation(hToken, TokenVirtualizationEnabled, &uacinfo, sizeof(uacinfo));
#endif

	BYTE infobuf[sizeof(FILE_RENAME_INFO) + 4 * sizeof(WCHAR)] = { 0 };
	auto info = (FILE_RENAME_INFO*)infobuf;
	info->FileNameLength = 4 * sizeof(WCHAR);
	*(DWORD64*)info->FileName = 0x00580050004E003A; // L':NPX'
	pSetFileInformationByHandle(tempfile2, FileRenameInfo, infobuf, sizeof(infobuf));

	// Need another handle since the last one now "points to" the renamed ADS
	tempfile = pCreateFileA(temppath, DELETE, FILE_SHARE_READ | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_TEMPORARY, NULL);
	pCloseHandle(tempfile2);

	FILE_DISPOSITION_INFO info2 = { 0 };
	info2.DeleteFile = TRUE;
	pSetFileInformationByHandle(tempfile, FileDispositionInfo, &info2, sizeof(info2));

	// Commence deletion
	pCloseHandle(tempfile);

#ifdef _M_IX86
	uacinfo = uacinfoold;
	pSetTokenInformation(hToken, TokenVirtualizationEnabled, &uacinfo, sizeof(uacinfo));

	pCloseHandle(hToken);
#endif

	// ---

	return entrypoint();
}

#ifdef _M_IX86

__declspec(naked)
static IMAGE_DOS_HEADER* _pexedata()
{
	__asm
	{
		call $ + 5
		pop eax
		add eax, 5
		ret
	}
}

#else

static int _exedata();

__forceinline
static IMAGE_DOS_HEADER* _pexedata()
{
	return (IMAGE_DOS_HEADER*)_exedata;
}

static int _exedata()
{
	return 0x12345678;
}

#endif

