#include <windows.h>
#include <mmsystem.h>
int main(int argc,char **argv) {
    if(argc!=2 || !LoadLibraryA(argv[1])) return 2;
    timeBeginPeriod(1);
    if(!timeGetTime()) return 3;
    Sleep(10000);
    timeEndPeriod(1);
    return 0;
}
