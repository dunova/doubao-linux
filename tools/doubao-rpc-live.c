// doubao-rpc-live —— 验证官方 RPC 真的能拿到数据
// 用法: doubao-rpc-live <rpc.dll> <mode>
//   mode 1  EnsureServerRunning(client)        判据：非 0 = RPC 活着
//   mode 2  FocusIn / KeyEvent / GetCandidateListUtf8
//   mode 3  GetCompTextUtf8 / GetCommitTextUtf8 到缓冲区
#include <windows.h>
#include <stdio.h>
#include <string.h>

typedef void *(*mk_t)(void *);
typedef int (*fn1_t)(void *);
typedef int (*fn3_t)(void *, char *, int);
typedef int (*fn2i_t)(void *, int);

int main(int argc, char **argv) {
    if (argc < 3) { printf("usage: %s <rpc.dll> <mode>\n", argv[0]); return 2; }
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
    HMODULE h = LoadLibraryA(argv[1]);
    if (!h) { printf("LoadLibrary FAIL %lu\n", GetLastError()); return 1; }
    int mode = atoi(argv[2]);

    mk_t mk = (mk_t)GetProcAddress(h, "CreateRpcClient");
    if (!mk) { printf("no CreateRpcClient\n"); return 1; }
    void *c = mk(NULL);
    printf("client=%p\n", c);
    if (!c) return 1;

    static char buf[65536];

    if (mode == 1) {
        fn1_t ensure = (fn1_t)GetProcAddress(h, "RpcPipe_EnsureServerRunning");
        fn1_t state  = (fn1_t)GetProcAddress(h, "RpcPipe_GetInputState");
        printf("EnsureServerRunning=%p GetInputState=%p\n", (void*)ensure, (void*)state);
        if (ensure) { fflush(stdout); int r = ensure(c); printf("  EnsureServerRunning -> %d\n", r); }
        if (state)  { fflush(stdout); int r = state(c);  printf("  GetInputState      -> %d\n", r); }
        return 0;
    }

    if (mode == 2) {
        fn1_t focus = (fn1_t)GetProcAddress(h, "RpcPipe_FocusIn");
        fn2i_t key  = (fn2i_t)GetProcAddress(h, "RpcPipe_KeyEvent");
        fn1_t cands = (fn1_t)GetProcAddress(h, "RpcPipe_GetCandidateListUtf8");
        printf("FocusIn=%p KeyEvent=%p GetCandidateListUtf8=%p\n",
               (void*)focus, (void*)key, (void*)cands);
        if (focus) { fflush(stdout); printf("  FocusIn -> %d\n", focus(c)); }
        // 试几种 KeyEvent 参数形态：VK 码
        const char *seq = "nihao";
        for (int i = 0; seq[i]; i++) {
            if (!key) break;
            int vk = toupper((unsigned char)seq[i]);
            fflush(stdout);
            int r = key(c, vk);
            printf("  KeyEvent('%c'=%d) -> %d\n", seq[i], vk, r);
        }
        if (cands) {
            memset(buf, 0, sizeof buf);
            fflush(stdout);
            int r = cands(c);
            printf("  GetCandidateListUtf8 -> %d\n", r);
        }
        // 也试带缓冲区的形态
        fn3_t cands3 = (fn3_t)cands;
        if (cands3) {
            memset(buf, 0, sizeof buf);
            fflush(stdout);
            int r = cands3(c, buf, sizeof buf);
            printf("  GetCandidateListUtf8(buf) -> %d, buf=[%.200s]\n", r, buf);
        }
        return 0;
    }

    if (mode == 3) {
        const char *names[] = {"RpcPipe_GetCompTextUtf8","RpcPipe_GetCommitTextUtf8",
                               "RpcPipe_GetInlineCommitTextUtf8","RpcPipe_GetInputState",NULL};
        for (int i = 0; names[i]; i++) {
            fn3_t f3 = (fn3_t)GetProcAddress(h, names[i]);
            if (!f3) { printf("  %-34s (无导出)\n", names[i]); continue; }
            memset(buf, 0, sizeof buf);
            fflush(stdout);
            int r = f3(c, buf, sizeof buf);
            printf("  %-34s -> %d  buf=[%.160s]\n", names[i], r, buf);
        }
        return 0;
    }
    printf("未知 mode\n");
    return 2;
}
