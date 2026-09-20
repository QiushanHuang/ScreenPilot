#include "DDCProtocol.h"
#include <assert.h>
#include <stdio.h>
static void checksum(uint8_t *b) { b[10]=0x50; for(int i=0;i<10;i++) b[10]^=b[i]; }
int main(void) {
 uint8_t reply[11]={0x6e,0x88,0x02,0,0x10,0,0,100,0,50,0}; checksum(reply);
 assert(validVCPReply(reply,11,0x10));
 assert(!validVCPReply(reply,5,0x10));
 assert(!validVCPReply(reply,11,0x60));
 reply[3]=1; checksum(reply); assert(!validVCPReply(reply,11,0x10));
 reply[3]=0; checksum(reply); reply[10]^=1; assert(!validVCPReply(reply,11,0x10));
 uint8_t empty[11]={0}; assert(!validVCPReply(empty,11,0x10));
 puts("DDC reply validation passed");
}
