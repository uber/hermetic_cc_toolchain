// Copyright 2023 Uber Technologies, Inc.
// Licensed under the Apache License, Version 2.0

#include <stdio.h>
#include <features.h>

int main() {
    #ifdef __GLIBC__
    printf("glibc_%d.%d\n", __GLIBC__, __GLIBC_MINOR__);
    #else
    printf("non-glibc\n");
    #endif
    return 0;
}
