#include <windows.h>
#include <tlhelp32.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <wchar.h>

static uintptr_t remote_module(DWORD pid,const wchar_t *name) {
    HANDLE snapshot=CreateToolhelp32Snapshot(TH32CS_SNAPMODULE,pid);
    MODULEENTRY32W entry; uintptr_t address=0;
    if(snapshot==INVALID_HANDLE_VALUE) return 0;
    entry.dwSize=sizeof(entry);
    if(Module32FirstW(snapshot,&entry)) do {
        if(!_wcsicmp(entry.szModule,name)) { address=(uintptr_t)entry.modBaseAddr; break; }
    } while(Module32NextW(snapshot,&entry));
    CloseHandle(snapshot); return address;
}
static int run_remote(HANDLE process,void *fn,void *parameter,DWORD *result) {
    HANDLE thread=CreateRemoteThread(process,0,0,(LPTHREAD_START_ROUTINE)fn,parameter,0,0);
    if(!thread) return 0;
    if(WaitForSingleObject(thread,15000)!=WAIT_OBJECT_0) { CloseHandle(thread); return -1; }
    if(!GetExitCodeThread(thread,result)) { CloseHandle(thread); return 0; }
    CloseHandle(thread); return 1;
}
int main(void) {
    int argc,code=2,status; DWORD pid,result=0;
    wchar_t **argv=CommandLineToArgvW(GetCommandLineW(),&argc),loaderPath[32768];
    HANDLE process=0; HMODULE local=0; void *remote=0; SIZE_T length;
    void *loader; MEMORY_BASIC_INFORMATION info; uintptr_t loaderBase,initOffset;
    if(!argv || argc!=3) { fprintf(stderr,"usage: inject PID absolute-dll-path\n"); goto done; }
    pid=wcstoul(argv[1],0,10);
    local=LoadLibraryExW(argv[2],0,DONT_RESOLVE_DLL_REFERENCES);
    if(!local) { code=3; goto done; }
    loader=(void *)GetProcAddress(local,"NativePauseInitialize");
    if(!loader) { code=4; goto done; }
    initOffset=(uintptr_t)loader-(uintptr_t)local;
    loader=(void *)GetProcAddress(GetModuleHandleW(L"kernel32.dll"),"LoadLibraryW");
    if(!VirtualQuery(loader,&info,sizeof(info)) || !GetModuleFileNameW(info.AllocationBase,loaderPath,32768)) { code=5; goto done; }
    loaderBase=remote_module(pid,wcsrchr(loaderPath,L'\\')+1);
    if(!loaderBase) { code=6; goto done; }
    loader=(void *)(loaderBase+(uintptr_t)loader-(uintptr_t)info.AllocationBase);
    process=OpenProcess(PROCESS_CREATE_THREAD|PROCESS_QUERY_INFORMATION|PROCESS_VM_OPERATION|PROCESS_VM_WRITE|PROCESS_VM_READ,FALSE,pid);
    if(!process) { code=7; goto done; }
    length=(wcslen(argv[2])+1)*sizeof(wchar_t);
    remote=VirtualAllocEx(process,0,length,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    if(!remote || !WriteProcessMemory(process,remote,argv[2],length,0)) { code=8; goto done; }
    status=run_remote(process,loader,remote,&result);
    /* 超时保留仍被工作线程引用的远端参数。模块始终保留至目标进程退出。 */
    if(status==-1) { remote=0; code=9; goto done; }
    if(status!=1 || !result) { code=10; goto done; }
    VirtualFreeEx(process,remote,0,MEM_RELEASE); remote=0;
    printf("DLL_MODULE=0x%08lx\n",result);
    status=run_remote(process,(void *)((uintptr_t)result+initOffset),0,&result);
    if(status!=1 || result!=1) { fprintf(stderr,"INITIALIZE_FAILED status=%d result=%lu\n",status,result); code=11; goto done; }
    puts("NATIVE_PAUSE_INITIALIZED=1"); code=0;
done:
    if(remote) VirtualFreeEx(process,remote,0,MEM_RELEASE);
    if(process) CloseHandle(process);
    if(local) FreeLibrary(local);
    if(argv) LocalFree(argv);
    if(code) fprintf(stderr,"inject failed code=%d win32=%lu\n",code,GetLastError());
    return code;
}
