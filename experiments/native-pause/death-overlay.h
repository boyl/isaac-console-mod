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
typedef struct { unsigned render,hints; } DeathLayout;
static DeathLayout death_layout={DEATH_RENDER_RVA,DEATH_HINT_RENDER_RVA};
/* 可识别的 Rep+ 绘制结构：从 Game 的死亡成员调用得到入口，
 * 再由零状态跳转核对同一函数的无栈参数返回路径。地址移动无需新增哈希。 */
static int discover_death_layout(const PauseImage *image,const Runtime *r,DeathLayout *out) {
    unsigned callsite=0,render=0,hints=0,exit_rva,s,count=0;
    IMAGE_SECTION_HEADER *sections=IMAGE_FIRST_SECTION(image->nt);
    const char *entry="538bdc83ec0883e4f883c404558b6b04896c24048bec6aff68????????64a100000000505381ec30010000a1????????33c58945ec5657508d45f464a3000000008bf989bdccfeffff833f00c785f4feffff000000000f84";
    const char *hint_entry="538bdc83ec0883e4f883c404558b6b04896c24048bec6aff68????????64a100000000505381ec900000005657a1????????33c5508d45f464a3000000008bf18975e8";
    if(!r || r->independent_pause || r->console_offset!=0x69468
       || !image_range(image,r->paused+0x35,8,IMAGE_SCN_MEM_EXECUTE)
       || !match_pattern(image->base+r->paused+0x35,"83ba20d501000075")
       || pattern_matches(image,"8d8f20d50100e8????????8d8f50d60100e8",&callsite)!=1
       || pattern_matches(image,hint_entry,&hints)!=1) return 0;
    render=callsite+11+*(int32_t *)(image->base+callsite+7);
    if(!image_range(image,render,0x5c,IMAGE_SCN_MEM_EXECUTE)
       || !match_pattern(image->base+render,entry)) return 0;
    exit_rva=render+0x5c+*(int32_t *)(image->base+render+0x58);
    if(exit_rva<=render+0x5c || exit_rva-render>0x2000
       || !image_range(image,exit_rva,0x1f,IMAGE_SCN_MEM_EXECUTE)
       || !match_pattern(image->base+exit_rva,"8b4df464890d00000000595f5e8b4dec33cde8????????8be55d8be35bc3cc")
       || !image_range(image,hints,0x4c6,IMAGE_SCN_MEM_EXECUTE)
       || !match_pattern(image->base+hints+0x4be,"8be55d8be35bc3cc")) return 0;
    /* 独立调用点证明该函数通过 Manager 子对象的 ECX 调用，无额外参数。 */
    for(s=0;s<image->nt->FileHeader.NumberOfSections;s++) {
        unsigned start=sections[s].VirtualAddress,size=sections[s].Misc.VirtualSize,i;
        if(!(sections[s].Characteristics&IMAGE_SCN_MEM_EXECUTE) || size<11
           || !image_range(image,start,size,IMAGE_SCN_MEM_EXECUTE)) continue;
        for(i=0;i+11<=size;i++) {
            const unsigned char *p=image->base+start+i;
            if(p[0]==0x8d && p[1]==0x8f && p[6]==0xe8
               && (unsigned)(start+i+11+*(int32_t *)(p+7))==hints) count++;
        }
    }
    if(count!=1) return 0;
    out->render=render;out->hints=hints;return 1;
}
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
    PauseImage image;
    int legacy=death_layout_matches(base,nt->OptionalHeader.SizeOfImage,digest);
    if(!legacy && (!inspect_image(base,&image) || !discover_death_layout(&image,runtime,&death_layout))) {
        log_event("DEATH_OVERLAY unavailable unsupported_layout"); return;
    }
    log_detail("DEATH_LAYOUT validated render=0x%X hints=0x%X mode=%s",death_layout.render,death_layout.hints,legacy?"known-J510":"structural");
    if(hook_result("death_render_create",MH_CreateHook(base+death_layout.render,overlay_death_render,(void **)&original_death_render))
       && hook_result("death_hints_create",MH_CreateHook(base+death_layout.hints,overlay_hint_render,(void **)&original_hint_render))
       && hook_result("death_render_queue",MH_QueueEnableHook(base+death_layout.render))
       && hook_result("death_hints_queue",MH_QueueEnableHook(base+death_layout.hints))
       && hook_result("death_apply",MH_ApplyQueued())) {
        death_hook_ready=1; log_event("DEATH_OVERLAY ready single_render_lease");
    } else log_event("DEATH_OVERLAY unavailable hook_failed");
}
