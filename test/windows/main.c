// Copyright 2023 Uber Technologies, Inc.
// Licensed under the MIT License

#include <stdio.h>
#include <windows.h>

int main() {
    DWORD version = GetVersion();
    DWORD majorVersion = (DWORD)(LOBYTE(LOWORD(version)));
    DWORD minorVersion = (DWORD)(HIBYTE(LOWORD(version)));

    DWORD build = 0;
    if (version < 0x80000000) {
        build = (DWORD)(HIWORD(version));
    }

    printf("Running Windows version %d.%d (%d).\n", majorVersion, minorVersion, build);
    return 0;
}
