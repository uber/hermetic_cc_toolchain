// Copyright 2023 Uber Technologies, Inc.
// Licensed under the MIT License

#include <stdio.h>
#if defined(_WIN64)
#include <windows.h>
#define OS "windows"
#elif __APPLE__
#define OS "macos"
#elif __linux__
#include <features.h>
#define OS "linux"
#elif __wasi__
#include <features.h>
#define OS "wasi"
#else
#   error "Unknown compiler!"
#endif

int main() {
#if defined(_WIN64)
    DWORD version = GetVersion();
    DWORD majorVersion = (DWORD)(LOBYTE(LOWORD(version)));
    DWORD minorVersion = (DWORD)(HIBYTE(LOWORD(version)));

    DWORD build = 0;
    if (version < 0x80000000) {
        build = (DWORD)(HIWORD(version));
    }

    printf("%s %lu.%lu (%lu).\n", OS, majorVersion, minorVersion, build);
#elif defined __GLIBC__
    printf("%s glibc_%d.%d\n", OS, __GLIBC__, __GLIBC_MINOR__);
#else
    printf("%s non-glibc\n", OS);
#endif
    return 0;
}
