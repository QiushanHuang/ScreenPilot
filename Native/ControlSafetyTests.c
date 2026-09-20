#include "ControlSafety.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    assert(powerControlBlocked(25001,10162));
    assert(!powerControlBlocked(25001,12289));
    assert(!powerControlBlocked(1507,10128));
    assert(canDisableDisplay(4,true,true));
    assert(!canDisableDisplay(1,true,true));
    assert(!canDisableDisplay(4,false,true));
    assert(!canDisableDisplay(4,true,false));
    assert(canRestoreCachedDisplay(true,false,true,false,false));
    assert(!canRestoreCachedDisplay(false,false,true,false,false));
    assert(!canRestoreCachedDisplay(true,false,false,false,false));
    assert(!canRestoreCachedDisplay(true,false,true,true,false));
    assert(!canRestoreCachedDisplay(true,false,true,false,true));
    assert(canRestoreCachedDisplay(true,true,false,true,true));
    puts("Power block and disconnect guards passed");
}
