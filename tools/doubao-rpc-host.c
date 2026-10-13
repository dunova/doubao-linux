// ============================================================================
// doubao-rpc-host —— Wine 内的 Windows 宿主
//
// 作用：在 Wine 里加载官方 rpc.dll，用其 RPC 客户端把官方 ImeService 的
//       候选 / 上屏 / 组合文本能力，通过「标准输入输出行协议」暴露给 Linux 侧
//       的 bridge（bridge/rpc_broker.py），再由它转成 Unix domain socket 给
//       Fcitx5 插件用。
//
// 为什么是 stdin/stdout 而不是 Unix socket？
//   Wine 11.19 的 ws2_32 不支持 AF_UNIX（socket(AF_UNIX) 返回 WSAEAFNOSUPPORT
//   10047），所以宿主无法在 Wine 内直接起 Unix socket 服务端。已验证可行的链路
//   是「宿主读 stdin / 写 stdout + Linux 侧 broker 包一层 Unix socket」，这与
//   现有的键盘桥接（bridge/keyboard_host.c + bridge/keyboard_broker.py）完全一致。
//
// 调用约定（已对 rpc.dll 0.9.0.0 反汇编确认，2026-10-13 实测）：
//   RpcPipe_* 的第一个参数（rcx）被内部 helper（rpc.dll 0x180014390）当成
//   **管道/服务地址 C 字符串** 使用：helper 对 rcx 做 strlen + std::string::assign。
//   rcx==NULL 时 helper 建一个空默认串（走全局默认地址）。所以第一参数必须传
//   endpoint 字符串；**绝不能传 CreateRpcClient 返回的 client 指针**——那会被当成
//   字符串地址去 strlen，触发后台连接线程崩溃（gle=123 / exit 5）。
//   参考实现 bridge/keyboard_host.c（已知可用）同样只传 endpoint 字符串，且
//   **不调用 CreateRpcClient**。
//   必须用 RpcPipe_KeyDown/KeyUp（带 process_name），不能用 RpcPipe_KeyEvent
//   —— 后者缺 process_name 会触发 libprotobuf 的
//   'oime.KeyCode.process_name' invalid UTF-8 错误。
//
// 用法：wine doubao-rpc-host.exe
//   行协议（每行一条命令，回一行 JSON）：
//     F             -> FocusIn（注册输入上下文，隐藏官方 UI）
//     X             -> FocusOut
//     K <vk> <0|1>  -> KeyDown / KeyUp（vk 为 Windows 虚拟键码）
//     C             -> 取候选列表 JSON（数组 + 选中索引）
//     T             -> 取组合文本（preedit）JSON
//     M             -> 取上屏文本 JSON
//     Q             -> 退出
//   启动成功后先输出一行 {"ready":true}
// ============================================================================
#include <windows.h>

// ---- 函数指针类型（签名经 rpc.dll 0.9.0.0 反汇编确认）-----------------------
typedef void  (*ensure_t)(void);                     // RpcPipe_EnsureServerRunning()
typedef int  (*focus_t)(void *, const char *);       // RpcPipe_FocusIn(name)
typedef void (*focusout_t)(void *);                  // RpcPipe_FocusOut
typedef void (*show_t)(void *, int);                 // RpcPipe_SetUIElementShowState
typedef int  (*down_t)(void *, unsigned int, unsigned long long, const char *); // KeyDown(vk,ts,app)
typedef int  (*up_t)(void *, unsigned int);          // KeyUp(vk)
typedef int  (*comp_t)(void *, char *, int, int *);  // GetCompTextUtf8(buf,size,*cursor)
typedef int  (*commit_t)(void *, char *, int);       // GetCommitTextUtf8(buf,size)
typedef int  (*cands_t)(void *, char *, int, int *, int *, int *); // GetCandidateListUtf8

// ---- 全局 ----------------------------------------------------------------
static HANDLE input, output;
// 所有 RpcPipe_* 的第一个参数必须传 endpoint 字符串（见文件头 ABI 说明）。
// 不调用 CreateRpcClient：它返回的 client 指针若被用作第一参数会被当成地址字符串
// 去 strlen → 后台连接线程崩溃（实测 gle=123 / exit 5）。参考 keyboard_host.c。
static const char *endpoint = "\\\\.\\pipe\\ObricIme\\oime-server";
static char preedit[65536], candidates[65536], commit[65536], inline_commit[65536];
static char line[256];
static int cursor, selected, previous, next, cand_count;

static down_t   rpc_down;
static up_t     rpc_up;
static comp_t   rpc_comp;
static commit_t rpc_commit;
static cands_t  rpc_cands;
static commit_t rpc_inline;
static focusout_t rpc_focusout;
static show_t   rpc_show;
static focus_t  rpc_focus;

// 输出缓冲（一次响应一行 JSON，最长 ~256KB 足够）
// 直接 WriteFile 输出（与 keyboard_host.c 一致），不使用 obuf 缓冲，避免
// 非 null 结尾的候选/组合串导致 lstrlenA 越界写坏静态区。
static void jwrite(const char *s) { DWORD n; WriteFile(output, s, (DWORD)lstrlenA(s), &n, 0); }

// 转义输出一个 C 串，最多 max 字节（max = 缓冲区大小，防止越界读）。
static void jquoted(const char *s, int max) {
    jwrite("\"");
    for (int i = 0; i < max && s[i]; i++) {
        char b[8]; unsigned char c = (unsigned char)s[i];
        if (c == '\"' || c == '\\') { b[0] = '\\'; b[1] = c; b[2] = 0; jwrite(b); }
        else if (c == '\n') { jwrite("\\n"); }
        else if (c == '\r') { jwrite("\\r"); }
        else if (c == '\t') { jwrite("\\t"); }
        else if (c < 32) { wsprintfA(b, "\\u%04x", c); jwrite(b); }
        else { b[0] = (char)c; b[1] = 0; jwrite(b); }
    }
    jwrite("\"");
}

// 把候选缓冲区（换行分隔）输出成 JSON 数组，最多扫 max 字节。
static void jcands(const char *buf, int max) {
    jwrite("[");
    int first = 1;
    for (int i = 0; i < max && buf[i]; ) {
        int e = i;
        while (e < max && buf[e] && buf[e] != '\n') e++;
        int len = e - i;
        while (len > 0 && buf[i + len - 1] == '\r') len--;   // 去尾部 \r
        if (len > 0) {
            if (!first) jwrite(",");
            first = 0;
            jquoted(buf + i, len);
        }
        if (e >= max || !buf[e]) break;
        i = e + 1;
    }
    jwrite("]");
}

static unsigned parse(char **p) {
    unsigned v = 0;
    while (**p == ' ') (*p)++;
    while (**p >= '0' && **p <= '9') { v = v * 10 + **p - '0'; (*p)++; }
    return v;
}

static void snapshot(void) {
    preedit[0] = candidates[0] = commit[0] = inline_commit[0] = 0;
    cursor = selected = previous = next = 0;
    rpc_comp(endpoint, preedit, sizeof(preedit), &cursor);
    cand_count = rpc_cands(endpoint, candidates, sizeof(candidates), &selected, &previous, &next);
    rpc_commit(endpoint, commit, sizeof(commit));
    if (rpc_inline) rpc_inline(endpoint, inline_commit, sizeof(inline_commit));
}

static void report_full(int result) {
    char num[128];
    wsprintfA(num, "{\"result\":%d,\"cursor\":%d,\"selected\":%d,\"has_prev\":%d,\"has_next\":%d,\"preedit\":",
              result, cursor, selected, previous, next);
    jwrite(num);
    jquoted(preedit, (int)sizeof(preedit));
    jwrite(",\"candidates\":");
    jcands(candidates, (int)sizeof(candidates));
    jwrite(",\"commit\":");
    jquoted(commit, (int)sizeof(commit));
    jwrite(",\"inline_commit\":");
    jquoted(inline_commit, (int)sizeof(inline_commit));
    jwrite("}\n");
}

static void report_cands(void) {
    char num[128];
    jwrite("{\"candidates\":");
    jcands(candidates, (int)sizeof(candidates));
    wsprintfA(num, ",\"selected\":%d,\"has_prev\":%d,\"has_next\":%d}\n", selected, previous, next);
    jwrite(num);
}

static void report_preedit(void) {
    char num[128];
    jwrite("{\"preedit\":");
    jquoted(preedit, (int)sizeof(preedit));
    wsprintfA(num, ",\"cursor\":%d}\n", cursor);
    jwrite(num);
}

static void report_commit(void) {
    jwrite("{\"commit\":");
    jquoted(commit, (int)sizeof(commit));
    jwrite(",\"inline_commit\":");
    jquoted(inline_commit, (int)sizeof(inline_commit));
    jwrite("}\n");
}

static void report_simple(const char *json) { jwrite(json); jwrite("\n"); }

static void shutdown_host(void) {
    if (rpc_focusout) rpc_focusout(endpoint);
    ExitProcess(0);
}

void mainCRTStartup(void) {
    input = GetStdHandle(STD_INPUT_HANDLE);
    output = GetStdHandle(STD_OUTPUT_HANDLE);
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
    SetDllDirectoryW(L"C:\\DoubaoIme\\versions\\v0.9.0.0");

    HMODULE dll = LoadLibraryW(L"C:\\DoubaoIme\\versions\\v0.9.0.0\\rpc.dll");
    if (!dll) { report_simple("{\"error\":\"LoadLibrary rpc.dll failed\"}"); ExitProcess(2); }

#define LOAD(type, var, name) type var = (type)GetProcAddress(dll, name); if (!var) { report_simple("{\"error\":\"missing " name "\"}"); ExitProcess(3); }
    LOAD(ensure_t, ensure, "RpcPipe_EnsureServerRunning");
    LOAD(focus_t, f0, "RpcPipe_FocusIn");
    LOAD(focusout_t, fo0, "RpcPipe_FocusOut");
    LOAD(show_t, sh0, "RpcPipe_SetUIElementShowState");
    LOAD(down_t, dn0, "RpcPipe_KeyDown");
    LOAD(up_t, up0, "RpcPipe_KeyUp");
    LOAD(comp_t, cp0, "RpcPipe_GetCompTextUtf8");
    LOAD(commit_t, cm0, "RpcPipe_GetCommitTextUtf8");
    LOAD(cands_t, cd0, "RpcPipe_GetCandidateListUtf8");
#undef LOAD
    rpc_inline    = (commit_t)GetProcAddress(dll, "RpcPipe_GetInlineCommitTextUtf8");
    rpc_down      = dn0;
    rpc_up        = up0;
    rpc_comp      = cp0;
    rpc_commit    = cm0;
    rpc_cands     = cd0;
    rpc_focusout  = fo0;
    rpc_show      = sh0;
    rpc_focus     = f0;

    // 不调用 CreateRpcClient：参考 keyboard_host.c。RpcPipe_* 一律传 endpoint 字符串。
    ensure();
    for (int i = 0; i < 150; i++) { if (WaitNamedPipeA(endpoint, 100)) break; Sleep(100); }

    // 注册焦点并隐藏官方 UI，让 Fcitx 自己绘制候选窗
    rpc_focusout(endpoint);
    rpc_focus(endpoint, "fcitx5-doubao");
    rpc_show(endpoint, 0);
    rpc_down(endpoint, VK_ESCAPE, GetTickCount64() * 1000, "fcitx5-doubao.exe");
    snapshot();

    report_simple("{\"ready\":true}");

    for (;;) {
        DWORD n; int length = 0;
        while (length < 255) {
            if (!ReadFile(input, line + length, 1, &n, 0) || !n) { shutdown_host(); }
            if (line[length] == '\n') break;
            length++;
        }
        line[length] = 0;
        int result = 0;
        char *p = line + 1;
        char cmd = line[0];
        if (cmd == 'F') {
            rpc_down(endpoint, VK_ESCAPE, GetTickCount64() * 1000, "fcitx5-doubao.exe");
            rpc_focusout(endpoint);
            rpc_focus(endpoint, "fcitx5-doubao");
            rpc_show(endpoint, 0);
            snapshot();
            report_full(1);
        } else if (cmd == 'X') {
            rpc_focusout(endpoint);
            report_simple("{\"focus\":false}");
        } else if (cmd == 'K') {
            unsigned vk = parse(&p), release = parse(&p);
            result = release ? rpc_up(endpoint, vk)
                             : rpc_down(endpoint, vk, GetTickCount64() * 1000, "fcitx5-doubao.exe");
            snapshot();
            report_full(result);
        } else if (cmd == 'C') {
            cand_count = rpc_cands(endpoint, candidates, sizeof(candidates), &selected, &previous, &next);
            report_cands();
        } else if (cmd == 'T') {
            rpc_comp(endpoint, preedit, sizeof(preedit), &cursor);
            report_preedit();
        } else if (cmd == 'M') {
            rpc_commit(endpoint, commit, sizeof(commit));
            if (rpc_inline) rpc_inline(endpoint, inline_commit, sizeof(inline_commit));
            report_commit();
        } else if (cmd == 'Q') {
            shutdown_host();
        } else {
            report_simple("{\"error\":\"unknown command\"}");
        }
    }
}
