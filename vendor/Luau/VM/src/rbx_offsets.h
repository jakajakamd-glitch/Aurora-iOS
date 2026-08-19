// ============================================================================
//  rbx_offsets.h — All reversed function offsets for new libroblox.so
//  Every Lua-related function found via radare2 + r2ghidra reverse engineering
// ============================================================================
#pragma once
#include <cstdint>

// All offsets verified by tracing ScriptContext.cpp flow through the new binary.
// Methods used:
//   - String xrefs (find string → find adrp+add → find containing function)
//   - Call chain tracing (startScript → getGlobalState → lua_newthread → ...)
//   - Struct field access patterns (ldrb/ldr/str with known offsets)
//   - r2ghidra decompilation for verification

namespace rbx_offsets
{
    // === ScriptContext functions ===
    // Found via "startScript re-entrancy" string (0x58d151)
    constexpr uint64_t startScript                  = 0x2563a74;
    // Found via "Failed to create Lua state" string (0x39413c)
    constexpr uint64_t openState                    = 0x2546f38;
    // Found by matching sandboxThread pattern (lua_newtable×2, protect_metatable, __index, pushvalue, settable, setmetatable, replace)
    constexpr uint64_t setThreadIdentityAndSandbox  = 0x25a6040;
    // Found via "Can't resume script" string (0x306546)
    constexpr uint64_t resumeImpl                   = 0x25ab8c8;
    // Found by tracing startScript call chain (called after getGlobalState)
    constexpr uint64_t getGlobalState               = 0x25a4b4c;
    // 8-byte function, checks flag at [x0+0x10]
    constexpr uint64_t canCompileScripts            = 0x25a4b44;

    // === LuaVM::load (the "safe loader") ===
    // Found by tracing loadstring → LuaVM::load call
    constexpr uint64_t LuaVM_load                   = 0x25a7bd4;
    // Called from LuaVM_load, compiles + calls luau_load_wrapper
    constexpr uint64_t LuaVM_load_compile           = 0x3cd7868;
    // Sets up RobloxLoadStruct, calls luaD_rawrunprotected
    constexpr uint64_t luau_load_wrapper            = 0x25a7cd4;
    // setjmp-based exception wrapper
    constexpr uint64_t luaD_rawrunprotected         = 0x2549e88;
    // Found via "bytecode version mismatch" string (0x4bb3d5, one byte after null terminator)
    // This is the ACTUAL bytecode parser — 5680 bytes, references all bytecode error strings
    constexpr uint64_t luau_load_impl               = 0x5d200f4;
    // luaL_loadbuffer (loadstring path, references "anonymous function" string)
    constexpr uint64_t luaL_loadbuffer              = 0x3d2319c;

    // === Lua state functions ===
    // Found via openState → lua_newstate call chain. Allocates 0x4b80 bytes.
    constexpr uint64_t lua_newstate                 = 0x2549bbc;
    // Found in startScript, called after getGlobalState with (globalState)
    // Pushes new thread on stack, calls luaE_newthread
    constexpr uint64_t lua_newthread                = 0x25a580c;
    // Internal: allocates 0x80 bytes (lua_State), sets tt=0xa, copies global pointer
    constexpr uint64_t luaE_newthread               = 0x25a58e0;
    // Called from luaE_newthread: allocates stack (0x180) + callinfo array (0x2dc)
    constexpr uint64_t thread_init_arrays           = 0x5d0ea48;

    // === Lua C API (all verified from sandboxThread in setThreadIdentityAndSandbox) ===
    // lua_createtable(L, narr, nrec) — called with (L, 0, 0) in sandboxThread
    constexpr uint64_t lua_createtable              = 0x254f048;
    // luaH_new(L, narray, nrec) — creates Table, called from lua_createtable
    constexpr uint64_t luaH_new                     = 0x254d918;
    // lua_pushvalue(L, idx) — called with LUA_GLOBALSINDEX (-10002)
    constexpr uint64_t lua_pushvalue                = 0x254e5bc;
    // lua_settable(L, idx) — called with -3
    constexpr uint64_t lua_settable                 = 0x254f114;
    // lua_setmetatable(L, idx) — called with -2
    constexpr uint64_t lua_setmetatable             = 0x254fcd4;
    // lua_replace(L, idx) — called with LUA_GLOBALSINDEX (-10002)
    constexpr uint64_t lua_replace                  = 0x25a62bc;
    // lua_setglobal(L, name) — called with "_G", "script", "shared", "_G"
    constexpr uint64_t lua_setglobal                = 0x254e69c;
    // lua_settop(L, idx) — called with -2 (LUA_REGISTRYINDEX)
    constexpr uint64_t lua_settop                   = 0x254efa0;
    // Lua::protect_metatable(L, idx) — "The metatable is locked" string
    constexpr uint64_t protect_metatable            = 0x2550e0c;

    // === VM execution ===
    // Found via callers of luaG_typeerror. VM dispatch loop (21616 bytes).
    // Reads L+0x08 (base), L+0x18 (ci), L+0x28 (top), L+0x03 (status)
    // Opcode dispatch: ldrb from Proto+0x10 (decrypt table) → br via jump table at 0x664a0b0
    constexpr uint64_t luau_execute                 = 0x5d1492c;
    // Found by finding callers of luau_execute. Calls luau_execute via G+0x528 callback.
    constexpr uint64_t lua_resume                   = 0x5d07f98;
    // luaG_typeerror — "attempt to %s a %s value" string (0x289c8c)
    constexpr uint64_t luaG_typeerror               = 0x5d0874c;
    // luaC_step — GC step, called from many push functions
    constexpr uint64_t luaC_step                    = 0x5d09d38;

    // === String/format functions ===
    // luaO_pushfstring(L, fmt, ...) — varargs string formatter
    constexpr uint64_t luaO_pushfstring             = 0x5d0038c;
    // lua_pushfstring — wrapper around luaO_pushfstring
    constexpr uint64_t lua_pushfstring              = 0x2721078;

    // === RobloxExtraSpace access ===
    // For child threads: returns L->field_0x58 (ExtraSpace pointer)
    // ldr x0, [x0, 0x58]; ret
    constexpr uint64_t extraspace_get_thread        = 0x22f5eec;
    // For main thread: returns L->global + 0x4c0 (direct offset, not pointer)
    // ldr x8, [x0, 0x20]; add x0, x8, #0x4c0; ret
    constexpr uint64_t extraspace_get_global        = 0x5d014cc;
    // Returns L->global + 0x4e0 (ScriptContext*)
    // ldr x8, [x0, 0x20]; add x0, x8, #0x4e0; ret
    constexpr uint64_t getContext                   = 0x254df90;

    // === Memory ===
    // luaM_realloc_(L, block, osize, nsize) — main Lua allocator
    constexpr uint64_t luaM_realloc                 = 0x1d2030c;
    // luaM_newgco — GC page allocator (used by luaE_newthread)
    constexpr uint64_t luaM_newgco                  = 0x2549f48;

    // === Opcode dispatch (runtime-filled) ===
    // Jump table at 0x664a0b0 (8 bytes per entry, ~80 entries, in .bss)
    // Filled at runtime during VM initialization
    constexpr uint64_t opcode_dispatch_table        = 0x664a0b0;

    // === Stack-related ===
    // luaD_growstack — called when stack is full
    constexpr uint64_t luaD_growstack               = 0x25b834c;

    // === Struct sizes ===
    constexpr size_t LUA_STATE_SIZE                 = 0x80;   // 128 bytes
    constexpr size_t GLOBAL_STATE_SIZE              = 0x4b00; // 19200 bytes
    constexpr size_t TOTAL_NEWSTATE_ALLOC           = 0x4b80; // 19328 bytes
    constexpr size_t TVALUE_SIZE                    = 0x10;   // 16 bytes
    constexpr size_t CALLINFO_SIZE                  = 0x30;   // 48 bytes
    constexpr size_t PROTO_SIZE                     = 0xa0;   // 160 bytes (from luaF_newproto alloc)
    constexpr size_t BASIC_CI_SIZE                  = 8;      // 8 CallInfo slots
    constexpr size_t BASIC_STACK_SIZE               = 0x180;  // 384 bytes (24 TValues)

    // === ExtraSpace offsets ===
    // Main thread: ExtraSpace at G + 0x4c0
    // Child threads: ExtraSpace pointer at L + 0x58
    // ScriptContext* at G + 0x4e0
    constexpr size_t EXTRASPACE_OFFSET_G            = 0x4c0;
    constexpr size_t EXTRASPACE_PTR_OFFSET_L        = 0x58;
    constexpr size_t CONTEXT_OFFSET_G               = 0x4e0;

    // === ExtraSpace internal layout (from setThreadIdentityAndSandbox @ 0x25a6040) ===
    // ES + 0x18: control block pointer (shared_ptr control)
    // ES + 0x40: 16 bytes (shared_ptr<BaseScript> — script object)
    // ES + 0x50: identity-related pointer
    // ES + 0x58: shared_ptr pair (script + control block)
    // ES + 0x60: previous value (freed if non-NULL)
    // ES + 0x88: 16 bytes (thread info, stored from q0)
    // ES + 0x90: previous value (freed if non-NULL)
    constexpr size_t EXTRASPACE_SIZE                = 0x180; // 384 bytes (from 0x5d0ea48 alloc)

    // === global_State key offsets (from lua_newstate @ 0x2549bbc) ===
    // G = L + 0x80
    constexpr size_t G_FREALLOC                    = 0x28;   // lua_Alloc
    constexpr size_t G_UD                          = 0x30;   // void*
    constexpr size_t G_GC_GOAL                     = 0x38;   // double
    constexpr size_t G_GC_PAUSE                    = 0x40;   // int = 200
    constexpr size_t G_TOTALBYTES                  = 0x50;   // size_t = 0x4b80
    constexpr size_t G_MAINTHREAD                  = 0x1a0;  // lua_State*
    constexpr size_t G_THREAD_CHAIN_START          = 0x310;
    constexpr size_t G_THREAD_CHAIN_END            = 0x318;
    constexpr size_t G_EXTRASPACE                  = 0x4c0;  // RobloxExtraSpace (main thread)
    constexpr size_t G_CONTEXT                     = 0x4e0;  // ScriptContext*
    constexpr size_t G_EXEC_CALLBACK_ENTER         = 0x518;  // used by lua_resume
    constexpr size_t G_EXEC_CALLBACK               = 0x528;  // used by lua_resume

    // === lua_State key offsets (from lua_newstate + luaE_newthread + luau_execute) ===
    constexpr size_t L_TT                          = 0x00;   // uint8_t = 0xa
    constexpr size_t L_MARKED                      = 0x01;   // uint8_t
    constexpr size_t L_MEMCAT                      = 0x02;   // uint8_t
    constexpr size_t L_STATUS                      = 0x03;   // uint8_t
    constexpr size_t L_ACTIVEMEMCAT                = 0x04;   // uint8_t
    constexpr size_t L_SINGLESTEP                  = 0x05;   // bool
    constexpr size_t L_BASE                        = 0x08;   // StkId
    constexpr size_t L_STACK_LAST                  = 0x10;   // StkId
    constexpr size_t L_CI                          = 0x18;   // CallInfo*
    constexpr size_t L_GLOBAL                      = 0x20;   // global_State*
    constexpr size_t L_TOP                         = 0x28;   // StkId
    constexpr size_t L_STACK                       = 0x30;   // StkId
    constexpr size_t L_GCLIST                      = 0x38;   // GCObject*
    constexpr size_t L_BASE_CI                     = 0x40;   // CallInfo*
    constexpr size_t L_END_CI                      = 0x48;   // CallInfo*
    constexpr size_t L_OPENUPVAL                   = 0x50;   // UpVal*
    constexpr size_t L_USERDATA                    = 0x58;   // RobloxExtraSpace*
    constexpr size_t L_CI_BASE                     = 0x60;   // CallInfo*
    constexpr size_t L_STACKSIZE                   = 0x68;   // int
    constexpr size_t L_SIZE_CI                     = 0x6c;   // int
    constexpr size_t L_GT                          = 0x70;   // LuaTable*
    constexpr size_t L_NCCALLS                     = 0x78;   // uint16_t
    constexpr size_t L_BASECCALLS                  = 0x7a;   // uint16_t
    constexpr size_t L_CACHEDSLOT                  = 0x7c;   // uint32_t

    // === CallInfo offsets (unchanged from old binary) ===
    constexpr size_t CI_BASE                       = 0x00;   // StkId
    constexpr size_t CI_P                          = 0x08;   // Proto*
    constexpr size_t CI_FUNC                       = 0x10;   // StkId
    constexpr size_t CI_TOP                        = 0x18;   // StkId
    constexpr size_t CI_SAVEDPC                    = 0x20;   // Instruction*
    constexpr size_t CI_NRESULTS                   = 0x28;   // int
    constexpr size_t CI_FLAGS                      = 0x2c;   // unsigned int

    // === Proto key offsets ===
    constexpr size_t P_OPCODE_DECRYPT              = 0x10;   // uint8_t* (per-Proto opcode mapping)
    constexpr size_t P_CODE                        = 0x30;   // Instruction*
    constexpr size_t P_P                           = 0x40;   // Proto**
    constexpr size_t P_K                           = 0x50;   // TValue*
    constexpr size_t P_LINEINFO                    = 0x58;   // uint8_t*
    constexpr size_t P_SOURCE                      = 0x60;   // TString*
    constexpr size_t P_EXECDATA                    = 0x68;   // void*
    constexpr size_t P_EXECTARGET                  = 0x70;   // uintptr_t
    constexpr size_t P_CODEENTRY                   = 0x78;   // const Instruction*
    constexpr size_t P_SIZECODE                    = 0x88;   // int
}
