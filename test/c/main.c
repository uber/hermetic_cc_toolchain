// Copyright 2023 Uber Technologies, Inc.
// Licensed under the MIT License

#include <stdio.h>
#if defined(_WIN64)
#define OS "windows"
#elif __APPLE__
#define OS "macos"
#elif __linux__
#define OS "linux"
#include <features.h>
#else
#   error "Unknown compiler!"
#endif

int main() {
    #ifdef __GLIBC__
    printf("%s glibc_%d.%d\n", OS, __GLIBC__, __GLIBC_MINOR__);
    #else
    printf("%s non-glibc\n", OS);
    #endif
    return 0;
}
