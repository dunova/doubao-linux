// 探测官方豆包 IME 的命名管道 RPC 通道是否可连
#include <windows.h>
#include <stdio.h>

static void try_open(const char *name) {
    HANDLE h = CreateFileA(name, GENERIC_READ | GENERIC_WRITE,
                           0, NULL, OPEN_EXISTING, 0, NULL);
    if (h == INVALID_HANDLE_VALUE) {
        printf("  FAIL  %-48s err=%lu\n", name, GetLastError());
        return;
    }
    printf("  OK    %-48s (可打开)\n", name);
    // 试着发一点探测字节（不一定被接受，只证明通道活着）
    DWORD wrote = 0;
    BOOL w = WriteFile(h, "PING\n", 5, &wrote, NULL);
    printf("        WriteFile -> %s wrote=%lu\n", w ? "ok" : "fail", wrote);
    CloseHandle(h);
}

int main(void) {
    printf("== 枚举命名管道 ==\n");
    WIN32_FIND_DATAA d;
    HANDLE f = FindFirstFileA("\\\\.\\pipe\\*", &d);
    if (f != INVALID_HANDLE_VALUE) {
        do {
            if (strstr(d.cFileName, "Obric") || strstr(d.cFileName, "oime") ||
                strstr(d.cFileName, "Doubao") || strstr(d.cFileName, "ime"))
                printf("  %s\n", d.cFileName);
        } while (FindNextFileA(f, &d));
        FindClose(f);
    } else {
        printf("  (FindFirstFile 失败 err=%lu)\n", GetLastError());
    }

    printf("\n== 直接尝试打开官方 RPC 通道 ==\n");
    try_open("\\\\.\\pipe\\ObricIme\\oime-server");
    try_open("\\\\.\\pipe\\ObricIme\\oime-server-tsf-log");
    return 0;
}
