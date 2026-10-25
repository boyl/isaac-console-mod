/* 固定 RVA 适配器的兼容检测；本文件不写内存、不安装挂钩。 */
#include <stdarg.h>
#include "vendor/minhook/src/hde/hde32.h"

static void log_detail(const char *format,...) {
    char message[2048]; va_list args;
    va_start(args,format); vsnprintf(message,sizeof(message),format,args); va_end(args);
    log_event(message);
}

static int readable_range(const void *pointer,size_t bytes,int writable) {
    uintptr_t cursor=(uintptr_t)pointer,end=cursor+bytes;
    if(!cursor || end<cursor) return 0;
    while(cursor<end) {
        MEMORY_BASIC_INFORMATION m;
        DWORD protection;
        uintptr_t next;
        if(!VirtualQuery((void *)cursor,&m,sizeof(m)) || m.State!=MEM_COMMIT
           || (m.Protect&(PAGE_GUARD|PAGE_NOACCESS))) return 0;
        protection=m.Protect&0xff;
        if(writable ? !(protection==PAGE_READWRITE || protection==PAGE_WRITECOPY
                        || protection==PAGE_EXECUTE_READWRITE || protection==PAGE_EXECUTE_WRITECOPY)
                    : !(protection==PAGE_READONLY || protection==PAGE_READWRITE || protection==PAGE_WRITECOPY
                        || protection==PAGE_EXECUTE_READ || protection==PAGE_EXECUTE_READWRITE || protection==PAGE_EXECUTE_WRITECOPY)) return 0;
        next=(uintptr_t)m.BaseAddress+m.RegionSize;
        if(next<=cursor) return 0;
        cursor=next;
    }
    return 1;
}

typedef struct { unsigned char *base; unsigned size; IMAGE_NT_HEADERS32 *nt; } PauseImage;
static int inspect_image(unsigned char *address,PauseImage *out) {
    IMAGE_DOS_HEADER *dos=(void *)address; IMAGE_NT_HEADERS32 *nt;
    if(!readable_range(address,sizeof(*dos),0) || dos->e_magic!=IMAGE_DOS_SIGNATURE
       || dos->e_lfanew<sizeof(*dos) || dos->e_lfanew>0x100000) return 0;
    nt=(void *)(address+dos->e_lfanew);
    if(!readable_range(nt,sizeof(*nt),0) || nt->Signature!=IMAGE_NT_SIGNATURE
       || nt->FileHeader.Machine!=IMAGE_FILE_MACHINE_I386
       || nt->OptionalHeader.Magic!=IMAGE_NT_OPTIONAL_HDR32_MAGIC
       || nt->FileHeader.SizeOfOptionalHeader!=sizeof(IMAGE_OPTIONAL_HEADER32)
       || !nt->FileHeader.NumberOfSections || nt->FileHeader.NumberOfSections>96
       || !readable_range(IMAGE_FIRST_SECTION(nt),nt->FileHeader.NumberOfSections*sizeof(IMAGE_SECTION_HEADER),0)) return 0;
    out->base=address; out->size=nt->OptionalHeader.SizeOfImage; out->nt=nt;
    return out->size>nt->OptionalHeader.SizeOfHeaders;
}

static int image_range(const PauseImage *image,unsigned rva,unsigned length,DWORD flags) {
    IMAGE_SECTION_HEADER *sections=IMAGE_FIRST_SECTION(image->nt); unsigned i;
    if(rva>image->size || length>image->size-rva || !readable_range(image->base+rva,length,0)) return 0;
    for(i=0;i<image->nt->FileHeader.NumberOfSections;i++) {
        unsigned start=sections[i].VirtualAddress,size=sections[i].Misc.VirtualSize;
        if(rva>=start && rva-start<=size && length<=size-(rva-start)
           && (sections[i].Characteristics&flags)==flags) return 1;
    }
    return 0;
}

static int report_check(const Runtime *r,const char *name,unsigned rva,int ok,const char *reason) {
    log_detail("CHECK candidate=\"%s\" check=%s rva=0x%08X result=%s reason=%s",
               r->name,name,rva,ok?"PASS":"FAIL",reason);
    return ok;
}
static void log_signature_bytes(const PauseImage *image,const Runtime *r,const char *name,unsigned rva,unsigned length) {
    char actual[129];unsigned i;
    if(length>64) length=64;
    if(!image_range(image,rva,length,IMAGE_SCN_MEM_EXECUTE)) {
        log_detail("DETAIL candidate=\"%s\" check=%s reason=outside_readable_executable_section",r->name,name);return;
    }
    for(i=0;i<length;i++) sprintf(actual+i*2,"%02X",image->base[rva+i]);
    log_detail("DETAIL candidate=\"%s\" check=%s actual_bytes=%s",r->name,name,actual);
}

static int hex_digit(char c) { return c>='0'&&c<='9'?c-'0':c-'a'+10; }
static int match_pattern(const unsigned char *bytes,const char *pattern) {
    unsigned i;
    for(i=0;pattern[i*2];i++) if(pattern[i*2]!='?' && bytes[i]!=(hex_digit(pattern[i*2])*16+hex_digit(pattern[i*2+1]))) return 0;
    return 1;
}

/* 特征描述的是指令结构，绝对重定位地址使用通配。Rep+ 来自本机 J460；
   Rep 来自 REPENTOGON 1.0.12 的 Console.zhl/Game.zhl，另以调用引用关系验证。 */
static const char *input_patterns[]={
    "558bec6aff68????????64a1000000005083ec3c535657a1????????33c5508d45f464a3000000008bf1",
    "558bec83ec3c535657"
};
static const char *render_patterns[]={
    "538bdc83ec0883e4f883c404558b6b04896c24048bec6aff68????????64a100000000505381ec78010000a1????????33c58945ec5657508d45f464a3000000008bf1897584",
    "558bec6aff68????????64a1????????5081ec9c000000a1????????33c58945??535657508d45??64a3????????8bf18975"
};

/* 证明同一条指令链由 game 全局指针得到 Console 对象，再调用输入入口。
   只允许 mov -> test/jcc/nop -> lea ecx -> call，中间不接受任意寄存器改写。
   Rep 的 Console::_state 在对象内 +0x20，Rep+ 为 +0。 */
static int has_console_reference(const PauseImage *image,const Runtime *r,int variant) {
    IMAGE_SECTION_HEADER *sections=IMAGE_FIRST_SECTION(image->nt); unsigned s;
    int constructor_found=0,console_call_found=0;
    unsigned object_offset=r->console_offset-(variant==1?0x20:0);
    for(s=0;s<image->nt->FileHeader.NumberOfSections;s++) {
        unsigned start=sections[s].VirtualAddress,size=sections[s].Misc.VirtualSize,i;
        if(!(sections[s].Characteristics&IMAGE_SCN_MEM_EXECUTE) || size<48
           || !image_range(image,start,size,IMAGE_SCN_MEM_EXECUTE)) continue;
        for(i=0;i+48<=size;i++) {
            unsigned char *p=image->base+start+i; unsigned reg,skip,position;
            /* 老 Rep 的 Game 单例构造赋值模式（Game.zhl g_Game）：
               call ctor; mov [ebp-4],-1; mov [g_Game],eax; call ...。
               配合 IsPaused 对 console_offset 的直接引用，不依赖 Rep+ 新增的输入调用点。 */
            if(variant==1 && match_pattern(p,"e8????????c745fcffffffffa3????????e8")
               && *(uintptr_t *)(p+13)==(uintptr_t)(image->base+r->game_ptr)) constructor_found=1;
            if(variant==1 && p[0]==0x8d && (p[1]&0xf8)==0x88 && (p[1]&7)!=4
               && *(unsigned *)(p+2)==object_offset && p[6]==0xe8
               && (unsigned)(start+i+11+*(int32_t *)(p+7))==r->input) console_call_found=1;
            if(p[0]==0xa1 && *(uint32_t *)(p+1)==(uintptr_t)(image->base+r->game_ptr)) {reg=0;skip=5;}
            else if(p[0]==0x8b && (p[1]&0xc7)==5 && *(uint32_t *)(p+2)==(uintptr_t)(image->base+r->game_ptr)) {reg=(p[1]>>3)&7;skip=6;}
            else continue;
            for(position=skip;position<32;) {
                hde32s instruction; unsigned length=hde32_disasm(p+position,&instruction);
                if(!length || instruction.flags&F_ERROR) break;
                if(p[position]==0x8d && p[position+1]==(0x88|reg)
                   && reg!=4 && *(uint32_t *)(p+position+2)==object_offset
                   && p[position+6]==0xe8
                   && (unsigned)(start+i+position+11+*(int32_t *)(p+position+7))==r->input) return 1;
                if(!(instruction.opcode==0x85 || instruction.opcode==0x90
                   || (instruction.opcode>=0x70 && instruction.opcode<=0x7f)
                   || (instruction.opcode==0x0f && instruction.opcode2>=0x80 && instruction.opcode2<=0x8f))) break;
                position+=length;
            }
        }
    }
    return variant==1 && constructor_found && console_call_found;
}

static int validate_candidate(const PauseImage *image,const Runtime *r,HMODULE lua,int extended,int variant) {
    int ok=1,pass; unsigned length;
    pass=image_range(image,r->paused,r->paused_length,IMAGE_SCN_MEM_EXECUTE)
         && !memcmp(image->base+r->paused,r->paused_bytes,r->paused_length);
    ok&=report_check(r,"paused",r->paused,pass,"entry_signature_and_executable_range");
    if(!pass) log_signature_bytes(image,r,"paused",r->paused,r->paused_length);
    if(!r->independent_pause) {
        length=extended?(unsigned)strlen(input_patterns[variant])/2:r->input_length;
        pass=image_range(image,r->input,length,IMAGE_SCN_MEM_EXECUTE)
            && (extended?match_pattern(image->base+r->input,input_patterns[variant]):!memcmp(image->base+r->input,r->input_bytes,length));
        ok&=report_check(r,"input",r->input,pass,extended?"extended_signature":"entry_signature");
        if(!pass) log_signature_bytes(image,r,"input",r->input,length);
        length=extended?(unsigned)strlen(render_patterns[variant])/2:r->render_length;
        pass=image_range(image,r->render,length,IMAGE_SCN_MEM_EXECUTE)
            && (extended?match_pattern(image->base+r->render,render_patterns[variant]):!memcmp(image->base+r->render,r->render_bytes,length));
        ok&=report_check(r,"render",r->render,pass,extended?"extended_signature":"entry_signature");
        if(!pass) log_signature_bytes(image,r,"render",r->render,length);
    }
    pass=image_range(image,r->game_ptr,sizeof(void *),IMAGE_SCN_MEM_WRITE);
    ok&=report_check(r,"game_ptr",r->game_ptr,pass,"writable_image_slot");
    pass=image_range(image,r->pcall_iat,sizeof(void *),IMAGE_SCN_MEM_READ)
         && lua && GetProcAddress(lua,"lua_pcallk")
         && *(void **)(image->base+r->pcall_iat)==(void *)GetProcAddress(lua,"lua_pcallk");
    ok&=report_check(r,"pcall_iat",r->pcall_iat,pass,"lua_pcallk_export_identity");
    if(extended) {
        pass=image_range(image,r->paused,17,IMAGE_SCN_MEM_EXECUTE)
             && (variant==0 ? (match_pattern(image->base+r->paused,"8bd1568b35????????83ba????????0074")
                               && *(uint32_t *)(image->base+r->paused+11)==r->console_offset)
                            : (match_pattern(image->base+r->paused,"83b9????????008b15")
                               && *(uint32_t *)(image->base+r->paused+2)==r->console_offset));
        ok&=report_check(r,"console_field",r->console_offset,pass,"paused_instruction_field_reference");
        pass=has_console_reference(image,r,variant);
        ok&=report_check(r,"game_console_reference",r->game_ptr,pass,variant==1?"game_constructor_or_console_call_reference":"game_pointer_to_console_input_call");
    }
    log_detail("CANDIDATE candidate=\"%s\" result=%s",r->name,ok?"PASS":"FAIL");
    return ok;
}

static const Runtime *select_runtime(const char *digest,unsigned char *address,HMODULE lua) {
    PauseImage image; unsigned i; int matches=0; const Runtime *selected=0;
    if(!inspect_image(address,&image)) {log_event("DISABLED invalid_PE_or_not_x86");return 0;}
    for(i=0;i<sizeof(runtimes)/sizeof(runtimes[0]);i++) if(digest && !strcmp(digest,runtimes[i].sha256)) {
        log_detail("KNOWN_HASH candidate=\"%s\"",runtimes[i].name);
        if(validate_candidate(&image,&runtimes[i],lua,0,0)) return &runtimes[i];
        log_event("DISABLED known_runtime_validation_failed");return 0;
    }
    log_event("UNKNOWN_HASH compatibility_probe");
    for(i=0;i<2;i++) if(validate_candidate(&image,&runtimes[i],lua,1,i)) {selected=&runtimes[i];matches++;}
    if(matches!=1) {log_event(matches?"DISABLED ambiguous_compatible_runtime":"DISABLED no_compatible_runtime");return 0;}
    log_detail("COMPATIBLE_UNKNOWN_HASH candidate=\"%s\"",selected->name);
    return selected;
}
