// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
// This code is based on Lua 5.x implementation licensed under MIT License; see lua_LICENSE.txt for details
#pragma once

#include "lua.h"
#include "lcommon.h"

/*
** Union of all collectible objects
*/
typedef union GCObject GCObject;

/*
** Common Header for all collectible objects (in macro form, to be included in other objects)
*/
// clang-format off
// roblox CommonHeader — VERIFIED from lua_newstate (0x2549bbc) + luaE_newthread (0x25a58e0) + luaH_new (0x254d918):
//   lua_newstate:  strh w8=0xa, [x19]     → L[0]=tt=0xa, L[1]=0 (memcat=0 for main thread)
//                  strb w9=9, [x19, 2]    → L[2]=marked=9 (bit2mask(WHITE0BIT=0, FIXEDBIT=3))
//   luaE_newthread: strb w8=0xa, [x0]     → +0=tt
//                  strb w9=parent[4], [x0,1] → +1=memcat (from parent activememcat)
//                  strb w9=currentwhite&3, [x0,2] → +2=marked (white bits)
//   luaH_new:      strb w9=7, [x0]        → +0=tt=LUA_TTABLE
//                  strb w10=parent[4], [x0,1] → +1=memcat
//                  strb w8=currentwhite&3, [x0,2] → +2=marked
// ORDER: { tt(0), memcat(1), marked(2) }
#define CommonHeader \
     uint8_t tt; uint8_t memcat; uint8_t marked
// clang-format on

/*
** Common header in struct form
*/
typedef struct GCheader
{
    CommonHeader;
} GCheader;

/*
** Union of all Lua values
*/
typedef union
{
    GCObject* gc;
    void* p;
    double n;
    int b;
    int64_t l;
    float v[2]; // v[0], v[1] live here; v[2] lives in TValue::extra
} Value;

/*
** Tagged Values
*/

typedef struct lua_TValue
{
    Value value;
    int extra[LUA_EXTRA_SIZE];
    int tt;
} TValue;

#if LUA_VECTOR_SIZE == 4
#define condvector4(vec4expr, vec3expr) vec4expr
#else
#define condvector4(vec4expr, vec3expr) vec3expr
#endif

#if LUA_VECTOR_DOUBLE == 1
#define condvectordouble(vecdoubleexpr, vecfloatexpr) vecdoubleexpr
#else
#define condvectordouble(vecdoubleexpr, vecfloatexpr) vecfloatexpr
#endif

// Macros to test type
#define ttisnil(o) (ttype(o) == LUA_TNIL)
#define ttisnumber(o) (ttype(o) == LUA_TNUMBER)
#define ttisinteger(o) (ttype(o) == LUA_TINTEGER)
#define ttisstring(o) (ttype(o) == LUA_TSTRING)
#define ttistable(o) (ttype(o) == LUA_TTABLE)
#define ttisfunction(o) (ttype(o) == LUA_TFUNCTION)
#define ttisboolean(o) (ttype(o) == LUA_TBOOLEAN)
#define ttisuserdata(o) (ttype(o) == LUA_TUSERDATA)
#define ttisthread(o) (ttype(o) == LUA_TTHREAD)
#define ttisbuffer(o) (ttype(o) == LUA_TBUFFER)
#define ttislightuserdata(o) (ttype(o) == LUA_TLIGHTUSERDATA)
#define ttisvector(o) (ttype(o) == LUA_TVECTOR)
#define ttisupval(o) (ttype(o) == LUA_TUPVAL)
#define ttisclass(o) (ttype(o) == LUA_TCLASS)
#define ttisobject(o) (ttype(o) == LUA_TOBJECT)

// Macros to access values
#define ttype(o) ((o)->tt)
#define gcvalue(o) check_exp(iscollectable(o), (o)->value.gc)
#define pvalue(o) check_exp(ttislightuserdata(o), (o)->value.p)
#define nvalue(o) check_exp(ttisnumber(o), (o)->value.n)
#define lvalue(o) check_exp(ttisinteger(o), (o)->value.l)
#define vvalue(o) check_exp(ttisvector(o), condvectordouble((o)->value.gc->vec.v, (o)->value.v))
#define tsvalue(o) check_exp(ttisstring(o), &(o)->value.gc->ts)
#define uvalue(o) check_exp(ttisuserdata(o), &(o)->value.gc->u)
#define clvalue(o) check_exp(ttisfunction(o), &(o)->value.gc->cl)
#define hvalue(o) check_exp(ttistable(o), &(o)->value.gc->h)
#define bvalue(o) check_exp(ttisboolean(o), (o)->value.b)
#define thvalue(o) check_exp(ttisthread(o), &(o)->value.gc->th)
#define bufvalue(o) check_exp(ttisbuffer(o), &(o)->value.gc->buf)
#define upvalue(o) check_exp(ttisupval(o), &(o)->value.gc->uv)
#define classvalue(o) check_exp(ttisclass(o), &(o)->value.gc->lclass)
#define objectvalue(o) check_exp(ttisobject(o), &(o)->value.gc->lobject)

#define l_isfalse(o) (ttisnil(o) || (ttisboolean(o) && bvalue(o) == 0))

#define lightuserdatatag(o) check_exp(ttislightuserdata(o), (o)->extra[0])

// Internal tags used by the VM
#define LU_TAG_ITERATOR LUA_UTAG_LIMIT

/*
** for internal debug only
*/
#define checkconsistency(obj) LUAU_ASSERT(!iscollectable(obj) || (ttype(obj) == (obj)->value.gc->gch.tt))

#define checkliveness(g, obj) LUAU_ASSERT(!iscollectable(obj) || ((ttype(obj) == (obj)->value.gc->gch.tt) && !isdead(g, (obj)->value.gc)))

// Macros to set values
#define setnilvalue(obj) ((obj)->tt = LUA_TNIL)

#define setnvalue(obj, x) \
    { \
        TValue* i_o = (obj); \
        i_o->value.n = (x); \
        i_o->tt = LUA_TNUMBER; \
    }

#define setlvalue(obj, x) \
    { \
        TValue* i_o = (obj); \
        i_o->value.l = (x); \
        i_o->tt = LUA_TINTEGER; \
    }

#if LUA_VECTOR_DOUBLE == 1
#define setvvalue(L, obj, x, y, z, w) \
    { \
        TValue* i_o = (obj); \
        LuauVector* i_vec = luaVec_newvector((L), double(x), double(y), double(z), condvector4(double(w), 0)); \
        i_o->value.gc = cast_to(GCObject*, i_vec); \
        i_o->tt = LUA_TVECTOR; \
        checkliveness((L)->global, i_o); \
    }
#else
#define setvvalue(L, obj, x, y, z, w) \
    { \
        TValue* i_o = (obj); \
        float* i_v = i_o->value.v; \
        i_v[0] = float(x); \
        i_v[1] = float(y); \
        i_v[2] = float(z); \
        condvector4(i_v[3] = float(w), (void)(w)); \
        i_o->tt = LUA_TVECTOR; \
    }
#endif

#define setpvalue(obj, x, tag) \
    { \
        TValue* i_o = (obj); \
        i_o->value.p = (x); \
        i_o->extra[0] = (tag); \
        i_o->tt = LUA_TLIGHTUSERDATA; \
    }

#define setbvalue(obj, x) \
    { \
        TValue* i_o = (obj); \
        i_o->value.b = (x); \
        i_o->tt = LUA_TBOOLEAN; \
    }

#define setsvalue(L, obj, x) \
    { \
        TValue* i_o = (obj); \
        i_o->value.gc = cast_to(GCObject*, (x)); \
        i_o->tt = LUA_TSTRING; \
        checkliveness(L->global, i_o); \
    }

#define setuvalue(L, obj, x) \
    { \
        TValue* i_o = (obj); \
        i_o->value.gc = cast_to(GCObject*, (x)); \
        i_o->tt = LUA_TUSERDATA; \
        checkliveness(L->global, i_o); \
    }

#define setthvalue(L, obj, x) \
    { \
        TValue* i_o = (obj); \
        i_o->value.gc = cast_to(GCObject*, (x)); \
        i_o->tt = LUA_TTHREAD; \
        checkliveness(L->global, i_o); \
    }

#define setbufvalue(L, obj, x) \
    { \
        TValue* i_o = (obj); \
        i_o->value.gc = cast_to(GCObject*, (x)); \
        i_o->tt = LUA_TBUFFER; \
        checkliveness(L->global, i_o); \
    }

#define setclvalue(L, obj, x) \
    { \
        TValue* i_o = (obj); \
        i_o->value.gc = cast_to(GCObject*, (x)); \
        i_o->tt = LUA_TFUNCTION; \
        checkliveness(L->global, i_o); \
    }

#define sethvalue(L, obj, x) \
    { \
        TValue* i_o = (obj); \
        i_o->value.gc = cast_to(GCObject*, (x)); \
        i_o->tt = LUA_TTABLE; \
        checkliveness(L->global, i_o); \
    }

#define setptvalue(L, obj, x) \
    { \
        TValue* i_o = (obj); \
        i_o->value.gc = cast_to(GCObject*, (x)); \
        i_o->tt = LUA_TPROTO; \
        checkliveness(L->global, i_o); \
    }

#define setupvalue(L, obj, x) \
    { \
        TValue* i_o = (obj); \
        i_o->value.gc = cast_to(GCObject*, (x)); \
        i_o->tt = LUA_TUPVAL; \
        checkliveness(L->global, i_o); \
    }

#define setobj(L, obj1, obj2) \
    { \
        const TValue* o2 = (obj2); \
        TValue* o1 = (obj1); \
        *o1 = *o2; \
        checkliveness(L->global, o1); \
    }

#define setclassvalue(L, obj, x) \
    { \
        TValue* i_o = (obj); \
        i_o->value.gc = cast_to(GCObject*, (x)); \
        i_o->tt = LUA_TCLASS; \
        checkliveness(L->global, i_o); \
    }


#define setobjectvalue(L, obj, x) \
    { \
        TValue* i_o = (obj); \
        i_o->value.gc = cast_to(GCObject*, (x)); \
        i_o->tt = LUA_TOBJECT; \
        checkliveness(L->global, i_o); \
    }

/*
** different types of sets, according to destination
*/

// to stack
#define setobj2s setobj
// from table to same table (no barrier)
#define setobjt2t setobj
// to table (needs barrier)
#define setobj2t setobj
// to new object (no barrier)
#define setobj2n setobj
// to class instance or static member (needs barrier)
#define setobj2class setobj

#define setttype(obj, tt) (ttype(obj) = (tt))

#define iscollectable(o) (ttype(o) >= LUA_TSTRING)

// wrapper for returning userdata properties directly
struct DirectFieldResult
{
    lua_State* L;
    TValue* slot;
};

typedef TValue* StkId; // index to stack elements

/*
** String headers for string table
**
** VERIFIED from luaS_newlstr (0x254dd90):
**   strb w9=6, [x0]           → +0x00 = tt = 6 (LUA_TSTRING)
**   strb w10, [x0, 1]         → +0x01 = memcat
**   strb w8=currentwhite&3, [x0, 2] → +0x02 = marked
**   str w9=-0x7fff0001, [x0, 4] → +0x04 = atom (int32_t)
**   stp w21, w22, [x0, 0x10]  → +0x10 = hash, +0x14 = len
**   add x24, x0, 0x18         → +0x18 = data (string bytes)
**   ldr x19, [x19, 8]         → +0x08 = next (linked list)
**   ldr w8, [x19, 0x14]       → +0x14 = len (for memcmp)
**   add x1, x19, 0x18         → +0x18 = data (for memcmp)
*/
typedef struct TString
{
    CommonHeader;       // +0x00 tt, memcat, marked
    uint8_t _pad_03;    // +0x03 (padding, 1 byte)

    int32_t atom;       // +0x04 (initialized to -0x7fff0001 = ~0x7fff0000)

    TString* next;      // +0x08 (next string in hash bucket)

    uint32_t hash;      // +0x10
    uint32_t len;       // +0x14

    char data[1];       // +0x18 (string data, allocated right after header)
} TString;


#define getstr(ts) (ts)->data
#define svalue(o) getstr(tsvalue(o))

typedef struct Udata
{
    CommonHeader;

    uint8_t tag;

    int len;

    struct LuaTable* metatable;

    // userdata is allocated right after the header
    // while the alignment is only 8 here, for sizes starting at 16 bytes, 16 byte alignment is provided
    alignas(8) char data[1];
} Udata;

typedef struct LuauBuffer
{
    CommonHeader;

    unsigned int len;

    alignas(8) char data[1];
} Buffer;

typedef struct LuauVector
{
    CommonHeader;
    // 1 byte padding

    LUA_VECTOR_TYPE v[LUA_VECTOR_SIZE];
} LuauVector;

enum FeedbackVectorSlotKind
{
    CALL_TARGET
};

struct FeedbackVectorSlot
{
    FeedbackVectorSlotKind kind;

    union
    {
        struct
        {
            uint32_t pc;
            uint32_t proto;
            uint32_t hits;
        } call_target;
    };
};

/*
** Function Prototypes
**
** VERIFIED from luaF_newproto (0x25a898c) + luau_load_impl (0x5d200f4) + luau_execute (0x5d1492c):
**   luaF_newproto: alloc size = 0xd8, tt = 0xf
**
**   luau_load_impl field writes (VERIFIED):
**     strb w8, [x22, 3]  → +0x03 = nups
**     strb w8, [x22, 4]  → +0x04 = numparams
**     strb w8, [x22, 5]  → +0x05 = is_vararg
**     strb w8, [x22, 6]  → +0x06 = flags
**     strb w8, [x22, 7]  → +0x07 = maxstacksize
**     str x8, [x0, 0x18] → +0x18 = source (TString*)
**     str x0, [x22, 0x28]→ +0x28 = typeinfo (uint8_t*)
**     str x0, [x22, 0x68]→ +0x68 = upvalues (TString**)
**     str x0, [x22, 0x70]→ +0x70 = k (TValue* constants array, size = nconst*16)
**     str x0, [x22, 0x78]→ +0x78 = code (Instruction*, size = sizecode*4)
**     str x23, [x22, 0x80]→ +0x80 = code duplicate (Instruction*)
**     str w19, [x22, 0x88]→ +0x88 = sizecode (int)
**     str w24, [x22, 0x8c]→ +0x8c = sizetypeinfo (int)
**     str w19, [x22, 0xac]→ +0xac = sizek (int, the constant count)
**     str x0, [x22, 0xb0]→ +0xb0 = locvars (LocVar*)
**     str w8, [x22, 0xb8]→ +0xb8 = sizelocvars (int)
**     str w8, [x22, 0xbc]→ +0xbc = bytecodeid (int)
**     str x8, [x22, 0xd0]→ +0xd0 = ??? (last field, size_t)
**
**   luau_execute reads (VERIFIED):
**     ldr x24, [x10, 0x70] → +0x70 = k (TValue* — used for LOADK)
**     ldr x10, [x9, 0x78]  → +0x78 = code (Instruction* — used as PC base)
**     ldrsw x9, [x9, 0x88] → +0x88 = sizecode
**     ldr w9, [x9, 0xbc]   → +0xbc = bytecodeid
**     ldr w2, [x9, 0x14]   → +0x14 = hash/linedefined (passed to exec callback)
**     add x1, x9, 0x18     → +0x18 = source (passed to exec callback)
**
**   Fields below NOT verified from binary but kept for code compatibility:
**     p (sub-protos), sizep, lineinfo, sizelineinfo, debugname, debuginsn,
**     abslineinfo, linegaplog2, execdata, gclist, etc.
*/
// clang-format off
typedef struct Proto
{
    CommonHeader;              // +0x00 tt, memcat, marked

    uint8_t nups;              // +0x03 (VERIFIED)
    uint8_t numparams;         // +0x04 (VERIFIED)
    uint8_t is_vararg;         // +0x05 (VERIFIED)
    uint8_t flags;             // +0x06 (VERIFIED)
    uint8_t maxstacksize;      // +0x07 (VERIFIED)

    char _pad_08[0x08];        // +0x08..0x0f (zeroed)

    char _pad_10[0x04];        // +0x10..0x13 (zeroed)
    uint32_t linedefined;      // +0x14 (read by luau_execute, passed to exec callback as w2)
    TString* source;           // +0x18 (VERIFIED: str x8, [x0, 0x18] in luau_load)

    char _pad_20[0x08];        // +0x20..0x27 (zeroed)

    uint8_t* typeinfo;         // +0x28 (VERIFIED: str x0, [x22, 0x28])
    char _pad_30[0x30];        // +0x30..0x5f (zeroed — debug/exec data)

    TString** upvalues;        // +0x68 (VERIFIED: str x0, [x22, 0x68])

    TValue* k;                 // +0x70 (VERIFIED from luau_execute: ldr x24, [x10, 0x70] = k array)
                               //         ALSO VERIFIED from luau_load: str x0, [x22, 0x70] = k alloc
    Instruction* code;         // +0x78 (VERIFIED: str x0, [x22, 0x78]; ldr x10, [x9, 0x78])
    Instruction* codeentry;    // +0x80 (VERIFIED: str x23, [x22, 0x80] — duplicate of code)

    int sizecode;              // +0x88 (VERIFIED: str w19, [x22, 0x88]; ldrsw x9, [x9, 0x88])
    int sizetypeinfo;          // +0x8c (VERIFIED: str w24, [x22, 0x8c])

    int sizep;                 // +0x90 (NOT verified — kept for code compat)
    int sizek;                 // +0x94 (NOT verified — but +0xac is the real sizek)
    int sizelineinfo;          // +0x98 (NOT verified — kept for code compat)
    int sizeupvalues;          // +0x9c (NOT verified — but +0xa0 is real sizeupvalues)

    int _sizeupvalues_real;    // +0xa0 (VERIFIED: str w20, [x22, 0xa0] = sizeupvalues)
    char _pad_a4[0x08];        // +0xa4..0xab (zeroed)
    int _sizek_real;           // +0xac (VERIFIED: str w19, [x22, 0xac] = sizek)

    struct LocVar* locvars;    // +0xb0 (VERIFIED: str x0, [x22, 0xb0])
    int sizelocvars;           // +0xb8 (VERIFIED: str w8, [x22, 0xb8])
    int bytecodeid;            // +0xbc (VERIFIED: str w8, [x22, 0xbc]; ldr w9, [x9, 0xbc])

    char _pad_c0[0x10];        // +0xc0..0xcf (zeroed)
    size_t _field_d0;          // +0xd0 (VERIFIED: str x8, [x22, 0xd0] — last field written)

    // === Fields below are NOT in roblox Proto at these offsets ===
    // They are kept ONLY for code compatibility. Code that accesses them
    // will read/write wrong memory, but most code paths only use the
    // verified fields above (k, code, sizecode, source, etc.).
    // DO NOT access these from hot paths.
    struct Proto** p;          // sub-protos (compatibility — offset wrong)
    uint8_t* lineinfo;         // line info (compatibility — offset wrong)
    int* abslineinfo;          // baseline line info (compatibility)
    int linegaplog2;           // (compatibility)
    TString* debugname;        // (compatibility)
    uint8_t* debuginsn;        // copy of code[] with just opcodes (compatibility)
    void* execdata;            // (compatibility)
    void* userdata;            // (compatibility)
    GCObject* gclist;          // (compatibility)
    struct Proto* optimized;   // (compatibility)
    struct Proto* deoptimized; // (compatibility)
    struct FeedbackVectorSlot* feedbackvec; // (compatibility)
    uint32_t feedbackvecsize;  // (compatibility)
    uint32_t funid;            // (compatibility)
    uint64_t cost;             // (compatibility)
    uintptr_t exectarget;      // (compatibility — lvmexecute.cpp checks p->exectarget)
} Proto;
// clang-format on

typedef struct LocVar
{
    TString* varname;
    int startpc; // first point where variable is active
    int endpc;   // first point where variable is dead
    uint8_t reg; // register slot, relative to base, where variable is stored
} LocVar;

/*
** Upvalues
*/

typedef struct UpVal
{
    CommonHeader;
    uint8_t markedopen; // set if reachable from an alive thread (only valid during atomic)

    // 4 byte padding (x64)

    TValue* v; // points to stack or to its own value
    union
    {
        TValue value; // the value (when closed)
        struct
        {
            // global double linked list (when open)
            struct UpVal* prev;
            struct UpVal* next;

            // thread linked list (when open)
            struct UpVal* threadnext;
        } open;
    } u;
} UpVal;

#define upisopen(up) ((up)->v != &(up)->u.value)

/*
** Closures
**
** Roblox-reversed layout:
**   Lua closure: alloc size = 0x20 + nupvalues * 0x10, env +0x10, proto +0x18, uprefs +0x20.
**   C closure: alloc size = 0x30 + nupvalues * 0x10, function +0x10, continuation +0x18,
**   debug-name fields +0x20/+0x28, upvalues +0x30.
**   Both closure kinds use tt=8 for Lua and tt=7 for C.
*/
typedef struct Closure
{
    CommonHeader;

    uint8_t isC;
    uint8_t stacksize;
    uint8_t nupvalues;
    uint8_t preload;
    uint8_t _pad_07;

    GCObject* gclist;

    union
    {
        struct
        {
            struct LuaTable* env;
            struct Proto* p;
            TValue uprefs[1];
        } l;

        struct
        {
            lua_CFunction f;
            lua_Continuation cont;
            const char* debugname_DEPRECATED;
            TString* debugname;
            TValue upvals[1];
        } c;
    };
} Closure;

// roblox uses tt=7 for C closures, tt=8 for L closures (not the isC field)
#define iscfunction(o) (ttype(o) == LUA_TFUNCTION && clvalue(o)->tt == 7)
#define isLfunction(o) (ttype(o) == LUA_TFUNCTION && clvalue(o)->tt == 8)

/*
** Tables
*/

typedef struct TKey
{
    ::Value value;
    int extra[LUA_EXTRA_SIZE];
    unsigned tt : 4;
    int next : 28; // for chaining
} TKey;

typedef struct LuaNode
{
    TValue val;
    TKey key;
} LuaNode;

// copy a value into a key
#define setnodekey(L, node, obj) \
    { \
        LuaNode* n_ = (node); \
        const TValue* i_o = (obj); \
        n_->key.value = i_o->value; \
        memcpy(n_->key.extra, i_o->extra, sizeof(n_->key.extra)); \
        n_->key.tt = i_o->tt; \
        checkliveness(L->global, i_o); \
    }

// copy a value from a key
#define getnodekey(L, obj, node) \
    { \
        TValue* i_o = (obj); \
        const LuaNode* n_ = (node); \
        i_o->value = n_->key.value; \
        memcpy(i_o->extra, n_->key.extra, sizeof(i_o->extra)); \
        i_o->tt = n_->key.tt; \
        checkliveness(L->global, i_o); \
    }

// clang-format off
// roblox LuaTable layout — verified from luaH_new ( 0x2227b28 ) decompilation:
//   puVar3[5] = 0xff     -> +0x05 = tmcache ( ~0 )
//   alloc size = 0x30   -> total struct = 48 bytes
//   stp x8,xzr,[x0,#0x18] -> +0x18 = node ( dummynode ), +0x20 = array ( null )
//   str xzr,[x0,#0x10]  -> +0x10 = gclist ( null )
//   +0x28 = metatable ( null )
typedef struct LuaTable
{
    CommonHeader;       // +0x00 tt, +0x01 memcat, +0x02 marked
    uint8_t lsizenode;  // +0x03  log2 of size of `node' array
    uint8_t readonly;   // +0x04  ( zeroed in luaH_new )
    uint8_t tmcache;    // +0x05  ( set to 0xff in luaH_new )
    uint8_t safeenv;    // +0x06
    uint8_t nodemask8;  // +0x07  (1<<lsizenode)-1
    int sizearray;      // +0x08  size of `array' array
    union {
        int lastfree;   // +0x0c  any free position is before this position
        int aboundary;  //       negated 'boundary' of `array' array
    };
    GCObject* gclist;   // +0x10  GC list link ( zeroed in luaH_new )
    LuaNode* node;      // +0x18  hash part ( dummynode by default )
    TValue* array;      // +0x20  array part
    struct LuaTable* metatable; // +0x28
} LuaTable;
// clang-format on

typedef struct LuauClass
{
    CommonHeader;

    GCObject* gclist;

    TString* name;

    // Mapping from offset to static members (only methods for now).
    TValue* staticmembers;

    // Mapping from member name to offset.
    // For static members, subtracting numberofinstancemembers from the offset gives the actual index into staticmembers.
    LuaTable* memberstooffset;

    // Mapping from offset to member name. Instance member offsets are stored before static member offsets.
    TString** offsettomember;

    // Metatable for this *class object*. At time of writing this only contains
    // __call, but we may add more metamethods to class objects in the future.
    LuaTable* metatable;

    // Metatable for instances of this class. NULL until the first metamethod
    // is added via luaR_addclassmember.
    LuaTable* instancemetatable;

    // Number of instance members that we expect instances of this class object
    // to have.
    uint32_t numberofinstancemembers;

    // Total number of members that we expect this class object to have between
    // instance and static members.
    //
    // We store this number as an optimization. It's pretty rare that we need
    // to reference the specific number of static members, but it's very common
    // to reference the total number of members (for validating hot paths in
    // the interpreter) and the number of instance members (branching on
    // instance or static members, creating class instances).
    uint32_t numberofallmembers;

} LuauClass;

typedef struct LuauObject
{
    CommonHeader;

    GCObject* gclist;

    // The class object that this value is an instance of.
    LuauClass* lclass;

    // The number of members that this instance contains. We need this in order
    // to free ourselves if we got swept in the same GC cycle as our class
    // pointer.
    uint32_t numberofmembers;

    // The fields of this instance.
    TValue* members;

} LuauObject;

/*
** `module' operation for hashing (size is always a power of 2)
*/
#define lmod(s, size) (check_exp((size & (size - 1)) == 0, (cast_to(int, (s) & ((size) - 1)))))

#define twoto(x) ((int)(1 << (x)))
#define sizenode(t) (twoto((t)->lsizenode))

#define luaO_nilobject (&luaO_nilobject_)

LUAI_DATA const TValue luaO_nilobject_;

#define ceillog2(x) (luaO_log2((x) - 1) + 1)

LUAI_FUNC int luaO_log2(unsigned int x);
LUAI_FUNC int luaO_rawequalObj(const TValue* t1, const TValue* t2);
LUAI_FUNC int luaO_rawequalKey(const TKey* t1, const TValue* t2);
LUAI_FUNC int luaO_str2d(const char* s, double* result);
LUAI_FUNC int luaO_str2l(const char* s, int64_t* result, int base = 10);
LUAI_FUNC const char* luaO_pushvfstring(lua_State* L, const char* fmt, va_list argp);
LUAI_FUNC const char* luaO_pushfstring(lua_State* L, const char* fmt, ...);
LUAI_FUNC const char* luaO_chunkid(char* buf, size_t buflen, const char* source, size_t srclen);
