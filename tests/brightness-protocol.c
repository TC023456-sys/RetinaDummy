#include "../BrightnessProtocol.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static void checksum(uint8_t *p) { p[10]=0x50; for(int i=0;i<10;i++)p[10]^=p[i]; }
int main(void) {
    uint8_t p[11]={0x6e,0x88,0x02,0,0x10,0,0,100,0,38,0}; checksum(p);
    uint16_t cur=0,max=0;
    assert(RetinaDecodeBrightness(p,11,&cur,&max) && cur==38 && max==100);
    assert(!RetinaDecodeBrightness(p,10,&cur,&max));
    p[3]=1;checksum(p);assert(!RetinaDecodeBrightness(p,11,&cur,&max));
    p[3]=0;p[4]=0x12;checksum(p);assert(!RetinaDecodeBrightness(p,11,&cur,&max));
    p[4]=0x10;p[7]=0;checksum(p);assert(!RetinaDecodeBrightness(p,11,&cur,&max));
    p[7]=100;p[9]=101;checksum(p);assert(!RetinaDecodeBrightness(p,11,&cur,&max));
    p[9]=38;checksum(p);p[10]^=1;assert(!RetinaDecodeBrightness(p,11,&cur,&max));
    memset(p,0,sizeof(p));assert(!RetinaDecodeBrightness(p,11,&cur,&max));
    assert(RetinaBrightnessValue(50,255)==128);
    assert(RetinaBrightnessValue(100,65535)==65535);
    assert(RetinaBrightnessValue(-5,100)==0 && RetinaBrightnessValue(110,100)==100);
    puts("PASS: valid DDC responses, unsupported/corrupt/empty replies, non-100 scaling and bounds");
}
