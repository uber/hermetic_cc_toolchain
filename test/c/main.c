#include <stdio.h>
#include <features.h>

int main() {
    #ifdef __GLIBC__
    printf("glibc_%d.%d", __GLIBC__, __GLIBC_MINOR__);
    #else
    puts("non-glibc");
    #endif
    return 0;
}
