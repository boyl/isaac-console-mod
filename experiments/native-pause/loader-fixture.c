#include <windows.h>
#include <stdio.h>
#include <wchar.h>
#ifdef NATIVE_FIXTURE_DLL
static HINSTANCE module;
BOOL WINAPI DllMain(HINSTANCE self,DWORD reason,LPVOID unused) {
    if(reason==DLL_PROCESS_ATTACH) module=self;
    return TRUE;
}
__declspec(dllexport) DWORD WINAPI NativePauseInitialize(LPVOID unused) {
    wchar_t path[32768]; FILE *file;
    GetModuleFileNameW(module,path,32768);
    wcscpy(wcsrchr(path,L'\\')+1,L"fixture-ready.txt");
    file=_wfopen(path,L"w");
    if(!file) return 0;
    fputs("EXPLICIT_INITIALIZATION_PASS",file); fclose(file); return 1;
}
#else
int main(void) { Sleep(60000); return 0; }
#endif
