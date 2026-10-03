#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>
#include <bcrypt.h>
#include "vendor/minhook/include/MinHook.h"

/* 当前 J460 的离线反汇编证据；加载器另行验证完整 EXE SHA-256。 */
#define GAME_PTR_RVA 0x871678
#define CONSOLE_OFFSET 0x68d78
#define PAUSED_RVA 0x2fd350
#define PCALL_IAT_RVA 0x7183d8
typedef struct {
    const char *name,*sha256;
    unsigned game_ptr,console_offset,paused,pcall_iat,input,render;
    unsigned char paused_bytes[7],input_bytes[6],render_bytes[6];
    int paused_length,input_length,render_length;
} Runtime;
static const Runtime runtimes[]={
    {"Repentance+ J460","3BDFC8BAE0DC7E334B76009D0AD45DFBB16EE5F00C06FFBC3A0094E34D44616B",
     0x871678,0x68d78,0x2fd350,0x7183d8,0x28b260,0x28c2e0,
     {0x8b,0xd1,0x56,0x8b,0x35},{0x55,0x8b,0xec,0x6a,0xff},{0x53,0x8b,0xdc,0x83,0xec,0x08},5,5,6},
    {"Repentance 1.7.9b","04469D0C3D3581936FCF85BEA5F9F4F3A65B2CCF96B36310456C9626BAC36DC6",
     0x7fd65c,0x1bb80,0x2d0380,0x60623c,0x263550,0x263d10,
     {0x83,0xb9,0x80,0xbb,0x01,0,0},{0x55,0x8b,0xec,0x83,0xec,0x3c},{0x55,0x8b,0xec,0x6a,0xff},7,6,5}
};
static const Runtime *runtime=&runtimes[0];
typedef struct lua_State lua_State;
typedef int (__cdecl *LuaC)(lua_State *);
typedef int (__cdecl *Pcall)(lua_State *,int,int,int,int,void *);
static Pcall original_pcall;
static void (__cdecl *pushclosure)(lua_State *,LuaC,int);
static void (__cdecl *setglobal)(lua_State *,const char *);
static void (__cdecl *pushboolean)(lua_State *,int);
static long long (__cdecl *tointeger)(lua_State *,int,int *);
static unsigned char *base;
static volatile unsigned char owned;
static void *owner_game;
static FILE *logfile;
static void log_event(const char *event) {
    if(logfile) { fprintf(logfile,"%lu %s\n",GetTickCount(),event); fflush(logfile); }
}
#ifdef NATIVE_PAUSE_TEST
static void *test_game;
static int test_other_pause;
static void *game(void) { return test_game; }
#else
static void *game(void) { return *(void **)(base+runtime->game_ptr); }
#endif
static int *console_state(void *g) { return (int *)((unsigned char *)g+runtime->console_offset); }
static int native_paused(void *g) {
#ifdef NATIVE_PAUSE_TEST
    return test_other_pause || *console_state(g)!=0;
#else
    int result;
    void *fn=base+runtime->paused;
#ifdef _MSC_VER
    __asm {
        mov ecx,g
        mov eax,fn
        call eax
        movzx eax,al
        mov result,eax
    }
#else
    __asm__ volatile("mov %1, %%ecx; call *%2; movzbl %%al, %0"
        : "=r"(result) : "r"(g), "r"(fn) : "eax","ecx","edx","memory");
#endif
    return result;
#endif
}
static void release_pause(void) {
    void *g=game();
    if(owned && g==owner_game && *console_state(g)==2) *console_state(g)=0;
    if(owned) log_event("RELEASE");
    owned=0; owner_game=0;
}
static int bridge(lua_State *L) {
    int valid=0, op=(int)tointeger(L,1,&valid), result=0;
    void *g=game();
    if(owned && (g!=owner_game || !g || *console_state(g)!=2)) {
        owned=0; owner_game=0; log_event("OWNERSHIP_LOST");
    }
    if(valid && op==0) release_pause();
    else if(valid && op==1 && g) {
        if(!owned && *console_state(g)==0 && !native_paused(g)) {
            owner_game=g; owned=1; *console_state(g)=2; log_event("ACQUIRE");
        }
        result=owned;
    } else if(valid && op==2 && owned) {
        /* 其他暂停原因仍拥有画面，Lua 菜单不能覆盖它们。 */
        *console_state(g)=0;
        result=!native_paused(g);
        *console_state(g)=2;
    }
    pushboolean(L,result);
    return 1;
}
static int __cdecl wrapped_pcall(lua_State *L,int args,int results,int error,int ctx,void *continuation) {
    /* 两次操作净栈变化为零；每次注册以支持 luareset 和同地址重建。 */
    pushclosure(L,bridge,0);
    setglobal(L,"IsaacConsoleNativePausePrototype");
    return original_pcall(L,args,results,error,ctx,continuation);
}
static int write_memory(void *where,const void *bytes,size_t size) {
    DWORD old,unused;
    if(!VirtualProtect(where,size,PAGE_EXECUTE_READWRITE,&old)) return 0;
    memcpy(where,bytes,size);
    FlushInstructionCache(GetCurrentProcess(),where,size);
    VirtualProtect(where,size,old,&unused);
    return 1;
}
typedef struct { unsigned char *target,*stub; unsigned char original[6],jump[6]; int length; } Hook;
static int prepare_suppression(Hook *hook,unsigned rva,const unsigned char *expected,int length) {
    unsigned char *target=base+rva, *stub;
    unsigned char jump[6]={0xe9,0,0,0,0,0x90};
    if(memcmp(target,expected,length)) return 0;
    stub=VirtualAlloc(0,64,MEM_COMMIT|MEM_RESERVE,PAGE_EXECUTE_READWRITE);
    if(!stub) return 0;
    /* cmp byte [owned],0; je original; ret; 原指令; jmp continuation */
    stub[0]=0x80; stub[1]=0x3d; *(uintptr_t *)(stub+2)=(uintptr_t)&owned;
    stub[6]=0; stub[7]=0x74; stub[8]=1; stub[9]=0xc3;
    memcpy(stub+10,expected,length);
    stub[10+length]=0xe9;
    *(int *)(stub+11+length)=(int)(target+length-(stub+15+length));
    *(int *)(jump+1)=(int)(stub-(target+5));
    hook->target=target; hook->stub=stub; hook->length=length;
    memcpy(hook->original,expected,length); memcpy(hook->jump,jump,length);
    return 1;
}
static HINSTANCE module;
static LONG initialized;
static int exe_sha256(char output[65]) {
    wchar_t path[32768]; unsigned char chunk[65536],digest[32]; DWORD read; int i,ok=0;
    BCRYPT_ALG_HANDLE algorithm=0; BCRYPT_HASH_HANDLE hash=0; HANDLE file=INVALID_HANDLE_VALUE;
    if(!GetModuleFileNameW(0,path,32768)) return 0;
    file=CreateFileW(path,GENERIC_READ,FILE_SHARE_READ,0,OPEN_EXISTING,FILE_FLAG_SEQUENTIAL_SCAN,0);
    if(file==INVALID_HANDLE_VALUE) return 0;
    if(BCryptOpenAlgorithmProvider(&algorithm,BCRYPT_SHA256_ALGORITHM,0,0)<0
       || BCryptCreateHash(algorithm,&hash,0,0,0,0,0)<0) goto done;
    for(;;) {
        if(!ReadFile(file,chunk,sizeof(chunk),&read,0)) goto done;
        if(!read) break;
        if(BCryptHashData(hash,chunk,read,0)<0) goto done;
    }
    if(BCryptFinishHash(hash,digest,sizeof(digest),0)<0) goto done;
    for(i=0;i<32;i++) sprintf(output+i*2,"%02X",digest[i]);
    ok=1;
done:
    if(hash) BCryptDestroyHash(hash);
    if(algorithm) BCryptCloseAlgorithmProvider(algorithm,0);
    CloseHandle(file); return ok;
}
__declspec(dllexport) DWORD WINAPI NativePauseInitialize(LPVOID reserved) {
    HMODULE lua;
    wchar_t path[32768];
    char digest[65]; int i;
    Hook input_hook={0},render_hook={0};
    if(InterlockedCompareExchange(&initialized,1,0)!=0) return 10;
    if(!GetModuleFileNameW(module,path,32768) || !wcsrchr(path,L'\\')) return 11;
    wcscpy(wcsrchr(path,L'\\')+1,L"native-pause.log");
    logfile=_wfopen(path,L"a");
    if(!exe_sha256(digest)) { log_event("DISABLED EXE hash unavailable"); return 16; }
    runtime=0;
    for(i=0;i<sizeof(runtimes)/sizeof(runtimes[0]);i++) if(!strcmp(digest,runtimes[i].sha256)){runtime=&runtimes[i];break;}
    if(!runtime){log_event("DISABLED unsupported EXE hash");return 17;}
    base=(unsigned char *)GetModuleHandleW(0);
    lua=GetModuleHandleA("Lua5.3.3r.dll");
    if(!lua || memcmp(base+runtime->paused,runtime->paused_bytes,runtime->paused_length)
        || memcmp(base+runtime->input,runtime->input_bytes,runtime->input_length)
        || memcmp(base+runtime->render,runtime->render_bytes,runtime->render_length)) return FALSE;
    pushclosure=(void *)GetProcAddress(lua,"lua_pushcclosure");
    setglobal=(void *)GetProcAddress(lua,"lua_setglobal");
    pushboolean=(void *)GetProcAddress(lua,"lua_pushboolean");
    tointeger=(void *)GetProcAddress(lua,"lua_tointegerx");
    if(!pushclosure || !setglobal || !pushboolean || !tointeger) return FALSE;
    original_pcall=*(Pcall *)(base+runtime->pcall_iat);
    if((void *)original_pcall!=(void *)GetProcAddress(lua,"lua_pcallk")) return FALSE;
    if(!prepare_suppression(&input_hook,runtime->input,runtime->input_bytes,runtime->input_length)
       || !prepare_suppression(&render_hook,runtime->render,runtime->render_bytes,runtime->render_length)) return FALSE;
    if(MH_Initialize()!=MH_OK) return 12;
    if(MH_CreateHook(input_hook.target,input_hook.stub,0)!=MH_OK
       || MH_CreateHook(render_hook.target,render_hook.stub,0)!=MH_OK
       || MH_QueueEnableHook(input_hook.target)!=MH_OK
       || MH_QueueEnableHook(render_hook.target)!=MH_OK
       || MH_ApplyQueued()!=MH_OK) {
        log_event("DISABLED hook initialization failed");
        /* 不卸载：部分生效的跳板仍可能引用本模块，owned 始终为零。 */
        return 13;
    }
    { DWORD old,unused;
      if(!VirtualProtect(base+runtime->pcall_iat,sizeof(Pcall),PAGE_READWRITE,&old)) return 14;
      /* 对齐 IAT 入口原子交换；其他线程永远看到完整旧或新指针。 */
      if(InterlockedCompareExchangePointer((PVOID *)(base+runtime->pcall_iat),
          (PVOID)wrapped_pcall,(PVOID)original_pcall)!=(PVOID)original_pcall) {
          VirtualProtect(base+runtime->pcall_iat,sizeof(Pcall),old,&unused);
          log_event("DISABLED IAT changed during initialization"); return 15;
      }
      VirtualProtect(base+runtime->pcall_iat,sizeof(Pcall),old,&unused);
    }
    log_event(runtime->name);
    log_event("LOADED native-pause 0.2.0");
    return 1;
}
#ifdef NATIVE_PAUSE_AUTO
static DWORD WINAPI automatic_initialize(void *unused) {
    int attempt;
    for(attempt=0;attempt<600;attempt++) {
        if(GetModuleHandleW(L"Lua5.3.3r.dll")) return NativePauseInitialize(0);
        Sleep(50);
    }
    /* 即使没有 Lua 也执行哈希拒绝，便于非游戏启动测试输出可观察证据。 */
    return NativePauseInitialize(0);
}
#endif
BOOL WINAPI DllMain(HINSTANCE self,DWORD reason,LPVOID reserved) {
    if(reason==DLL_PROCESS_ATTACH) {
        module=self; DisableThreadLibraryCalls(self);
#ifdef NATIVE_PAUSE_AUTO
        HANDLE worker=CreateThread(0,0,automatic_initialize,0,0,0);
        if(!worker) return FALSE;
        CloseHandle(worker);
#endif
    }
    /* 挂钩与日志初始化必须在加载器锁之外执行。进程退出统一释放资源。 */
    return TRUE;
}
