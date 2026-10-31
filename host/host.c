// SR5 Tweak Menu host - runs the SR Tweak Menu's Lua inside Saints Row (2022).
//
// Built as dinput8.dll: SaintsRow_DX12.exe imports one function from it
// (DirectInput8Create), so Windows loads this file from the game folder and
// we pass that call on to the real dinput8.dll in System32.
//
// Our Lua 5.4 (the menu) runs once per iteration of the game's main loop,
// on the main thread (see "the frame hook"). Saints Row (2022) has one Lua
// 5.1 state (its UI, "vint", and the UI's gameplay functions such as
// cheat_activate), used on that same thread: wml.game(code) runs code in it.
//
// The Lua side sees a `wml` table, the same shape as the SR1 menu's host:
// log, setting, mod_folder, read_u8/u16/u32/u64/f32,
// write_..., key_down, key_pressed, on_frame; and for SR5: game(code),
// call(addr, ...), base (the exe's load address), buffer, read_string,
// pad, f2u/u2f.
//
// Addresses are RVAs in SaintsRow_DX12.exe of 2023-08-31 (the Epic build).

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <ctype.h>
#include <share.h>
#include <stdint.h>
#include <string.h>
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

// ------------------------------------------------------------------ SR5 facts
#define RVA_FRAME_FN    0x1B4A320   // called with 0, 1, 2 every main-loop iteration (main thread)
#define RVA_LUA_PCALL   0x12BFE00   // lua_pcall(L, nargs, nresults, errfunc)
#define RVA_LUA_LOAD    0x12BFF60   // lua_load(L, reader, data, chunkname)
#define RVA_LUA_STATE   0x5BED438   // lua_State* of the game's (only) state
// lua_State: top +0x10, base +0x18, stack +0x40. TValue: 16 bytes, value at
// +0, type (int) at +8; numbers are doubles. TString: length at +0x10, text
// at +0x18.
#define LS_TOP     0x10
#define LS_STACK   0x40

// ------------------------------------------------------------------ state
static char g_game_dir[MAX_PATH], g_root[MAX_PATH], g_mod_folder[MAX_PATH], g_ini[MAX_PATH], g_log_path[MAX_PATH];
static FILE *g_log;
static lua_State *L;
static int g_lua_failed;
static uint8_t *g_base;
static CRITICAL_SECTION g_lock;
static uint8_t g_key_now[256], g_key_prev[256];
static volatile LONG g_guarded;   // >0 while the host runs a guarded read, write or call (see the crash logger)

// ------------------------------------------------------------------ log
static void hlog(const char *fmt, ...)
{
    if (!g_log) return;
    SYSTEMTIME t; GetLocalTime(&t);
    fprintf(g_log, "[%02d:%02d:%02d.%03d] ", t.wHour, t.wMinute, t.wSecond, t.wMilliseconds);
    va_list ap; va_start(ap, fmt); vfprintf(g_log, fmt, ap); va_end(ap);
    fputc('\n', g_log);
    fflush(g_log);
}

// ------------------------------------------------------------------ memory
// A bad address becomes a Lua error instead of a crash.
static int mem_read(uint64_t a, void *out, size_t n)
{
    int ok = 1;
    g_guarded++;
    __try { memcpy(out, (void *)(uintptr_t)a, n); }
    __except (EXCEPTION_EXECUTE_HANDLER) { ok = 0; }
    g_guarded--;
    return ok;
}
static int mem_write(uint64_t a, const void *in, size_t n)
{
    int ok = 1;
    g_guarded++;
    __try { memcpy((void *)(uintptr_t)a, in, n); }
    __except (EXCEPTION_EXECUTE_HANDLER) { ok = 0; }
    g_guarded--;
    return ok;
}
static uint64_t check_addr(lua_State *s, int i) { return (uint64_t)luaL_checkinteger(s, i); }

static int l_read(lua_State *s, int n)
{
    uint64_t a = check_addr(s, 1), v = 0;
    if (!mem_read(a, &v, n)) return luaL_error(s, "bad read at %p", (void *)a);
    lua_pushinteger(s, (lua_Integer)v);
    return 1;
}
static int l_read_u8(lua_State *s)  { return l_read(s, 1); }
static int l_read_u16(lua_State *s) { return l_read(s, 2); }
static int l_read_u32(lua_State *s) { return l_read(s, 4); }
static int l_read_u64(lua_State *s) { return l_read(s, 8); }
static int l_read_f32(lua_State *s)
{
    uint64_t a = check_addr(s, 1); float f;
    if (!mem_read(a, &f, 4)) return luaL_error(s, "bad read at %p", (void *)a);
    lua_pushnumber(s, f);
    return 1;
}
static int l_read_f64(lua_State *s)
{
    uint64_t a = check_addr(s, 1); double d;
    if (!mem_read(a, &d, 8)) return luaL_error(s, "bad read at %p", (void *)a);
    lua_pushnumber(s, d);
    return 1;
}
static int l_write(lua_State *s, int n)
{
    uint64_t a = check_addr(s, 1), v = (uint64_t)luaL_checkinteger(s, 2);
    if (!mem_write(a, &v, n)) return luaL_error(s, "bad write at %p", (void *)a);
    return 0;
}
static int l_write_u8(lua_State *s)  { return l_write(s, 1); }
static int l_write_u16(lua_State *s) { return l_write(s, 2); }
static int l_write_u32(lua_State *s) { return l_write(s, 4); }
static int l_write_u64(lua_State *s) { return l_write(s, 8); }
static int l_write_f32(lua_State *s)
{
    uint64_t a = check_addr(s, 1); float f = (float)luaL_checknumber(s, 2);
    if (!mem_write(a, &f, 4)) return luaL_error(s, "bad write at %p", (void *)a);
    return 0;
}
static int l_f2u(lua_State *s) { float f = (float)luaL_checknumber(s, 1); uint32_t u; memcpy(&u, &f, 4); lua_pushinteger(s, u); return 1; }
static int l_u2f(lua_State *s) { uint32_t u = (uint32_t)luaL_checkinteger(s, 1); float f; memcpy(&f, &u, 4); lua_pushnumber(s, f); return 1; }

// read_string(addr [, max])
static int l_read_string(lua_State *s)
{
    uint64_t a = check_addr(s, 1);
    lua_Integer max = luaL_optinteger(s, 2, 256);
    char buf[4096];
    if (max > (lua_Integer)sizeof buf - 1) max = sizeof buf - 1;
    int n = 0;
    for (; n < max; n++) { if (!mem_read(a + n, &buf[n], 1)) return luaL_error(s, "bad read at %p", (void *)(a + n)); if (!buf[n]) break; }
    lua_pushlstring(s, buf, n);
    return 1;
}
// buffer(slot [, text]): the address of a 4 KB scratch buffer (slots 0-15).
static char g_buffers[16][4096];
static int l_buffer(lua_State *s)
{
    lua_Integer slot = luaL_checkinteger(s, 1);
    if (slot < 0 || slot > 15) return luaL_error(s, "buffer: slot 0-15");
    if (!lua_isnoneornil(s, 2)) {
        size_t n; const char *t = luaL_checklstring(s, 2, &n);
        if (n > sizeof g_buffers[0] - 1) n = sizeof g_buffers[0] - 1;
        memcpy(g_buffers[slot], t, n); g_buffers[slot][n] = 0;
    }
    lua_pushinteger(s, (lua_Integer)(uintptr_t)g_buffers[slot]);
    return 1;
}

// ------------------------------------------------------------------ game functions
// call(addr, ...): a game function with up to 8 integer/pointer arguments
// (x64: rcx, rdx, r8, r9, then the stack; extra ones are harmless). Returns rax.
typedef uint64_t (*fn8_t)(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t);
static int call_guarded(uint64_t fn, const uint64_t *a, uint64_t *out)
{
    int ok = 1;
    g_guarded++;
    __try { *out = ((fn8_t)(uintptr_t)fn)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7]); }
    __except (EXCEPTION_EXECUTE_HANDLER) { ok = 0; }
    g_guarded--;
    return ok;
}
static int l_call(lua_State *s)
{
    uint64_t fn = check_addr(s, 1), a[8] = { 0 }, r;
    int n = lua_gettop(s) - 1;
    if (n > 8) return luaL_error(s, "call: at most 8 arguments");
    for (int i = 0; i < n; i++) a[i] = (uint64_t)luaL_checkinteger(s, i + 2);
    if (!call_guarded(fn, a, &r)) return luaL_error(s, "call %p crashed", (void *)fn);
    lua_pushinteger(s, (lua_Integer)r);
    return 1;
}

// wml.callf(addr, ...): as wml.call, and a Lua float (a number with a decimal
// point) is passed as a C float: in the Windows x64 convention each of the
// first four arguments goes in its integer or its float register by position,
// so there's one prototype per mix; later arguments are stack slots, the
// float's bits in the low half.
typedef uint64_t U64;
#define CALLF4(T0, A0, T1, A1, T2, A2, T3, A3) \
    (((U64 (*)(T0, T1, T2, T3, U64, U64, U64, U64))(uintptr_t)fn)(A0, A1, A2, A3, a[4], a[5], a[6], a[7]))
static int callf_guarded(uint64_t fn, const uint64_t *a, const float *f, int mask, uint64_t *out)
{
    int ok = 1;
    g_guarded++;
    __try {
        switch (mask) {
        case 0:  *out = CALLF4(U64, a[0],  U64, a[1],  U64, a[2],  U64, a[3]);  break;
        case 1:  *out = CALLF4(float, f[0], U64, a[1],  U64, a[2],  U64, a[3]);  break;
        case 2:  *out = CALLF4(U64, a[0],  float, f[1], U64, a[2],  U64, a[3]);  break;
        case 3:  *out = CALLF4(float, f[0], float, f[1], U64, a[2],  U64, a[3]);  break;
        case 4:  *out = CALLF4(U64, a[0],  U64, a[1],  float, f[2], U64, a[3]);  break;
        case 5:  *out = CALLF4(float, f[0], U64, a[1],  float, f[2], U64, a[3]);  break;
        case 6:  *out = CALLF4(U64, a[0],  float, f[1], float, f[2], U64, a[3]);  break;
        case 7:  *out = CALLF4(float, f[0], float, f[1], float, f[2], U64, a[3]);  break;
        case 8:  *out = CALLF4(U64, a[0],  U64, a[1],  U64, a[2],  float, f[3]); break;
        case 9:  *out = CALLF4(float, f[0], U64, a[1],  U64, a[2],  float, f[3]); break;
        case 10: *out = CALLF4(U64, a[0],  float, f[1], U64, a[2],  float, f[3]); break;
        case 11: *out = CALLF4(float, f[0], float, f[1], U64, a[2],  float, f[3]); break;
        case 12: *out = CALLF4(U64, a[0],  U64, a[1],  float, f[2], float, f[3]); break;
        case 13: *out = CALLF4(float, f[0], U64, a[1],  float, f[2], float, f[3]); break;
        case 14: *out = CALLF4(U64, a[0],  float, f[1], float, f[2], float, f[3]); break;
        default: *out = CALLF4(float, f[0], float, f[1], float, f[2], float, f[3]); break;
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) { ok = 0; }
    g_guarded--;
    return ok;
}
static int l_callf(lua_State *s)
{
    uint64_t fn = check_addr(s, 1), a[8] = { 0 }, r;
    float f[4] = { 0 };
    int n = lua_gettop(s) - 1, mask = 0;
    if (n > 8) return luaL_error(s, "callf: at most 8 arguments");
    for (int i = 0; i < n; i++) {
        if (lua_isinteger(s, i + 2)) { a[i] = (uint64_t)lua_tointeger(s, i + 2); continue; }
        float v = (float)luaL_checknumber(s, i + 2);
        if (i < 4) { f[i] = v; mask |= 1 << i; }
        else memcpy(&a[i], &v, sizeof v);
    }
    if (!callf_guarded(fn, a, f, mask, &r)) return luaL_error(s, "callf %p crashed", (void *)fn);
    lua_pushinteger(s, (lua_Integer)r);
    return 1;
}

// ------------------------------------------------------------------ the game's Lua
typedef int (*lua_load_t)(void *L, const char *(*reader)(void *, void *, size_t *), void *data, const char *chunk);
typedef int (*lua_pcall_t)(void *L, int nargs, int nresults, int errfunc);
typedef struct { const char *s; size_t n; } reader_t;
static const char *code_reader(void *state, void *ud, size_t *size)
{
    (void)state;
    reader_t *r = (reader_t *)ud;
    if (!r->n) { *size = 0; return NULL; }
    *size = r->n; r->n = 0;
    return r->s;
}
static void *game_state(void) { return *(void **)(g_base + RVA_LUA_STATE); }

// Pushes one game TValue onto our stack as the closest Lua 5.4 value.
static void push_game_value(lua_State *s, const uint8_t *tv)
{
    int type = *(const int *)(tv + 8);
    uint64_t v = *(const uint64_t *)tv;
    switch (type) {
    case 0: lua_pushnil(s); break;
    case 1: lua_pushboolean(s, *(const int *)tv != 0); break;
    case 3: {
        double d = *(const double *)tv;
        if (d == (double)(lua_Integer)d && d > -9e15 && d < 9e15) lua_pushinteger(s, (lua_Integer)d); else lua_pushnumber(s, d);
        break;
    }
    case 4: {
        const uint8_t *ts = (const uint8_t *)(uintptr_t)v;
        uint64_t len = 0;
        if (!mem_read((uint64_t)(uintptr_t)(ts + 0x10), &len, 8) || len > (1u << 24)) { lua_pushstring(s, "<bad string>"); break; }
        char *tmp = (char *)malloc((size_t)len + 1);
        if (tmp && mem_read((uint64_t)(uintptr_t)(ts + 0x18), tmp, (size_t)len)) lua_pushlstring(s, tmp, (size_t)len);
        else lua_pushstring(s, "<bad string>");
        free(tmp);
        break;
    }
    default: lua_pushfstring(s, "<game type %d: %p>", type, (void *)(uintptr_t)v); break;
    }
}

// game(code): runs code in the game's Lua 5.1 state (as a chunk: use
// `return ...` to get values back). Returns true and the chunk's results,
// or false and the error message.
static int l_game(lua_State *s)
{
    size_t n; const char *code = luaL_checklstring(s, 1, &n);
    uint8_t *gs = (uint8_t *)game_state();
    if (!gs) { lua_pushboolean(s, 0); lua_pushstring(s, "no game Lua state yet"); return 2; }
    // The game's stack can be reallocated (moved) while the code runs, so the
    // old top is kept as an offset from the stack's start, not a pointer.
    uint8_t **top = (uint8_t **)(gs + LS_TOP), **stack = (uint8_t **)(gs + LS_STACK);
    ptrdiff_t top0 = *top - *stack;
    reader_t rd = { code, n };
    int status = -1, crashed = 0;
    g_guarded++;
    __try {
        status = ((lua_load_t)(g_base + RVA_LUA_LOAD))(gs, code_reader, &rd, "=tweak");
        if (status == 0) status = ((lua_pcall_t)(g_base + RVA_LUA_PCALL))(gs, 0, -1 /* LUA_MULTRET */, 0);
    } __except (EXCEPTION_EXECUTE_HANDLER) { crashed = 1; }
    g_guarded--;
    if (crashed) {
        *top = *stack + top0;
        hlog("game Lua crashed running: %.300s", code);
        lua_pushboolean(s, 0); lua_pushstring(s, "crashed");
        return 2;
    }
    uint8_t *first = *stack + top0;
    int results = (int)((*top - first) / 16);
    if (status != 0) {
        lua_pushboolean(s, 0);
        if (results > 0) push_game_value(s, *top - 16); else lua_pushfstring(s, "status %d", status);
        *top = first;
        return 2;
    }
    luaL_checkstack(s, results + 1, "too many results");
    lua_pushboolean(s, 1);
    for (int i = 0; i < results; i++) push_game_value(s, first + i * 16);
    *top = first;
    return 1 + results;
}

// ------------------------------------------------------------------ keys and pad
typedef struct { const char *name; uint8_t vk; } key_t;
static const key_t KEYS[] = {
    { "UP", VK_UP }, { "DOWN", VK_DOWN }, { "LEFT", VK_LEFT }, { "RIGHT", VK_RIGHT },
    { "ENTER", VK_RETURN }, { "RETURN", VK_RETURN }, { "BACKSPACE", VK_BACK },
    { "PAGEUP", VK_PRIOR }, { "PAGEDOWN", VK_NEXT }, { "HOME", VK_HOME }, { "END", VK_END },
    { "INSERT", VK_INSERT }, { "DELETE", VK_DELETE }, { "ESCAPE", VK_ESCAPE }, { "ESC", VK_ESCAPE },
    { "SHIFT", VK_SHIFT }, { "CTRL", VK_CONTROL }, { "CONTROL", VK_CONTROL }, { "ALT", VK_MENU },
    { "SPACE", VK_SPACE }, { "TAB", VK_TAB },
};
static int key_lookup(lua_State *s, int i, uint8_t *vk)
{
    if (lua_type(s, i) == LUA_TNUMBER) { *vk = (uint8_t)lua_tointeger(s, i); return 1; }
    char name[32]; const char *in = luaL_checkstring(s, i);
    size_t n = 0;
    for (; in[n] && n < sizeof name - 1; n++) name[n] = (char)toupper((unsigned char)in[n]);
    name[n] = 0;
    for (int k = 0; k < (int)(sizeof KEYS / sizeof *KEYS); k++)
        if (!strcmp(name, KEYS[k].name)) { *vk = KEYS[k].vk; return 1; }
    if (name[0] == 'F' && name[1] >= '1' && name[1] <= '9') {
        int f = atoi(name + 1);
        if (f >= 1 && f <= 24) { *vk = (uint8_t)(VK_F1 + f - 1); return 1; }
    }
    if (n == 1 && ((name[0] >= 'A' && name[0] <= 'Z') || (name[0] >= '0' && name[0] <= '9'))) { *vk = (uint8_t)name[0]; return 1; }
    return 0;
}
static int game_focused(void)
{
    DWORD pid = 0;
    GetWindowThreadProcessId(GetForegroundWindow(), &pid);
    return pid == GetCurrentProcessId();
}
static void poll_keys(void)
{
    memcpy(g_key_prev, g_key_now, sizeof g_key_now);
    int focus = game_focused();
    for (int vk = 1; vk < 256; vk++) g_key_now[vk] = focus && (GetAsyncKeyState(vk) & 0x8000) ? 1 : 0;
}
static int l_key_down(lua_State *s) { uint8_t vk; lua_pushboolean(s, key_lookup(s, 1, &vk) && g_key_now[vk]); return 1; }
static int l_key_pressed(lua_State *s) { uint8_t vk; lua_pushboolean(s, key_lookup(s, 1, &vk) && g_key_now[vk] && !g_key_prev[vk]); return 1; }
static int l_noop(lua_State *s) { (void)s; return 0; }

typedef struct { DWORD packet; WORD buttons; BYTE lt, rt; SHORT lx, ly, rx, ry; } xstate_t;
typedef DWORD (WINAPI *xget_t)(DWORD, xstate_t *);

// ------------------------------------------------------------------ keeping input from the game
// While the menu is open it takes its keys and the controller's buttons:
// the game's own imports are wrapped (raw input and window messages for the
// keyboard, XInputGetState for the pad). The menu reads input on its own
// (GetAsyncKeyState, its own XInput), so it isn't affected.
static volatile uint8_t g_block_vk[256];
static volatile int g_block_pad;
static volatile int g_pad_mask;            // buttons kept from the game
static volatile int g_pad_no_triggers;     // and its triggers
static volatile int g_pad_no_lstick;       // and its left stick

typedef UINT (WINAPI *raw_data_t)(HRAWINPUT, UINT, LPVOID, PUINT, UINT);
typedef BOOL (WINAPI *peek_t)(LPMSG, HWND, UINT, UINT, UINT);
static raw_data_t g_raw_data;
static peek_t g_peek;
static xget_t g_game_xget;

// Auto fire: while the fire button is held, the game sees it pressed and let
// go over and over, so single-shot guns keep firing. The mouse's left button
// is pulsed with SendInput; our own events reach raw input with no device
// (hDevice 0), so the real button's state is tracked from the others. The
// pad's right trigger is pulsed in the game's XInputGetState.
static volatile int g_autofire, g_autofire_ms = 60;
static volatile int g_phys_lmb;            // the real left button, from raw input
static int g_sent_up;                      // we've sent a "left up" the real button hasn't

static UINT WINAPI my_raw_data(HRAWINPUT h, UINT cmd, LPVOID data, PUINT size, UINT header)
{
    UINT r = g_raw_data(h, cmd, data, size, header);
    if (cmd == RID_INPUT && data && r != (UINT)-1 && r >= sizeof(RAWINPUTHEADER) + sizeof(RAWKEYBOARD)) {
        RAWINPUT *ri = (RAWINPUT *)data;
        if (ri->header.dwType == RIM_TYPEKEYBOARD && ri->data.keyboard.VKey < 256 && g_block_vk[ri->data.keyboard.VKey]) {
            ri->data.keyboard.VKey = 0xFF;      // "no key"
            ri->data.keyboard.MakeCode = 0;
        }
        if (ri->header.dwType == RIM_TYPEMOUSE && ri->header.hDevice && r >= sizeof(RAWINPUTHEADER) + sizeof(RAWMOUSE)) {
            USHORT f = ri->data.mouse.usButtonFlags;
            if (f & RI_MOUSE_LEFT_BUTTON_DOWN) g_phys_lmb = 1;
            if (f & RI_MOUSE_LEFT_BUTTON_UP) g_phys_lmb = 0;
        }
    }
    return r;
}

static int autofire_phase(void)
{
    int ms = g_autofire_ms > 10 ? g_autofire_ms : 10;
    return (int)((GetTickCount64() / (ULONGLONG)ms) & 1);   // 1: "released" half
}
static void send_left(int down)
{
    INPUT in = { 0 };
    in.type = INPUT_MOUSE;
    in.mi.dwFlags = down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP;
    SendInput(1, &in, sizeof in);
}
// Called every frame on the main thread.
static int game_focused(void);
static void autofire_tick(void)
{
    int want_up = g_autofire && g_phys_lmb && !g_block_pad && game_focused() && autofire_phase();
    if (want_up && !g_sent_up) { send_left(0); g_sent_up = 1; }
    else if (!want_up && g_sent_up) {
        if (g_phys_lmb) send_left(1);    // still held: press again
        g_sent_up = 0;
    }
}
static BOOL WINAPI my_peek(LPMSG msg, HWND wnd, UINT min, UINT max, UINT remove)
{
    BOOL r = g_peek(msg, wnd, min, max, remove);
    if (r && msg && (msg->message == WM_KEYDOWN || msg->message == WM_KEYUP || msg->message == WM_CHAR) &&
        msg->wParam < 256 && g_block_vk[msg->wParam])
        msg->message = WM_NULL;
    return r;
}
static DWORD WINAPI my_game_xget(DWORD user, xstate_t *st)
{
    DWORD r = g_game_xget(user, st);
    if (r == 0 && st && g_block_pad) st->buttons = 0;   // the sticks and triggers still reach the game
    if (r == 0 && st) st->buttons &= (WORD)~g_pad_mask;
    if (r == 0 && st && g_pad_no_triggers) st->lt = st->rt = 0;
    if (r == 0 && st && g_pad_no_lstick) st->lx = st->ly = 0;
    if (r == 0 && st && g_autofire && !g_block_pad && st->rt > 30 && autofire_phase()) st->rt = 0;
    return r;
}

// auto_fire(on [, ms]): pulse the fire button while it's held (ms per half-pulse).
static void rearm_crash_logger(void);
static int l_auto_fire(lua_State *s)
{
    g_autofire = lua_toboolean(s, 1);
    if (!lua_isnoneornil(s, 2)) g_autofire_ms = (int)luaL_checkinteger(s, 2);
    return 0;
}

// Points one of the exe's imports (dll, function) at `to`; returns the old target.
static void *hook_import(const char *dll, const char *fn, void *to)
{
    IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)g_base;
    IMAGE_NT_HEADERS64 *nt = (IMAGE_NT_HEADERS64 *)(g_base + dos->e_lfanew);
    IMAGE_DATA_DIRECTORY dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    for (IMAGE_IMPORT_DESCRIPTOR *d = (IMAGE_IMPORT_DESCRIPTOR *)(g_base + dir.VirtualAddress); d->Name; d++) {
        if (_stricmp((char *)(g_base + d->Name), dll)) continue;
        IMAGE_THUNK_DATA64 *names = (IMAGE_THUNK_DATA64 *)(g_base + (d->OriginalFirstThunk ? d->OriginalFirstThunk : d->FirstThunk));
        IMAGE_THUNK_DATA64 *iat = (IMAGE_THUNK_DATA64 *)(g_base + d->FirstThunk);
        for (; names->u1.AddressOfData; names++, iat++) {
            if (IMAGE_SNAP_BY_ORDINAL64(names->u1.Ordinal)) continue;
            IMAGE_IMPORT_BY_NAME *ibn = (IMAGE_IMPORT_BY_NAME *)(g_base + names->u1.AddressOfData);
            if (strcmp((char *)ibn->Name, fn)) continue;
            DWORD old;
            void *prev = (void *)iat->u1.Function;
            if (!VirtualProtect(&iat->u1.Function, 8, PAGE_READWRITE, &old)) return NULL;
            iat->u1.Function = (ULONGLONG)(uintptr_t)to;
            VirtualProtect(&iat->u1.Function, 8, old, &old);
            hlog("wrapped the game's %s!%s", dll, fn);
            return prev;
        }
    }
    hlog("the game doesn't import %s!%s", dll, fn);
    return NULL;
}

static void install_input_hooks(void)
{
    g_raw_data = (raw_data_t)hook_import("USER32.dll", "GetRawInputData", (void *)my_raw_data);
    g_peek = (peek_t)hook_import("USER32.dll", "PeekMessageA", (void *)my_peek);
    g_game_xget = (xget_t)hook_import("XINPUT9_1_0.dll", "XInputGetState", (void *)my_game_xget);
}

// block_input(keys_on, pad_on [, key names...]): while keys_on, the listed
// keys (default: the menu's own keys) don't reach the game; while pad_on,
// the controller's buttons don't.
static int l_block_input(lua_State *s)
{
    int keys = lua_toboolean(s, 1), pad = lua_toboolean(s, 2);
    static const uint8_t MENU_KEYS[] = { VK_UP, VK_DOWN, VK_LEFT, VK_RIGHT, VK_RETURN, VK_BACK, VK_PRIOR, VK_NEXT };
    uint8_t list[256] = { 0 };
    int n = lua_gettop(s);
    if (n > 2) {
        for (int i = 3; i <= n; i++) { uint8_t vk; if (key_lookup(s, i, &vk)) list[vk] = 1; }
    } else {
        for (size_t i = 0; i < sizeof MENU_KEYS; i++) list[MENU_KEYS[i]] = 1;
    }
    for (int vk = 0; vk < 256; vk++) g_block_vk[vk] = (uint8_t)(keys && list[vk]);
    g_block_pad = pad && g_game_xget;
    return 0;
}

static int l_aoe_scale(lua_State *s);
static xget_t g_xget;
static int l_pad(lua_State *s)
{
    static int tried;
    if (!tried) {
        tried = 1;
        HMODULE x = LoadLibraryA("xinput1_4.dll");
        if (!x) x = LoadLibraryA("xinput9_1_0.dll");
        if (x) g_xget = (xget_t)GetProcAddress(x, "XInputGetState");
    }
    xstate_t st;
    if (!g_xget || g_xget(0, &st) != 0 || !game_focused()) return 0;
    lua_pushinteger(s, st.buttons); lua_pushinteger(s, st.lt); lua_pushinteger(s, st.rt);
    lua_pushinteger(s, st.lx); lua_pushinteger(s, st.ly); lua_pushinteger(s, st.rx); lua_pushinteger(s, st.ry);
    return 7;
}
// pad_mask(buttons [, triggers [, left stick]]): these buttons, and the triggers and
// left stick if asked, don't reach the game until it's called again.
static int l_pad_mask(lua_State *s)
{
    g_pad_mask = (int)luaL_checkinteger(s, 1);
    g_pad_no_triggers = lua_toboolean(s, 2);
    g_pad_no_lstick = lua_toboolean(s, 3);
    return 0;
}

// ------------------------------------------------------------------ settings, log, callbacks
static int l_setting(lua_State *s)
{
    const char *name = luaL_checkstring(s, 1);
    char v[512];
    GetPrivateProfileStringA("settings", name, "\x01", v, sizeof v, g_ini);
    if (v[0] == 1) { lua_settop(s, 2); return 1; }
    char *c = strchr(v, ';'); if (c) *c = 0;
    size_t n = strlen(v); while (n && (v[n - 1] == ' ' || v[n - 1] == '\t')) v[--n] = 0;
    switch (lua_type(s, 2)) {
    case LUA_TNUMBER: {
        char *end; double d = strtod(v, &end);
        if (end == v) { lua_settop(s, 2); return 1; }
        if (d == (double)(lua_Integer)d && !strpbrk(v, ".eE")) lua_pushinteger(s, (lua_Integer)d); else lua_pushnumber(s, d);
        return 1;
    }
    case LUA_TBOOLEAN: lua_pushboolean(s, !_stricmp(v, "true") || !strcmp(v, "1") || !_stricmp(v, "yes")); return 1;
    default: lua_pushstring(s, v); return 1;
    }
}
static int l_log(lua_State *s)
{
    int n = lua_gettop(s);
    luaL_Buffer b; luaL_buffinit(s, &b);
    for (int i = 1; i <= n; i++) {
        if (i > 1) luaL_addchar(&b, ' ');
        luaL_tolstring(s, i, NULL); luaL_addvalue(&b);
    }
    luaL_pushresult(&b);
    hlog("%s", lua_tostring(s, -1));
    return 0;
}
static int l_on_frame(lua_State *s)
{
    luaL_checktype(s, 1, LUA_TFUNCTION);
    lua_getfield(s, LUA_REGISTRYINDEX, "wml_frames");
    lua_pushvalue(s, 1);
    lua_rawseti(s, -2, (lua_Integer)lua_rawlen(s, -2) + 1);
    return 0;
}

static void start_lua(void)
{
    L = luaL_newstate();
    luaL_openlibs(L);
    lua_newtable(L); lua_setfield(L, LUA_REGISTRYINDEX, "wml_frames");

    static const luaL_Reg api[] = {
        { "log", l_log }, { "setting", l_setting },
        { "read_u8", l_read_u8 }, { "read_u16", l_read_u16 }, { "read_u32", l_read_u32 }, { "read_u64", l_read_u64 },
        { "read_f32", l_read_f32 }, { "read_f64", l_read_f64 },
        { "write_u8", l_write_u8 }, { "write_u16", l_write_u16 }, { "write_u32", l_write_u32 }, { "write_u64", l_write_u64 },
        { "write_f32", l_write_f32 },
        { "key_down", l_key_down }, { "key_pressed", l_key_pressed },
        { "take_key", l_noop }, { "force_key", l_noop }, { "mouse_look", l_noop }, { "set_look", l_noop },
        { "block_input", l_block_input }, { "auto_fire", l_auto_fire },
        { "on_frame", l_on_frame }, { "game", l_game }, { "call", l_call }, { "callf", l_callf },
        { "buffer", l_buffer }, { "read_string", l_read_string },
        { "pad", l_pad }, { "pad_mask", l_pad_mask }, { "aoe_scale", l_aoe_scale }, { "f2u", l_f2u }, { "u2f", l_u2f },
        { NULL, NULL }
    };
    luaL_newlib(L, api);
    lua_pushstring(L, g_mod_folder); lua_setfield(L, -2, "mod_folder");
    lua_pushstring(L, g_root); lua_setfield(L, -2, "root");
    lua_pushstring(L, "SR Tweak Menu"); lua_setfield(L, -2, "mod_name");
    lua_pushstring(L, "sr5"); lua_setfield(L, -2, "game_name");
    lua_pushinteger(L, (lua_Integer)(uintptr_t)g_base); lua_setfield(L, -2, "base");
    lua_setglobal(L, "wml");

    lua_getglobal(L, "package");
    lua_pushfstring(L, "%s\\?.lua", g_mod_folder);
    lua_setfield(L, -2, "path");
    lua_pop(L, 1);

    char main_path[MAX_PATH];
    _snprintf_s(main_path, sizeof main_path, _TRUNCATE, "%s\\main.lua", g_mod_folder);
    if (luaL_loadfile(L, main_path) != LUA_OK || lua_pcall(L, 0, 0, 0) != LUA_OK) {
        hlog("menu failed to load: %s", lua_tostring(L, -1));
        lua_pop(L, 1);
        g_lua_failed = 1;
        return;
    }
    hlog("menu loaded from %s", g_mod_folder);
}

// ------------------------------------------------------------------ per frame (the game's Lua thread)
static void on_frame(void)
{
    if (g_lua_failed) return;
    if (!L) {
        hlog("first frame (thread %lu): starting Lua", GetCurrentThreadId());
        rearm_crash_logger();
        start_lua();
        if (g_lua_failed) return;
    }
    poll_keys();
    lua_getfield(L, LUA_REGISTRYINDEX, "wml_frames");
    lua_Integer n = (lua_Integer)lua_rawlen(L, -1);
    for (lua_Integer i = 1; i <= n; i++) {
        lua_rawgeti(L, -1, i);
        if (lua_pcall(L, 0, 0, 0) != LUA_OK) {
            static char last[512];
            const char *e = lua_tostring(L, -1);
            if (e && strncmp(last, e, sizeof last - 1)) { strncpy_s(last, sizeof last, e, _TRUNCATE); hlog("frame error: %s", e); }
            lua_pop(L, 1);
        }
    }
    lua_pop(L, 1);
}

// ------------------------------------------------------------------ detours
// Moves `len` bytes of whole instructions (none RIP-relative) from `site` to
// a trampoline that jumps back after them, and points `site` at `hook`.
// Returns the trampoline (call it to run the original), or NULL.
static void *detour(uint32_t rva, const uint8_t *expect, size_t len, void *hook, const char *what)
{
    uint8_t *site = g_base + rva;
    if (len < 14 || memcmp(site, expect, len)) {
        hlog("%s at +%X doesn't look as expected (not the executable the menu knows): not hooked", what, rva);
        return NULL;
    }
    uint8_t *tramp = (uint8_t *)VirtualAlloc(NULL, 64, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if (!tramp) return NULL;
    memcpy(tramp, site, len);
    uint8_t *j = tramp + len;                     // jmp [rip+0] ; dq site+len
    j[0] = 0xFF; j[1] = 0x25; *(uint32_t *)(j + 2) = 0; *(uint64_t *)(j + 6) = (uint64_t)(uintptr_t)(site + len);

    uint8_t patch[32];
    memset(patch, 0x90, sizeof patch);
    patch[0] = 0xFF; patch[1] = 0x25; *(uint32_t *)(patch + 2) = 0; *(uint64_t *)(patch + 6) = (uint64_t)(uintptr_t)hook;
    DWORD old;
    if (!VirtualProtect(site, len, PAGE_EXECUTE_READWRITE, &old)) return NULL;
    memcpy(site, patch, len);
    VirtualProtect(site, len, old, &old);
    FlushInstructionCache(GetCurrentProcess(), site, len);
    hlog("hooked %s at +%X", what, rva);
    return tramp;
}

// ------------------------------------------------------------------ the frame hook
// The main loop (+BCC890) pumps window messages, then calls +1B4A320 with
// 0, 1 and 2; the loading screens' loops call it the same way. The call with
// 0 starts an iteration: our frame runs there, on the main thread, outside
// any call into the game's Lua.
typedef uint64_t (*frame_fn_t)(uint64_t, uint64_t, uint64_t, uint64_t);
static frame_fn_t g_frame_orig;
static LARGE_INTEGER g_qpf;
static uint64_t g_stat_frames, g_stat_since;
static DWORD g_main_thread;

static uint64_t my_frame_fn(uint64_t a, uint64_t b, uint64_t c, uint64_t d)
{
    if ((uint32_t)a == 0 && GetCurrentThreadId() == g_main_thread && TryEnterCriticalSection(&g_lock)) {
        LARGE_INTEGER now; QueryPerformanceCounter(&now);
        g_stat_frames++;
        if (!g_stat_since) g_stat_since = (uint64_t)now.QuadPart;
        if ((uint64_t)now.QuadPart - g_stat_since > (uint64_t)g_qpf.QuadPart * 30) {
            hlog("last 30 s: %llu menu frames", g_stat_frames);
            g_stat_frames = 0;
            g_stat_since = (uint64_t)now.QuadPart;
        }
        on_frame();
        autofire_tick();
        LeaveCriticalSection(&g_lock);
    }
    return g_frame_orig(a, b, c, d);
}

static const uint8_t FRAME_FN_PROLOGUE[16] = {
    0x40, 0x56,                     // push rsi
    0x41, 0x55,                     // push r13
    0x48, 0x83, 0xEC, 0x38,         // sub rsp, 38h
    0x48, 0x89, 0x5C, 0x24, 0x50,   // mov [rsp+50h], rbx
    0x8D, 0x41, 0xFF,               // lea eax, [rcx-1]
};

// Every explosion's area of effect goes through +973E80 with byte +0x110 set the one time it
// goes off: scaled there, on that component only, so this is safe on a job thread.
typedef void (*aoe_fn_t)(char *, void *);
static aoe_fn_t g_aoe_orig;
static volatile float g_aoe_radius = 1, g_aoe_force = 1, g_aoe_damage = 1;
static void my_aoe(char *c, void *ctx)
{
    if (c[0x110]) {
        *(float *)(c + 0x40) *= g_aoe_radius;
        *(float *)(c + 0x00) *= g_aoe_force;
        *(float *)(c + 0x04) *= g_aoe_force;
        *(float *)(c + 0x70) *= g_aoe_damage;
        *(float *)(c + 0x74) *= g_aoe_damage;
    }
    g_aoe_orig(c, ctx);
}
static int l_aoe_scale(lua_State *s)
{
    g_aoe_radius = (float)luaL_checknumber(s, 1);
    g_aoe_force = (float)luaL_checknumber(s, 2);
    g_aoe_damage = (float)luaL_checknumber(s, 3);
    lua_pushboolean(s, g_aoe_orig != NULL);
    return 1;
}
static const uint8_t AOE_PROLOGUE[15] = { 0x48, 0x89, 0x5C, 0x24, 0x18, 0x48, 0x89, 0x54, 0x24, 0x10, 0x55, 0x56, 0x57, 0x41, 0x54 };

static void install_hooks(void)
{
    g_frame_orig = (frame_fn_t)detour(RVA_FRAME_FN, FRAME_FN_PROLOGUE, sizeof FRAME_FN_PROLOGUE, (void *)my_frame_fn, "the main loop's frame call");
    g_aoe_orig = (aoe_fn_t)detour(0x973E80, AOE_PROLOGUE, sizeof AOE_PROLOGUE, (void *)my_aoe, "explosions");
}

// ------------------------------------------------------------------ DirectInput proxy
typedef HRESULT (WINAPI *create_t)(HINSTANCE, DWORD, REFIID, LPVOID *, LPUNKNOWN);
HRESULT WINAPI proxy_DirectInput8Create(HINSTANCE inst, DWORD version, REFIID riid, LPVOID *out, LPUNKNOWN outer)
{
    // The Epic overlay (EOSOVH) hooks DirectInput8Create in modules named
    // dinput8.dll and passes calls on to "dinput8.dll"'s export, which is this
    // one: calling System32's dinput8.dll would come straight back here. So we
    // call a copy of it under another name, which the overlay leaves alone.
    static create_t real;
    static __declspec(thread) int depth;
    if (!real) {
        char path[MAX_PATH], copy[MAX_PATH];
        GetSystemDirectoryA(path, MAX_PATH);
        strcat_s(path, MAX_PATH, "\\dinput8.dll");
        _snprintf_s(copy, MAX_PATH, _TRUNCATE, "%s\\dinput8_system.dll", g_root);
        CreateDirectoryA(g_root, NULL);
        CopyFileA(path, copy, FALSE);   // (fails harmlessly while another process has the copy loaded)
        HMODULE m = LoadLibraryA(copy);
        real = m ? (create_t)GetProcAddress(m, "DirectInput8Create") : NULL;
        if (!real || real == proxy_DirectInput8Create) { real = NULL; hlog("couldn't load %s", copy); return E_FAIL; }
        hlog("DirectInput goes to %s", copy);
    }
    if (depth > 2) { hlog("DirectInput8Create came back to the proxy %d times; refused", depth); return E_FAIL; }
    depth++;
    HRESULT hr = real(inst, version, riid, out, outer);
    depth--;
    return hr;
}

// ------------------------------------------------------------------ crash logger
// The game's own crash handling ends the process without a Windows error
// report or a dump, so we log every serious exception first (code, where,
// a short stack as module+offset). The host's own guarded reads and calls
// raise some too (the guard catches those): they're marked "guarded".

static void where(void *addr, char *out, size_t n)
{
    HMODULE m = NULL;
    char path[MAX_PATH] = "?";
    if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (LPCSTR)addr, &m) && m) {
        GetModuleFileNameA(m, path, MAX_PATH);
        const char *base = strrchr(path, '\\');
        _snprintf_s(out, n, _TRUNCATE, "%s+%llX", base ? base + 1 : path, (unsigned long long)((uint8_t *)addr - (uint8_t *)m));
    } else {
        _snprintf_s(out, n, _TRUNCATE, "%p", addr);
    }
}

static LONG CALLBACK crash_logger(EXCEPTION_POINTERS *e)
{
    DWORD code = e->ExceptionRecord->ExceptionCode;
    // errors and guard-page hits (0x80000001: touching one disarms it, which can
    // bring a thread down later); not C++ throws, debugger chatter or thread naming
    if (code < 0x80000000 || code == 0xE06D7363 || code == 0x406D1388) return EXCEPTION_CONTINUE_SEARCH;
    static volatile LONG logged;
    if (InterlockedIncrement(&logged) > 30) return EXCEPTION_CONTINUE_SEARCH;
    char at[160];
    where(e->ExceptionRecord->ExceptionAddress, at, sizeof at);
    char extra[64] = "";
    if (code == 0xC0000005 && e->ExceptionRecord->NumberParameters >= 2)
        _snprintf_s(extra, sizeof extra, _TRUNCATE, " (%s %p)", e->ExceptionRecord->ExceptionInformation[0] ? "writing" : "reading",
                    (void *)e->ExceptionRecord->ExceptionInformation[1]);
    hlog("EXCEPTION %08lX at %s%s, thread %lu%s", code, at, extra, GetCurrentThreadId(), g_guarded ? " (guarded)" : "");
    void *frames[16];
    USHORT n = RtlCaptureStackBackTrace(0, 16, frames, NULL);
    char line[1200] = "", one[160];
    for (USHORT i = 0; i < n; i++) {
        where(frames[i], one, sizeof one);
        strcat_s(line, sizeof line, " ");
        strcat_s(line, sizeof line, one);
    }
    hlog("  stack:%s", line);
    return EXCEPTION_CONTINUE_SEARCH;
}

// The game registers its own handler (+E3BFC0, which ends in TerminateProcess) after we
// load, and the last one registered at the front runs first, so ours has to go back in
// front of it once the game is up. Its way out is logged too.
static PVOID g_crash_handle;
static void rearm_crash_logger(void)
{
    if (g_crash_handle) RemoveVectoredExceptionHandler(g_crash_handle);
    g_crash_handle = AddVectoredExceptionHandler(1, crash_logger);
}
typedef BOOL (WINAPI *terminate_t)(HANDLE, UINT);
static terminate_t g_terminate;
static BOOL WINAPI my_terminate(HANDLE h, UINT code)
{
    if (h == GetCurrentProcess()) {
        void *frames[16];
        USHORT n = RtlCaptureStackBackTrace(0, 16, frames, NULL);
        char line[1200] = "", one[160];
        for (USHORT i = 0; i < n; i++) {
            where(frames[i], one, sizeof one);
            strcat_s(line, sizeof line, " ");
            strcat_s(line, sizeof line, one);
        }
        hlog("TerminateProcess(self, %u), thread %lu, stack:%s", code, GetCurrentThreadId(), line);
    }
    return g_terminate(h, code);
}

// ------------------------------------------------------------------ entry
BOOL WINAPI DllMain(HINSTANCE self, DWORD reason, LPVOID unused)
{
    if (reason == DLL_PROCESS_DETACH) {
        // unused != NULL: the process is ending normally (ExitProcess); a crash
        // or TerminateProcess never gets here
        if (unused) hlog("process exiting normally");
        return TRUE;
    }
    if (reason != DLL_PROCESS_ATTACH) return TRUE;
    DisableThreadLibraryCalls(self);
    InitializeCriticalSection(&g_lock);
    QueryPerformanceFrequency(&g_qpf);

    char exe[MAX_PATH];
    GetModuleFileNameA(NULL, exe, MAX_PATH);
    strcpy_s(g_game_dir, MAX_PATH, exe);
    char *slash = strrchr(g_game_dir, '\\'); if (slash) *slash = 0;
    _snprintf_s(g_root, MAX_PATH, _TRUNCATE, "%s\\TweakMenu", g_game_dir);
    _snprintf_s(g_mod_folder, MAX_PATH, _TRUNCATE, "%s\\SRTweakMenu", g_root);
    _snprintf_s(g_ini, MAX_PATH, _TRUNCATE, "%s\\mod.ini", g_mod_folder);
    // The game logs to wml.log; anything else that loads us (the Epic
    // launcher) to a log of its own, so two processes never share one file.
    const char *exe_name = slash ? slash + 1 : exe;
    if (!_stricmp(exe_name, "SaintsRow_DX12.exe")) {
        _snprintf_s(g_log_path, MAX_PATH, _TRUNCATE, "%s\\wml.log", g_root);
    } else {
        char stem[MAX_PATH];
        strcpy_s(stem, MAX_PATH, exe_name);
        char *dot = strrchr(stem, '.'); if (dot) *dot = 0;
        _snprintf_s(g_log_path, MAX_PATH, _TRUNCATE, "%s\\wml_%s.log", g_root, stem);
    }
    CreateDirectoryA(g_root, NULL);
    // Keep the last run's log: after a crash it's the only evidence.
    {
        char prev[MAX_PATH];
        _snprintf_s(prev, MAX_PATH, _TRUNCATE, "%s.prev", g_log_path);
        MoveFileExA(g_log_path, prev, MOVEFILE_REPLACE_EXISTING);
    }
    g_log = _fsopen(g_log_path, "w", _SH_DENYNO);
    hlog("SR5 Tweak Menu host started in %s (thread %lu)", exe, GetCurrentThreadId());

    g_base = (uint8_t *)GetModuleHandleA(NULL);
    const char *name = slash ? slash + 1 : exe;
    if (_stricmp(name, "SaintsRow_DX12.exe")) {
        hlog("%s isn't supported yet (only SaintsRow_DX12.exe); menu off, input passes through", name);
        return TRUE;
    }
    g_main_thread = GetCurrentThreadId();
    rearm_crash_logger();
    g_terminate = (terminate_t)hook_import("KERNEL32.dll", "TerminateProcess", (void *)my_terminate);
    if (!g_terminate) g_terminate = TerminateProcess;
    install_hooks();
    install_input_hooks();
    return TRUE;
}
