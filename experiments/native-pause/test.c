#define NATIVE_PAUSE_TEST
#define DllMain PrototypeDllMain
#include "pause.c"
#undef DllMain
#include <stdlib.h>
static int checks;
static volatile LONG stress_stop,stress_calls,stress_errors;
static int (__cdecl *stress_fn)(void);
static DWORD WINAPI stress_worker(void *unused) {
    while(!InterlockedCompareExchange(&stress_stop,0,0)) {
        if(stress_fn()!=42) InterlockedIncrement(&stress_errors);
        InterlockedIncrement(&stress_calls);
    }
    return 0;
}
static void check(int ok,const char *label) {
    checks++; if(!ok) { fprintf(stderr,"FAIL %s\n",label); exit(1); }
    printf("PASS %s\n",label);
}
int main(int argc,char **argv) {
    HMODULE lua;
    lua_State *L;
    lua_State *(__cdecl *newstate)(void);
    int (__cdecl *loadstring)(lua_State *,const char *);
    int (__cdecl *gettop)(lua_State *);
    void (__cdecl *settop)(lua_State *,int);
    int (__cdecl *toboolean)(lua_State *,int);
    void (__cdecl *close_lua)(lua_State *);
    void *g1,*g2; int variant;
    if(argc!=2) return 2;
    lua=LoadLibraryA(argv[1]); if(!lua) return 3;
#define LOAD(name,exported) name=(void *)GetProcAddress(lua,exported)
    LOAD(pushclosure,"lua_pushcclosure"); LOAD(setglobal,"lua_setglobal");
    LOAD(pushboolean,"lua_pushboolean"); LOAD(tointeger,"lua_tointegerx");
    LOAD(original_pcall,"lua_pcallk"); LOAD(newstate,"luaL_newstate");
    LOAD(loadstring,"luaL_loadstring"); LOAD(gettop,"lua_gettop");
    LOAD(settop,"lua_settop"); LOAD(toboolean,"lua_toboolean"); LOAD(close_lua,"lua_close");
    L=newstate(); g1=calloc(1,CONSOLE_OFFSET+8); g2=calloc(1,CONSOLE_OFFSET+8);
#define CALL(op) (loadstring(L,"return IsaacConsoleNativePausePrototype(" #op ")"),wrapped_pcall(L,0,1,0,0,0))
    for(variant=0;variant<3;variant++) {
    runtime=&runtimes[variant]; test_game=g1; owned=0; owner_game=0; test_other_pause=0;
    memset(g1,0,CONSOLE_OFFSET+8); memset(g2,0,CONSOLE_OFFSET+8);
    printf("RUNTIME_CONTRACT %s\n",runtime->name);
    check(CALL(1)==0 && toboolean(L,-1) && *console_state(test_game)==(runtime->independent_pause?0:2),"acquire pause without changing another backend state"); settop(L,0);
    check(CALL(1)==0 && toboolean(L,-1),"idempotent acquire"); settop(L,0);
    check(CALL(2)==0 && toboolean(L,-1) && *console_state(test_game)==(runtime->independent_pause?0:2),"owned query preserves console state"); settop(L,0);
    test_other_pause=1;
    check(CALL(2)==0 && !toboolean(L,-1),"other pause keeps screen authority"); settop(L,0);
    check(CALL(0)==0 && *console_state(test_game)==0 && test_other_pause,"release preserves other pause"); settop(L,0);
    check(CALL(1)==0 && !toboolean(L,-1),"cannot acquire during external pause"); settop(L,0);
    test_other_pause=0; *console_state(test_game)=2;
    check(CALL(1)==0 && !toboolean(L,-1),"cannot acquire original console"); settop(L,0);
    check(CALL(0)==0 && *console_state(test_game)==2,"release preserves original console"); settop(L,0);
    *console_state(test_game)=0;
    CALL(1); settop(L,0); *console_state(test_game)=0;
    if(runtime->independent_pause) {
        check(CALL(2)==0 && toboolean(L,-1) && owned,"REPENTOGON console reset cannot release owned pause"); settop(L,0);
        *console_state(g1)=2;
        check(CALL(2)==0 && !toboolean(L,-1) && *console_state(g1)==2,"REPENTOGON console keeps screen authority"); settop(L,0);
        CALL(0); settop(L,0);
        check(*console_state(g1)==2,"release preserves REPENTOGON console");
        *console_state(g1)=0;
    } else {check(CALL(2)==0 && !toboolean(L,-1) && !owned,"detect ownership loss"); settop(L,0);}
    CALL(1); settop(L,0); test_game=g2; *console_state(g2)=2;
    check(CALL(0)==0 && *console_state(g2)==2 && !owned,"new game state is not unpaused"); settop(L,0);
    check(CALL(99)==0 && !toboolean(L,-1),"unknown operation has no effect"); settop(L,0);
    check(gettop(L)==0,"bridge registration preserves Lua stack");
    }
    {
        unsigned char *code=VirtualAlloc(0,64,MEM_COMMIT|MEM_RESERVE,PAGE_EXECUTE_READWRITE);
        PausedFunction fn=(void *)code;
        /* 引擎 bool 只约定 AL；EAX 高位不保证清零。 */
        unsigned char body[]={0x55,0x8b,0xec,0xb8,0,0x34,0x12,0,0x5d,0xc3};
        memcpy(code,body,sizeof(body)); owned=0; owner_game=g1;
        check(MH_Initialize()==MH_OK && MH_CreateHook(code,owned_paused,(void **)&original_paused)==MH_OK
              && MH_EnableHook(code)==MH_OK,"install independent engine pause hook");
        check(!fn(g1,0),"independent unowned pause preserves engine result");
        owned=1;
        check(fn(g1,0) && !fn(g2,0),"independent pause affects only owned game");
        owned=0;
        check(!fn(g1,0),"independent release restores engine result");
        check(MH_DisableHook(code)==MH_OK && MH_RemoveHook(code)==MH_OK && MH_Uninitialize()==MH_OK,"remove isolated independent hook");
    }
    {
        unsigned char expected[]={0x55,0x8b,0xec,0x6a,0xff};
        unsigned char wrong[]={0,0,0,0,0};
        unsigned char *code=VirtualAlloc(0,64,MEM_COMMIT|MEM_RESERVE,PAGE_EXECUTE_READWRITE);
        int marker=0;
        Hook hook={0};
        void (__cdecl *fn)(void)=(void *)code;
        memcpy(code,expected,5);
        code[5]=0x83; code[6]=0xc4; code[7]=4;
        code[8]=0xc7; code[9]=5; *(uintptr_t *)(code+10)=(uintptr_t)&marker;
        *(int *)(code+14)=42; code[18]=0x5d; code[19]=0xc3;
        base=code;
        check(!prepare_suppression(&hook,0,wrong,5),"reject mismatched hook bytes");
        check(prepare_suppression(&hook,0,expected,5)
            && write_memory(hook.target,hook.jump,hook.length),"install isolated executable gateway");
        owned=0; fn(); check(marker==42,"original code executes without pause ownership");
        marker=0; owned=1; fn(); check(marker==0,"owned pause suppresses original code");
        owned=0;
        check(write_memory(hook.target,hook.original,hook.length),"restore original gateway bytes");
        fn(); check(marker==42,"restored original code executes");
    }
    {
        unsigned char expected[]={0x55,0x8b,0xec,0x6a,0xff};
        unsigned char tail[]={0x83,0xc4,4,0xb8,42,0,0,0,0x5d,0xc3};
        unsigned char *code=VirtualAlloc(0,64,MEM_COMMIT|MEM_RESERVE,PAGE_EXECUTE_READWRITE);
        Hook hook={0}; HANDLE workers[4]; int i,round;
        memcpy(code,expected,5); memcpy(code+5,tail,sizeof(tail)); base=code; owned=0;
        check(prepare_suppression(&hook,0,expected,5),"prepare synchronized gateway");
        check(MH_Initialize()==MH_OK,"initialize synchronized hook manager");
        check(MH_CreateHook(code,hook.stub,0)==MH_OK,"create synchronized hook");
        stress_fn=(void *)code;
        for(i=0;i<4;i++) workers[i]=CreateThread(0,0,stress_worker,0,0,0);
        check(workers[0]&&workers[1]&&workers[2]&&workers[3],"start four concurrent execution threads");
        for(round=0;round<100;round++) {
            if(MH_QueueEnableHook(code)!=MH_OK || MH_ApplyQueued()!=MH_OK
               || MH_QueueDisableHook(code)!=MH_OK || MH_ApplyQueued()!=MH_OK) {
                fprintf(stderr,"FAIL hook stress round=%d\n",round); exit(1);
            }
        }
        InterlockedExchange(&stress_stop,1); WaitForMultipleObjects(4,workers,TRUE,10000);
        for(i=0;i<4;i++) CloseHandle(workers[i]);
        check(stress_calls>0 && !stress_errors,"100 concurrent enable-disable cycles preserve result");
        check(MH_EnableHook(code)==MH_OK,"enable final hook");
        check(stress_fn()==42,"unowned synchronized hook preserves original behavior");
        check(MH_DisableHook(code)==MH_OK && MH_RemoveHook(code)==MH_OK
            && MH_Uninitialize()==MH_OK,"synchronized teardown restores original instructions");
        check(!memcmp(code,expected,5) && stress_fn()==42,"restored machine code still executes");
        printf("NATIVE_THREAD_STRESS_PASS threads=4 cycles=100 calls=%ld errors=%ld\n",stress_calls,stress_errors);
        VirtualFree(code,0,MEM_RELEASE); VirtualFree(hook.stub,0,MEM_RELEASE);
    }
    close_lua(L); printf("NATIVE_CONTRACT_PASS assertions=%d\n",checks); return 0;
}
