// ============================================================================
// doubao-rpc-probe —— 探测官方 rpc.dll 的客户端 API 调用形态
//
// 目标（按顺序，每步独立可判）：
//   1. 哪些 RpcPipe_* 是可直接 GetProcAddress 的导出
//   2. CreateRpcClient(param) 用不同 param 的返回/崩溃情况
//   3. 若拿到 client，试调 RpcPipe_GetInputState / EnsureServerRunning
//
// 用法: doubao-rpc-probe <rpc.dll 路径> [mode]
//   mode 0 (默认) 只做第 1 步：枚举导出
//   mode 1        第 2 步：CreateRpcClient(NULL)
//   mode 2        第 2 步：CreateRpcClient(指向管道名 UTF-16 的指针)
//   mode 3        CreateRpcClient 后试调 RpcPipe_GetInputState(NULL)
//
// 注意：这是对私有 API 的探测，崩溃是预期结果之一。
// ============================================================================
#include <windows.h>
#include <stdio.h>
#include <string.h>

static const char *RPCPIPE_NAMES[] = {
    "RpcPipe_EnsureServerRunning", "RpcPipe_FocusIn", "RpcPipe_FocusOut",
    "RpcPipe_DeActivate", "RpcPipe_KeyEvent", "RpcPipe_KeyDown", "RpcPipe_KeyUp",
    "RpcPipe_GetInputState", "RpcPipe_GetCompTextUtf8", "RpcPipe_GetCandidateListUtf8",
    "RpcPipe_GetCommitTextUtf8", "RpcPipe_GetInlineCommitTextUtf8",
    "RpcPipe_SetCursorPos", "RpcPipe_SetUIElementShowState", "RpcPipe_ShowContextMenu",
    "RpcPipe_UpdateHostContextUtf8", "RpcPipe_AckVoiceCommit", "RpcPipe_PeekVoiceCommitUtf8",
    "RpcPipe_UploadModifyPair", "RpcPipe_RegisterTsfNotifySink",
    "RpcPipe_UnregisterTsfNotifySink", "RpcPipe_SimpleMessage", "RpcPipe_SimpleMessageEx",
    NULL
};

int main(int argc, char **argv) {
    if (argc < 2) { printf("usage: %s <rpc.dll> [mode]\n", argv[0]); return 2; }
    int mode = (argc > 2) ? atoi(argv[2]) : 0;

    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
    HMODULE h = LoadLibraryA(argv[1]);
    if (!h) { printf("LoadLibrary FAIL err=%lu\n", GetLastError()); return 1; }
    printf("LoadLibrary ok: %s\n", argv[1]);

    if (mode == 0) {
        printf("\n== 1) RpcPipe_* 是否可直接 GetProcAddress ==\n");
        int named = 0;
        for (int i = 0; RPCPIPE_NAMES[i]; i++) {
            FARPROC p = GetProcAddress(h, RPCPIPE_NAMES[i]);
            printf("  %-40s %s\n", RPCPIPE_NAMES[i], p ? "✔" : "·");
            if (p) named++;
        }
        printf("  → 可直接取到 %d / 23 个\n", named);
        printf("\n== 入口函数 ==\n");
        const char *entries[] = {"CreateRpcClient","DestroyRpcClient",NULL};
        for (int i = 0; entries[i]; i++) {
            FARPROC p = GetProcAddress(h, entries[i]);
            printf("  %-40s %s\n", entries[i], p ? "✔" : "✘");
        }
        return 0;
    }

    typedef void *(*mk_t)(void *);
    mk_t mk = (mk_t)GetProcAddress(h, "CreateRpcClient");
    if (!mk) { printf("GetProcAddress(CreateRpcClient) FAIL\n"); return 1; }

    if (mode == 1) {
        printf("\n== CreateRpcClient(NULL) ==\n");
        fflush(stdout);
        void *c = mk(NULL);
        printf("  返回 %p\n", c);
        return 0;
    }
    if (mode == 2) {
        // 管道名，UTF-16（模拟 LPCWSTR 形态）
        static const wchar_t pipe[] = L"\\\\.\\pipe\\ObricIme\\oime-server";
        printf("\n== CreateRpcClient(指向管道名宽字符串的指针) ==\n");
        printf("  pipe=%ls\n", pipe);
        fflush(stdout);
        void *c = mk((void *)pipe);
        printf("  返回 %p\n", c);
        return 0;
    }
    if (mode == 3) {
        printf("\n== CreateRpcClient(NULL) 后试调 RpcPipe_GetInputState ==\n");
        fflush(stdout);
        void *c = mk(NULL);
        printf("  client=%p\n", c);
        if (!c) return 0;
        typedef int (*fn0_t)(void *);
        fn0_t st = (fn0_t)GetProcAddress(h, "RpcPipe_GetInputState");
        printf("  GetInputState=%p\n", (void *)st);
        if (st) { fflush(stdout); int r = st(c); printf("  → 返回 %d\n", r); }
        return 0;
    }
    printf("未知 mode\n");
    return 2;
}
