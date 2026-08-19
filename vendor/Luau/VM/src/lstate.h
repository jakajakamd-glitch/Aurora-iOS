// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
// This code is based on Lua 5.x implementation licensed under MIT License; see lua_LICENSE.txt for details
#pragma once

#include "lobject.h"
#include "ltm.h"
#include "ludata.h"

// registry
#define registry( L ) ( &L->global->registry )

// extra stack space to handle TM calls and some other extras
#define EXTRA_STACK 5

#define BASIC_CI_SIZE 8

#define BASIC_STACK_SIZE ( 2 * LUA_MINSTACK )

// VERIFIED from luaS_newlstr (0x254DD90) disassembly:
//   ldr x9, [x24]        → strt.hash at G+0x00
//   ldr w8, [x24, 0xc]   → strt.size at G+0x0c
// Field order: hash(0), nuse(8), size(c) — NOT size, nuse, hash!
// clang-format off
typedef struct stringtable
{
    TString** hash;   // +0x00
    uint32_t nuse;    // +0x08
    int size;         // +0x0c
} stringtable;
// clang-format on

// VERIFIED from thread_init_arrays (0x5d0ea48) + lua_pushvalue + luau_execute:
//   thread_init_arrays: stp x9, x0, [x8] → ci[0]=base=stack+0x10, ci[8]=func=stack
//                       stp xzr, x9, [x8, 0x10] → ci[16]=p=NULL, ci[24]=top=stack+0x150
//   lua_pushvalue: ldr x8, [x8, 0x18] → ci+0x18 = ci->top (stack check)
//   luau_execute: ldr x9, [x8, 8] then ldr x22, [x9] → ci[8]=func, *func=Closure*
//                 ldr x26, [x8, 0x20] → ci+0x20 = savedpc
// NOTE: roblox swaps p and func compared to standard Luau!
//   standard: { base, p, func, top } → { +0, +8, +16, +24 }
//   roblox:   { base, func, p, top } → { +0, +8, +16, +24 }
// clang-format off
typedef struct CallInfo
{
    StkId base;                // +0x00
    StkId func;                // +0x08 (VERIFIED: ci[8]=stack in thread_init_arrays, *func=Closure* in luau_execute)
    Proto* p;                  // +0x10 (VERIFIED: ci[16]=0=NULL in thread_init_arrays)
    StkId top;                 // +0x18 (VERIFIED: ci[24]=stack+0x150 in thread_init_arrays)
    union
    {
        const Instruction* savedpc; // +0x20 (VERIFIED: ldr x26, [x8, 0x20] in luau_execute)
        int errfunc;
    };
    int nresults;              // +0x28
    unsigned int flags;        // +0x2c
} CallInfo;
// clang-format on

#define LUA_CALLINFO_RETURN ( 1 << 0 )
#define LUA_CALLINFO_HANDLE ( 1 << 1 )
#define LUA_CALLINFO_NATIVE ( 1 << 2 )
#define LUA_CALLINFO_OPYIELD ( 1 << 3 )

#define curr_func( L ) ( clvalue( L->ci->func ) )
#define ci_func( ci ) ( clvalue( (ci)->func ) )
#define f_isLua( ci ) ( ci_func( ci )->tt == 8 )
#define isLua( ci ) ( ttisfunction( (ci)->func ) && f_isLua( ci ) )

struct GCStats
{
    int32_t triggerterms[ 32 ] = {0};
    uint32_t triggertermpos = 0;
    int32_t triggerintegral = 0;
    size_t atomicstarttotalsizebytes = 0;
    size_t endtotalsizebytes = 0;
    size_t heapgoalsizebytes = 0;
    double starttimestamp = 0;
    double atomicstarttimestamp = 0;
    double endtimestamp = 0;
};

#ifdef LUAI_GCMETRICS
struct GCCycleMetrics
{
    size_t starttotalsizebytes = 0;
    size_t heaptriggersizebytes = 0;
    double pausetime = 0.0;
    double starttimestamp = 0.0;
    double endtimestamp = 0.0;
    double marktime = 0.0;
    double markassisttime = 0.0;
    double markmaxexplicittime = 0.0;
    size_t markexplicitsteps = 0;
    size_t markwork = 0;
    double atomicstarttimestamp = 0.0;
    size_t atomicstarttotalsizebytes = 0;
    double atomictime = 0.0;
    double atomictimeupval = 0.0;
    double atomictimeweak = 0.0;
    double atomictimegray = 0.0;
    double atomictimeembedder = 0.0;
    double atomictimeclear = 0.0;
    double sweeptime = 0.0;
    double sweepassisttime = 0.0;
    double sweepmaxexplicittime = 0.0;
    size_t sweepexplicitsteps = 0;
    size_t sweepwork = 0;
    size_t assistwork = 0;
    size_t explicitwork = 0;
    size_t propagatework = 0;
    size_t propagateagainwork = 0;
    size_t endtotalsizebytes = 0;
};

struct GCMetrics
{
    double stepexplicittimeacc = 0.0;
    double stepassisttimeacc = 0.0;
    uint64_t completedcycles = 0;
    GCCycleMetrics lastcycle;
    GCCycleMetrics currcycle;
};
#endif

struct lua_ExecutionCallbacks
{
    void* context;
    void (*close)(lua_State* L);
    void (*destroy)(lua_State* L, Proto* proto);
    int (*enter)(lua_State* L, Proto* proto);
    void (*disable)(lua_State* L, Proto* proto);
    size_t (*getmemorysize)(lua_State* L, Proto* proto);
    uint8_t (*gettypemapping)(lua_State* L, const char* str, size_t len);
    char* (*getcounterdata)(lua_State* L, Proto* proto, size_t* count);
    Proto* (*inlinefunction)(lua_State* L, Closure* caller, Closure* target, uint32_t pc);
};

struct lua_UdataDirectAccessData
{
    TValue indextm;
    TValue newindextm;
    TValue namecalltm;
    lua_UserdataDirectAccess index;
    lua_UserdataDirectAccess newindex;
    lua_UserdataDirectNamecall namecall;
};

/*
** `global state', shared by all threads of this state
**
** Layout matches new libroblox.so global_State.
** Verified from lua_newstate (0x2549bbc) disassembly.
** Total allocation: 0x4b80 bytes (lua_State 0x80 + global_State).
** global_State starts at L + 0x80.
**
** Key verified offsets:
**   G + 0x28 = frealloc (lua_Alloc)
**   G + 0x30 = ud (void*)
**   G + 0x38 = gc_goal (double)
**   G + 0x40 = gc_pause (int) = 200
**   G + 0x50 = totalbytes = 0x4b80
**   G + 0x1a0 = mainthread
**   G + 0x4c0 = RobloxExtraSpace (main thread)
**   G + 0x518 = exec_callback_enter (lua_resume)
**   G + 0x528 = exec_callback (lua_resume)
*/
// clang-format off
typedef struct global_State
{
    stringtable strt;                         // +0x00
    GCObject* gray;                           // +0x10
    GCObject* grayagain;                      // +0x18
    GCObject* weak;                           // +0x20
    lua_Alloc frealloc;                       // +0x28
    void* ud;                                 // +0x30
    int gcstepsize;                           // +0x38
    int gcstepmul;                            // +0x3c
    int gcgoal;                               // +0x40
    char _pad0[0x4];                          // +0x44
    size_t GCthreshold;                       // +0x48
    size_t totalbytes;                        // +0x50
    uint8_t currentwhite;                     // +0x58
    uint8_t gcstate;                          // +0x59
    char _pad1[0x6];                          // +0x5a
    lua_Page* freepages[LUA_SIZECLASSES];     // +0x60
    lua_State* mainthread;                    // +0x1a0
    lua_Page* sweepgcopage;                   // +0x1a8
    lua_Page* freegcopages[LUA_SIZECLASSES];  // +0x1b0
    lua_Page* allgcopages;                    // +0x2f0
    lua_Page* allpages;                       // +0x2f8
    UpVal uvhead;                             // +0x300
    LuaTable* mt[LUA_T_COUNT];                // +0x328
    TString* tmname[TM_N];                    // +0x398
    TString* ttname[LUA_T_COUNT];             // +0x440
    TValue pseudotemp;                        // +0x4b0
    TValue registry;                          // +0x4c0
    int registryfree;                         // +0x4d0
    char _pad2[0x4];                          // +0x4d4
    struct lua_jmpbuf* errorjmp;              // +0x4d8
    lua_Callbacks cb;                         // +0x4e0
    uint64_t rngstate;                        // +0x530
    uint64_t ptrenckey[4];                    // +0x538
    lua_ExecutionCallbacks ecb;                // +0x558
    alignas(16) uint8_t ecbdata[LUA_EXECUTION_CALLBACK_STORAGE]; // +0x598
    lua_UdataDirectAccessData udatadirect[UTAG_INTERNAL_LIMIT]; // +0x7a0
    size_t memcatbytes[LUA_MEMORY_CATEGORIES]; // +0x2c30
    void (*udatagc[LUA_UTAG_LIMIT])(lua_State*, void*); // +0x3410
    lua_UserdataMark udatamark[LUA_UTAG_LIMIT]; // +0x3810
    LuaTable* udatamt[LUA_UTAG_LIMIT];        // +0x3c10
    TValue weakregistry;                      // +0x4010
    int weakregistryfree;                     // +0x4020
    char _pad3[0x4];                          // +0x4024
    lua_EmbedderGc embeddergc;                // +0x4028
    TString* lightuserdataname[LUA_LUTAG_LIMIT]; // +0x4030
    LuaTable* udatadirectfields[UTAG_INTERNAL_LIMIT]; // +0x4430
    GCStats gcstats;                          // +0x4830
    uint32_t lastprotoid;                     // +0x48d0
    char _pad4[0x4];                          // +0x48d4
#ifdef LUAI_GCMETRICS
    GCMetrics gcmetrics;
#endif
} global_State;
// clang-format on

/*
** `per thread' state
**
** VERIFIED from new libroblox.so via FULL reverse engineering:
**   lua_newstate (0x2549bbc): initial field writes + alloc size 0x4b80
**   luaE_newthread (0x25a58e0): CommonHeader + field copies + thread_init_arrays call
**   thread_init_arrays (0x5d0ea48): ci/stack/base_ci/end_ci/stacksize/size_ci/top/base/stack_last
**   f_luaopen (0x5d0eb2c): str x0, [x19, 0x50] → L+0x50 = gt (luaH_new result)
**   lua_pushvalue (0x254e5bc): L+0x08 = top (write+incr), L+0x28 = base (positive idx),
**                              L+0x18 = ci, L+0x40 = openupval (passed to GC func)
**   pseudo2addr (0x5d014a8): L+0x50 = gt (GLOBALSINDEX), L+0x20 = global,
**                            L+0x68 = base_ci (REGISTRYINDEX cmp), G+0x4b0 = pseudotemp,
**                            G+0x4c0 = registry (ENVIRONINDEX returns this)
**   luau_execute (0x5d1492c): L+0x18 = ci, L+0x08 = top, L+0x28 = base, L+0x30 = stack
**
** lua_State size = 0x80 (128 bytes) — VERIFIED from alloc size in luaE_newthread (mov w1, 0x80)
*/
// clang-format off
struct lua_State
{
    CommonHeader;              /* +0x00 */
    uint8_t status;            /* +0x03 */
    uint8_t activememcat;      /* +0x04 */
    uint8_t singlestep;        /* +0x05 */
    uint8_t isactive;          /* +0x06 */
    char _pad0[0x1];           /* +0x07 */
    TValue* top;               /* +0x08 */
    TValue* stack_last;        /* +0x10 */
    struct CallInfo* ci;       /* +0x18 */
    global_State* global;      /* +0x20 */
    TValue* base;              /* +0x28 */
    TValue* stack;             /* +0x30 */
    TString* namecall;         /* +0x38 */
    GCObject* gclist;          /* +0x40 */
    UpVal* openupval;          /* +0x48 */
    LuaTable* gt;              /* +0x50 */
    RobloxExtraSpace* userdata;/* +0x58 */
    struct CallInfo* end_ci;   /* +0x60 */
    struct CallInfo* base_ci;  /* +0x68 */
    uint16_t nCcalls;          /* +0x70 */
    uint16_t baseCcalls;       /* +0x72 */
    int cachedslot;            /* +0x74 */
    int stacksize;             /* +0x78 */
    int size_ci;               /* +0x7c */
};
// clang-format on

union GCObject
{
    GCheader gch;
    struct TString ts;
    struct Udata u;
    struct Closure cl;
    struct LuaTable h;
    struct Proto p;
    struct UpVal uv;
    struct lua_State th;
    struct LuauBuffer buf;
    struct LuauClass lclass;
    struct LuauObject lobject;
    struct LuauVector vec;
};

#define gco2ts(o) check_exp((o)->gch.tt == LUA_TSTRING, &((o)->ts))
#define gco2u(o) check_exp((o)->gch.tt == LUA_TUSERDATA, &((o)->u))
#define gco2cl(o) check_exp((o)->gch.tt == LUA_TFUNCTION, &((o)->cl))
#define gco2h(o) check_exp((o)->gch.tt == LUA_TTABLE, &((o)->h))
#define gco2p(o) check_exp((o)->gch.tt == LUA_TPROTO, &((o)->p))
#define gco2uv(o) check_exp((o)->gch.tt == LUA_TUPVAL, &((o)->uv))
#define gco2th(o) check_exp((o)->gch.tt == LUA_TTHREAD, &((o)->th))
#define gco2buf(o) check_exp((o)->gch.tt == LUA_TBUFFER, &((o)->buf))
#define gco2class(o) check_exp((o)->gch.tt == LUA_TCLASS, &((o)->lclass))
#define gco2object(o) check_exp((o)->gch.tt == LUA_TOBJECT, &((o)->lobject))
#define gco2vec(o) check_exp((o)->gch.tt == LUA_TVECTOR, &((o)->vec))

#define obj2gco(v) check_exp(iscollectable(v), cast_to(GCObject*, (v) + 0))

LUAI_FUNC lua_State* luaE_newthread(lua_State* L);
LUAI_FUNC void luaE_freethread(lua_State* L, lua_State* L1, struct lua_Page* page);
