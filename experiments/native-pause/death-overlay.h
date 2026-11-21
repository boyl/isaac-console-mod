/* J510 GameOver::Render is thiscall void(), ECX=this, no stack arguments.
 * A Lua render grants one draw lease, consumed even if the owner changed.
 * No game state is written; missed callbacks/luareset restore native drawing. */
#define DEATH_RENDER_RVA 0x5afb20
#define DEATH_STATE_OFFSET 0x1d520
#define DEATH_HINT_RENDER_RVA 0x24a60
typedef void (__fastcall *DeathRenderFunction)(void *,void *);
static DeathRenderFunction original_death_render;
static DeathRenderFunction original_hint_render;
static int death_hook_ready;
static void *death_owner;
static void *hint_owner;
static int death_layout_matches(const unsigned char *image,size_t size,const char *digest) {
    static const unsigned char entry[]={0x53,0x8b,0xdc,0x83,0xec,0x08,0x83,0xe4,0xf8};
    static const unsigned char callsite[]={0x8d,0x8f,0x20,0xd5,0x01,0x00,0xe8,0x4b,0xc7,0x2a,0x00};
    static const unsigned char statecheck[]={0x8b,0xf9,0x89,0xbd,0xcc,0xfe,0xff,0xff,0x83,0x3f,0x00};
    static const unsigned char epilogue[]={0x8b,0xe5,0x5d,0x8b,0xe3,0x5b,0xc3};
    static const unsigned char hintcall[]={0x8d,0x8f,0x28,0xac,0x04,0x00,0xe8,0x66,0x94,0xab,0xff};
    return size>0x5b0a1b && !strcmp(digest,runtimes[3].sha256)
        && !memcmp(image+DEATH_RENDER_RVA,entry,sizeof(entry))
        && !memcmp(image+0x3033ca,callsite,sizeof(callsite))
        && !memcmp(image+0x5afb61,statecheck,sizeof(statecheck))
        && !memcmp(image+0x5b0a15,epilogue,sizeof(epilogue))
        && !memcmp(image+DEATH_HINT_RENDER_RVA,entry,sizeof(entry))
        && !memcmp(image+0x56b5ef,hintcall,sizeof(hintcall))
        && !memcmp(image+0x24f1e,epilogue,sizeof(epilogue));
}
static void __fastcall overlay_hint_render(void *surface,void *unused) {
    void *lease=hint_owner;
    hint_owner=0;
    /* Manager's two corner hints are a separate, later draw than GameOver. */
    if(lease && lease==game() && *(int *)((unsigned char *)lease+DEATH_STATE_OFFSET)!=0) return;
    original_hint_render(surface,0);
}
static void __fastcall overlay_death_render(void *surface,void *unused) {
    void *lease=death_owner;
    death_owner=0;
    if(lease && lease==game() && surface==(unsigned char *)lease+DEATH_STATE_OFFSET
       && *(int *)surface!=0) return;
    original_death_render(surface,0);
}
static int death_overlay_bridge(lua_State *L) {
    int valid=0,op=(int)tointeger(L,1,&valid),result=0;
    void *g=game();
    if(valid && op==0) {death_owner=0; hint_owner=0;}
    else if(valid && op==2) result=death_hook_ready;
    else if(valid && op==1 && death_hook_ready && g
            && *(int *)((unsigned char *)g+DEATH_STATE_OFFSET)!=0) {
        death_owner=g; hint_owner=g; result=1;
    }
    pushboolean(L,result); return 1;
}
static void initialize_death_overlay(const char *digest) {
    IMAGE_NT_HEADERS *nt=(void *)(base+((IMAGE_DOS_HEADER *)base)->e_lfanew);
    if(!death_layout_matches(base,nt->OptionalHeader.SizeOfImage,digest)) {
        log_event("DEATH_OVERLAY unavailable unsupported_layout"); return;
    }
    if(hook_result("death_render_create",MH_CreateHook(base+DEATH_RENDER_RVA,overlay_death_render,(void **)&original_death_render))
       && hook_result("death_hints_create",MH_CreateHook(base+DEATH_HINT_RENDER_RVA,overlay_hint_render,(void **)&original_hint_render))
       && hook_result("death_render_queue",MH_QueueEnableHook(base+DEATH_RENDER_RVA))
       && hook_result("death_hints_queue",MH_QueueEnableHook(base+DEATH_HINT_RENDER_RVA))
       && hook_result("death_apply",MH_ApplyQueued())) {
        death_hook_ready=1; log_event("DEATH_OVERLAY ready J510 single_render_lease");
    } else log_event("DEATH_OVERLAY unavailable hook_failed");
}
