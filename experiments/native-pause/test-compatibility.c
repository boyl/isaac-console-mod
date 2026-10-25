/* 不启动游戏、不安装挂钩：独立映像夹具 + 真实磁盘 EXE 的重定位映像。 */
#define DllMain CompatibilityDllMain
#include "pause.c"
#undef DllMain
#include <stdlib.h>
static int checks;
static const char *unknown_hash="210CADE2A1DE98550CEF52D012174108189D1A0D3926A22C3A1EC12FB3AE4831";
static void check(int ok,const char *name) {
    if(!ok) {fprintf(stderr,"FAIL %s\n",name);exit(1);}
    printf("PASS %s\n",name);checks++;
}
static void bytes(unsigned char *at,const char *hex) {
    unsigned value;
    while(*hex) {sscanf(hex,"%2x",&value);*at++=(unsigned char)value;hex+=2;}
}
static unsigned char *fixture(void) {
    unsigned char *image=VirtualAlloc(0,0x900000,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    IMAGE_DOS_HEADER *dos=(void *)image; IMAGE_NT_HEADERS32 *nt=(void *)(image+0x80);
    IMAGE_SECTION_HEADER *s;
    dos->e_magic=IMAGE_DOS_SIGNATURE;dos->e_lfanew=0x80;
    nt->Signature=IMAGE_NT_SIGNATURE;nt->FileHeader.Machine=IMAGE_FILE_MACHINE_I386;
    nt->FileHeader.SizeOfOptionalHeader=sizeof(IMAGE_OPTIONAL_HEADER32);nt->FileHeader.NumberOfSections=2;
    nt->OptionalHeader.Magic=IMAGE_NT_OPTIONAL_HDR32_MAGIC;nt->OptionalHeader.SizeOfImage=0x900000;
    nt->OptionalHeader.SizeOfHeaders=0x1000;s=IMAGE_FIRST_SECTION(nt);
    s[0].VirtualAddress=0x1000;s[0].Misc.VirtualSize=0x5ff000;s[0].Characteristics=IMAGE_SCN_MEM_READ|IMAGE_SCN_MEM_EXECUTE;
    s[1].VirtualAddress=0x600000;s[1].Misc.VirtualSize=0x300000;s[1].Characteristics=IMAGE_SCN_MEM_READ|IMAGE_SCN_MEM_WRITE;
    return image;
}
static void populate(unsigned char *image,int rep,HMODULE lua) {
    unsigned input=rep?0x263550:0x28b260,game_slot=rep?0x7fd65c:0x871678;
    unsigned object_offset=rep?0x1bb60:0x68d78,iat=rep?0x60623c:0x7183d8;
    unsigned char *ref=image+(rep?0x2100:0x2000);
    if(rep) {
        bytes(image+0x2d0380,"83b980bb0100008b1500000000");
        bytes(image+0x263550,"558bec83ec3c5356578bf1");
        bytes(image+0x263d10,"558bec6aff680000000064a1000000005081ec9c000000a10000000033c58945ec535657508d45f464a3000000008bf18975fc");
    } else {
        bytes(image+0x2fd350,"8bd1568b359c16c70083ba788d060000741a8b8ed8b30400");
        bytes(image+0x28b260,"558bec6aff68dd8eaf0064a1000000005083ec3c535657a1b493bf0033c5508d45f464a3000000008bf1");
        bytes(image+0x28c2e0,"538bdc83ec0883e4f883c404558b6b04896c24048bec6aff68ae8faf0064a100000000505381ec78010000a1b493bf0033c58945ec5657508d45f464a3000000008bf1897584");
    }
    bytes(ref,"8b350000000085f6740b8d8e00000000e800000000");
    *(uintptr_t *)(ref+2)=(uintptr_t)(image+game_slot);
    *(unsigned *)(ref+12)=object_offset;
    *(int32_t *)(ref+17)=(int32_t)(image+input-(ref+21));
    *(void **)(image+iat)=(void *)GetProcAddress(lua,"lua_pcallk");
}
static unsigned char *map_exe(const char *path) {
    FILE *f=fopen(path,"rb"); long size; unsigned char *file,*image; unsigned i;
    IMAGE_DOS_HEADER *dos; IMAGE_NT_HEADERS32 *nt; IMAGE_SECTION_HEADER *s;
    IMAGE_DATA_DIRECTORY reloc; unsigned position=0; uintptr_t delta;
    if(!f) return 0;fseek(f,0,SEEK_END);size=ftell(f);rewind(f);file=malloc(size);
    if(fread(file,1,size,f)!=(size_t)size){fclose(f);free(file);return 0;}fclose(f);
    dos=(void *)file;nt=(void *)(file+dos->e_lfanew);s=IMAGE_FIRST_SECTION(nt);
    image=VirtualAlloc(0,nt->OptionalHeader.SizeOfImage,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    memcpy(image,file,nt->OptionalHeader.SizeOfHeaders);
    for(i=0;i<nt->FileHeader.NumberOfSections;i++) memcpy(image+s[i].VirtualAddress,file+s[i].PointerToRawData,s[i].SizeOfRawData);
    delta=(uintptr_t)image-nt->OptionalHeader.ImageBase;
    reloc=nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_BASERELOC];
    while(position<reloc.Size) {
        IMAGE_BASE_RELOCATION *block=(void *)(image+reloc.VirtualAddress+position);
        WORD *entries=(void *)(block+1); unsigned count;
        if(block->SizeOfBlock<sizeof(*block)) break;
        count=(block->SizeOfBlock-sizeof(*block))/2;
        for(i=0;i<count;i++) if((entries[i]>>12)==IMAGE_REL_BASED_HIGHLOW)
            *(uintptr_t *)(image+block->VirtualAddress+(entries[i]&0xfff))+=delta;
        position+=block->SizeOfBlock;
    }
    free(file);return image;
}
int main(int argc,char **argv) {
    HMODULE lua; unsigned char *image; int rep; const Runtime *selected;
    char logtext[65536];size_t logsize;
    if(argc!=3) {fprintf(stderr,"usage: compatibility-test Lua.dll official-RepPlus.exe\n");return 2;}
    lua=LoadLibraryA(argv[1]);check(lua!=0,"load real Lua exports");
    logfile=tmpfile();check(logfile!=0,"capture diagnostic log");
    for(rep=0;rep<2;rep++) {
        unsigned input=rep?0x263550:0x28b260,field=rep?0x2d0382:0x2fd35b;
        unsigned iat=rep?0x60623c:0x7183d8,reference=rep?0x2102:0x2002;
        image=fixture();populate(image,rep,lua);
        selected=select_runtime(unknown_hash,image,lua);
        check(selected && selected->input==input,rep?"unknown Rep selects compatible backend":"exact reported hash selects compatible Rep+ backend");
        image[0x900]=0x42;
        check(select_runtime("different-hash",image,lua)==selected,"unrelated bytes do not gate compatibility");
        image[input+2]^=1;check(!select_runtime(unknown_hash,image,lua),"input mismatch blocks before hooks");image[input+2]^=1;
        image[field]^=1;check(!select_runtime(unknown_hash,image,lua),"wrong console field is diagnosed");image[field]^=1;
        image[reference]^=4;check(!select_runtime(unknown_hash,image,lua),"wrong game global reference is diagnosed");image[reference]^=4;
        *(void **)(image+iat)=0;check(!select_runtime(unknown_hash,image,lua),"wrong Lua IAT is diagnosed");
        populate(image,rep,lua);
        check(select_runtime(selected->sha256,image,lua)==selected,"known hash preserves backend selection");
        base=image;runtime=selected;game_memory_status=-1;
        check(!game(),"game not created waits without dereferencing null");
        *(void **)(image+selected->game_ptr)=(void *)1;
        check(!game(),"invalid object memory fails without access violation");
        *(void **)(image+selected->game_ptr)=image+0x600000;
        check(game()==image+0x600000,"valid object state becomes ready");
        VirtualFree(image,0,MEM_RELEASE);
    }
    image=fixture();populate(image,0,lua);populate(image,1,lua);
    check(!select_runtime(unknown_hash,image,lua),"ambiguous candidates do not select arbitrarily");
    VirtualFree(image,0,MEM_RELEASE);
    image=fixture();populate(image,1,lua);
    memset(image+0x2100,0,48);
    bytes(image+0x3000,"e800000000c745fcffffffffa300000000e800000000");
    *(uintptr_t *)(image+0x300d)=(uintptr_t)(image+0x7fd65c);
    bytes(image+0x3100,"8d8f60bb0100e800000000");
    *(int32_t *)(image+0x3107)=0x263550-0x310b;
    selected=select_runtime(unknown_hash,image,lua);
    check(selected && selected->input==0x263550,"Rep singleton constructor reference supports older call layout");
    image[0x3102]^=4;
    check(!select_runtime(unknown_hash,image,lua),"Rep constructor alone cannot validate console input target");
    image[0x3102]^=4;
    image[0x300d]^=4;
    check(!select_runtime(unknown_hash,image,lua),"Rep wrong singleton assignment is rejected");
    VirtualFree(image,0,MEM_RELEASE);
    image=fixture();populate(image,0,lua);
    check(!select_runtime(unknown_hash,image,0),"missing Lua export provider is diagnosed");
    ((IMAGE_NT_HEADERS32 *)(image+0x80))->FileHeader.Machine=IMAGE_FILE_MACHINE_AMD64;
    check(!select_runtime(unknown_hash,image,lua),"wrong PE architecture is diagnosed");
    VirtualFree(image,0,MEM_RELEASE);
    image=fixture();
    bytes(image+0x2f92a0,"8bd1568b3500000000");
    *(void **)(image+0x6aa278)=(void *)GetProcAddress(lua,"lua_pcallk");
    selected=select_runtime("CEB598B4E5E03DABBD2DA6EA322A9AA6FFC66FCC377AEEA4391F008403B7FAA4",image,lua);
    check(selected && selected->independent_pause,"known REPENTOGON selection is preserved");
    check(!select_runtime(unknown_hash,image,lua),"unknown independent backend is not mistaken for Rep");
    VirtualFree(image,0,MEM_RELEASE);
    image=map_exe(argv[2]);check(image!=0,"map actual Rep+ EXE without execution");
    /* 模拟 Windows 加载器解析这个槽位；游戏代码和调用引用保持真实文件内容。 */
    *(void **)(image+0x7183d8)=(void *)GetProcAddress(lua,"lua_pcallk");
    selected=select_runtime(unknown_hash,image,lua);
    check(selected && selected->input==0x28b260,"actual relocated Rep+ image accepts unknown hash");
    image[0x40]^=1;
    check(select_runtime("modified-non-code",image,lua)==selected,"actual Rep+ unrelated modification remains compatible");
    image[0x28c2e0+8]^=1;
    check(!select_runtime(unknown_hash,image,lua),"actual Rep+ render change is diagnosed");
    VirtualFree(image,0,MEM_RELEASE);
    rewind(logfile);logsize=fread(logtext,1,sizeof(logtext)-1,logfile);logtext[logsize]=0;
    check(strstr(logtext,"UNKNOWN_HASH compatibility_probe") && strstr(logtext,"COMPATIBLE_UNKNOWN_HASH"),"unknown hash logs both probe and successful selection");
    check(strstr(logtext,"check=console_field") && strstr(logtext,"check=game_console_reference") && strstr(logtext,"check=pcall_iat"),"diagnostics identify failed dependency checks");
    check(strstr(logtext,"DISABLED ambiguous_compatible_runtime") && strstr(logtext,"DISABLED no_compatible_runtime"),"terminal reasons are observable");
    fclose(logfile);logfile=0;
    printf("COMPATIBILITY_PASS assertions=%d synthetic=Rep,Rep+ actual=Rep+ no_game_execution\n",checks);return 0;
}
