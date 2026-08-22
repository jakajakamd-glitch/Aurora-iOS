#import "core.hpp"
#import "../roblox/Roblox.hpp"
#import "../roblox/environment.hpp"
#import "../functions/function_mgr.hpp"
#import "../utility/utility_mgr.hpp"
#import <Foundation/Foundation.h>
#include <cstdint>
#include <atomic>
#include <cstring>
#include <string>
#include <unordered_set>
#include <vector>
#include "lua.h"
#include "lualib.h"
#include "lmem.h"
#include "lobject.h"
#include "lstate.h"
#include "lfunc.h"
#include "lgc.h"
#include "startscript.hpp"
#include "hookmetamethod.hpp"
#include "Luau/Compiler.h"

namespace managers::core {

namespace {

static uint8_t genv_key;
static constexpr uintptr_t actor_global_state_offset = 0x1c8;

struct proto_view {
    uint8_t unknown_00[0x20];
    proto_view** child_protos;
    uint8_t unknown_28[0x10];
    void* capabilities;
    uint8_t unknown_40[0x68];
    uint32_t child_proto_count;
};

struct closure_view {
    uint8_t unknown_00[0x18];
    proto_view* proto;
};

void set_proto_caps(lua_State* l, void* capability_table) {
    if (!l || !capability_table || lua_type(l, -1) != LUA_TFUNCTION) {
        return;
    }

    const void* object = lua_topointer(l, -1);
    if (!object) {
        return;
    }

    closure_view* closure = const_cast<closure_view*>(reinterpret_cast<const closure_view*>(object));
    proto_view* root = closure->proto;
    if (!root || (!root->child_protos && root->child_proto_count != 0)) {
        return;
    }

    root->capabilities = capability_table;
    for (uint32_t i = 0; i < root->child_proto_count; ++i) {
        if (root->child_protos[i]) {
            root->child_protos[i]->capabilities = capability_table;
        }
    }
}

lua_State* actor_global_state(lua_State* L) {
    void* actor = lua_touserdata(L, 1);
    if (!actor) {
        actor = const_cast<void*>(lua_topointer(L, 1));
    }
    if (!actor) {
        return nullptr;
    }

    return *reinterpret_cast<lua_State**>(reinterpret_cast<uint8_t*>(actor) + actor_global_state_offset);
}

lua_State* find_script_thread(lua_State* state, void* script) {
    if (!state || !state->global || !script) {
        return nullptr;
    }

    for (lua_Page* page = state->global->allgcopages; page; page = luaM_getnextpage(page)) {
        char* start = nullptr;
        char* end = nullptr;
        int busy_blocks = 0;
        int block_size = 0;
        luaM_getpagewalkinfo(page, &start, &end, &busy_blocks, &block_size);
        for (char* position = start; position != end; position += block_size) {
            GCObject* object = (GCObject*)position;
            if (object->gch.tt != LUA_TTHREAD) {
                continue;
            }
            lua_State* candidate = &object->th;
            if (candidate->global != state->global || !candidate->userdata) {
                continue;
            }
            if (*(void**)((uintptr_t)candidate->userdata + 0x40) == script) {
                return candidate;
            }
        }
    }
    return nullptr;
}


static uint8_t original_map_key;
static uint8_t wrapper_map_key;


}

std::int32_t getsenv(lua_State* L) {
    int type = lua_type(L, 1);
    if (type != LUA_TUSERDATA && type != LUA_TLIGHTUSERDATA) {
        luaL_typeerrorL(L, 1, OBF("Script"));
        return 0;
    }

    void* script = const_cast<void*>(lua_topointer(L, 1));
    lua_State* current = lua_mainthread(L);
    if (!script || !current || !current->global) {
        lua_pushstring(L, OBF("script is not currently running"));
        lua_error(L);
        return 0;
    }

    lua_State* found = find_script_thread(current, script);
    bool foreign = false;
    if (!found && roblox_manager.scriptctx) {
        uintptr_t context = (uintptr_t)roblox_manager.scriptctx;
        for (size_t state_index = 0; state_index < 2 && !found; ++state_index) {
            uintptr_t state_entry = context + 0x130 + 0x18 + state_index * 0x210;
            uintptr_t handle = state_entry + 0x1e8;
            uint64_t low = (uint32_t)handle - *(uint32_t*)handle;
            uint64_t high = (uint32_t)(handle >> 32) - *(uint32_t*)(handle + 4);
            lua_State* alternate = (lua_State*)(low | (high << 32));
            if (!alternate || !alternate->global || alternate->global == current->global) {
                continue;
            }
            if (find_script_thread(alternate, script)) {
                foreign = true;
            }
        }
    }

    if (foreign) {
        lua_pushnil(L);
        return 1;
    }
    if (!found) {
        lua_pushstring(L, OBF("script is not currently running"));
        lua_error(L);
        return 0;
    }

    lua_pushvalue(found, LUA_GLOBALSINDEX);
    lua_xmove(found, L, 1);
    return 1;
}

std::int32_t getrenv(lua_State* L) {
    lua_State* main = lua_mainthread(L);
    if (!main) {
        lua_pushnil(L);
        return 1;
    }
    lua_pushvalue(main, LUA_GLOBALSINDEX);
    lua_xmove(main, L, 1);
    return 1;
}

std::int32_t getgenv(lua_State* L) {
    lua_State* main = lua_mainthread(L);
    if (!main) {
        lua_pushnil(L);
        return 1;
    }

    lua_rawgetp(main, LUA_REGISTRYINDEX, &genv_key);
    if (lua_istable(main, -1)) {
        lua_xmove(main, L, 1);
        return 1;
    }

    lua_pop(main, 1);
    lua_newtable(main);
    lua_pushvalue(main, -1);
    lua_rawsetp(main, LUA_REGISTRYINDEX, &genv_key);
    lua_xmove(main, L, 1);
    return 1;
}

std::int32_t loadstring(lua_State* L) {
    size_t source_size = 0;
    const char* source = luaL_checklstring(L, 1, &source_size);
    const char* chunkname = luaL_optstring(L, 2, OBF("=loadstring"));
    int base = lua_gettop(L);
    int status = roblox_manager.execute_script(source,
                                                source_size,
                                                chunkname,
                                                L,
                                                nullptr,
                                                execution_loadstring);
    if (status != 0) {
        lua_settop(L, base);
        lua_pushnil(L);
        lua_pushfstring(L, OBF("loadstring failed with status %d"), status);
        return 2;
    }
    return 1;
}

std::int32_t clonefunction(lua_State* L) {
    if (lua_type(L, 1) != LUA_TFUNCTION) {
        luaL_typeerrorL(L, 1, OBF("function"));
        return 0;
    }

    Closure* original = reinterpret_cast<Closure*>(const_cast<void*>(lua_topointer(L, 1)));
    if (!original) {
        luaL_error(L, OBF("invalid function"));
        return 0;
    }

    if (!lua_iscfunction(L, 1)) {
        luaC_checkGC(L);
        luaC_threadbarrier(L);
        Closure* clone = luaF_newLclosure(L, original->nupvalues, original->l.env, original->l.p);
        for (int index = 0; index < original->nupvalues; ++index) {
            setobj2n(L, &clone->l.uprefs[index], &original->l.uprefs[index]);
        }
        setclvalue(L, L->top, clone);
        ++L->top;
        return 1;
    }
    if (!original || !original->c.f) {
        lua_pushstring(L, OBF("invalid c closure"));
        lua_error(L);
        return 0;
    }

    int upvalue_count = original->nupvalues;
    for (int index = 1; index <= upvalue_count; ++index) {
        if (!lua_getupvalue(L, 1, index)) {
            lua_pushstring(L, OBF("unable to clone c closure upvalues"));
            lua_error(L);
            return 0;
        }
    }

    lua_pushcclosurek(L, original->c.f, nullptr, upvalue_count, original->c.cont);
    return 1;
}


std::int32_t getinstances(lua_State* L) {
    lua_newtable(L);
    int result_index = lua_gettop(L);
    if (!L || !L->global) {
        return 1;
    }

    std::unordered_set<void*> seen;
    int result_count = 0;
    auto is_instance_value = [L](int index) {
        if (!lua_isuserdata(L, index)) {
            return false;
        }
        int tag = lua_userdatatag(L, index);
        const char* name = lua_getuserdataname(L, tag);
        return name && std::strcmp(name, OBF("Instance")) == 0;
    };
    auto append_instance = [&seen, &result_count, result_index, L](int index) {
        void* identity = const_cast<void*>(lua_topointer(L, index));
        if (!identity || !seen.insert(identity).second) {
            return;
        }
        lua_pushvalue(L, index);
        lua_rawseti(L, result_index, ++result_count);
    };

    lua_pushnil(L);
    while (lua_next(L, LUA_REGISTRYINDEX) != 0) {
        if (lua_istable(L, -1)) {
            int held_table = lua_absindex(L, -1);
            lua_pushnil(L);
            while (lua_next(L, held_table) != 0) {
                if (is_instance_value(-1)) {
                    append_instance(-1);
                }
                lua_pop(L, 1);
            }
        }
        lua_pop(L, 1);
    }

    for (lua_Page* page = L->global->allgcopages; page; page = luaM_getnextpage(page)) {
        char* start = nullptr;
        char* end = nullptr;
        int busy_blocks = 0;
        int block_size = 0;
        luaM_getpagewalkinfo(page, &start, &end, &busy_blocks, &block_size);
        if (!start || !end || block_size <= 0) {
            continue;
        }
        for (char* position = start; position != end; position += block_size) {
            GCObject* object = reinterpret_cast<GCObject*>(position);
            if (!object || object->gch.tt != LUA_TUSERDATA) {
                continue;
            }
            Udata* userdata = &object->u;
            const char* userdata_name = lua_getuserdataname(L, userdata->tag);
            if (userdata->len < 16 || !userdata_name || std::strcmp(userdata_name, OBF("Instance")) != 0) {
                continue;
            }
            void* instance = *reinterpret_cast<void**>(userdata->data);
            void* control = *reinterpret_cast<void**>(userdata->data + sizeof(void*));
            if (!instance || !control || !seen.insert(instance).second) {
                continue;
            }
            __atomic_add_fetch(reinterpret_cast<uint64_t*>(control) + 1, 1, __ATOMIC_RELAXED);
            void* copy = lua_newuserdatataggedwithmetatable(L, 16, userdata->tag);
            std::memcpy(copy, userdata->data, 16);
            lua_rawseti(L, result_index, ++result_count);
        }
    }
    return 1;
}

std::int32_t hookfunction(lua_State* L) {
    if (lua_type(L, 1) != LUA_TFUNCTION) {
        luaL_typeerrorL(L, 1, OBF("function"));
        return 0;
    }
    if (lua_type(L, 2) != LUA_TFUNCTION) {
        luaL_typeerrorL(L, 2, OBF("function"));
        return 0;
    }

    Closure* target = reinterpret_cast<Closure*>(const_cast<void*>(lua_topointer(L, 1)));
    Closure* hook = reinterpret_cast<Closure*>(const_cast<void*>(lua_topointer(L, 2)));
    if (!target || !hook) {
        luaL_error(L, OBF("invalid function"));
        return 0;
    }
    if (hook->nupvalues > target->nupvalues) {
        luaL_error(L, OBF("hook has more upvalues than target"));
        return 0;
    }

    int original_index;
    lua_rawgetp(L, LUA_REGISTRYINDEX, &original_map_key);
    if (lua_istable(L, -1)) {
        int map_index = lua_gettop(L);
        lua_rawgetptagged(L, map_index, target, 0);
        lua_remove(L, map_index);
        if (lua_type(L, -1) == LUA_TFUNCTION) {
            original_index = lua_gettop(L);
        } else {
            lua_pop(L, 1);
            original_index = 0;
        }
    } else {
        lua_pop(L, 1);
        original_index = 0;
    }

    if (original_index == 0) {
        if (target->tt == 7) {
            for (int index = 0; index < target->nupvalues; ++index) {
                setobj2s(L, L->top, &target->c.upvals[index]);
                ++L->top;
            }
            lua_pushcclosurek(L, target->c.f, nullptr, target->nupvalues, target->c.cont);
        } else {
            luaC_checkGC(L);
            luaC_threadbarrier(L);
            Closure* clone = luaF_newLclosure(L, target->nupvalues, target->l.env, target->l.p);
            for (int index = 0; index < target->nupvalues; ++index) {
                setobj2n(L, &clone->l.uprefs[index], &target->l.uprefs[index]);
            }
            setclvalue(L, L->top, clone);
            ++L->top;
        }
        original_index = lua_gettop(L);
        lua_rawgetp(L, LUA_REGISTRYINDEX, &original_map_key);
        if (!lua_istable(L, -1)) {
            lua_pop(L, 1);
            lua_newtable(L);
            lua_pushvalue(L, -1);
            lua_rawsetp(L, LUA_REGISTRYINDEX, &original_map_key);
        }
        int map_index = lua_gettop(L);
        lua_pushvalue(L, original_index);
        lua_rawsetptagged(L, map_index, target, 0);
        lua_remove(L, map_index);
    }

    if (target->tt == 7 && hook->tt == 7) {
        target->c.f = hook->c.f;
        target->c.cont = hook->c.cont;
        target->nupvalues = hook->nupvalues;
        target->stacksize = hook->stacksize;
        for (int index = 0; index < hook->nupvalues; ++index) {
            setobj2n(L, &target->c.upvals[index], &hook->c.upvals[index]);
        }
    } else if (target->tt == 8 && hook->tt == 8) {
        target->l.env = hook->l.env;
        target->l.p = hook->l.p;
        target->nupvalues = hook->nupvalues;
        target->stacksize = hook->stacksize;
        for (int index = 0; index < hook->nupvalues; ++index) {
            setobj2n(L, &target->l.uprefs[index], &hook->l.uprefs[index]);
        }
        luaC_objbarrier(L, target, target->l.env);
        luaC_objbarrier(L, target, target->l.p);
    } else if (target->tt == 7) {
        target->tt = 8;
        target->isC = 0;
        target->l.env = hook->l.env;
        target->l.p = hook->l.p;
        target->nupvalues = hook->nupvalues;
        target->stacksize = hook->stacksize;
        for (int index = 0; index < hook->nupvalues; ++index) {
            setobj2n(L, &target->l.uprefs[index], &hook->l.uprefs[index]);
        }
        luaC_objbarrier(L, target, target->l.env);
        luaC_objbarrier(L, target, target->l.p);
    } else {
        target->tt = 7;
        target->isC = 1;
        target->c.f = hook->c.f;
        target->c.cont = hook->c.cont;
        target->nupvalues = hook->nupvalues;
        target->stacksize = hook->stacksize;
        for (int index = 0; index < hook->nupvalues; ++index) {
            setobj2n(L, &target->c.upvals[index], &hook->c.upvals[index]);
        }
    }
    return 1;
}

std::int32_t newcclosure(lua_State* L) {
    if (lua_type(L, 1) != LUA_TFUNCTION) {
        luaL_typeerrorL(L, 1, OBF("function"));
        return 0;
    }
    lua_pushcclosurek(L, [](lua_State* state) -> int {
        lua_Debug debug{};
        int before = lua_gettop(state);
        if (!lua_getinfo(state, 0, OBF("f"), &debug) || lua_gettop(state) != before + 1) {
            lua_settop(state, before);
            luaL_error(state, OBF("newcclosure target is unavailable"));
            return 0;
        }
        Closure* wrapper = reinterpret_cast<Closure*>(const_cast<void*>(lua_topointer(state, -1)));
        lua_pop(state, 1);
        lua_rawgetp(state, LUA_REGISTRYINDEX, &wrapper_map_key);
        if (!lua_istable(state, -1)) {
            lua_pop(state, 1);
            luaL_error(state, OBF("newcclosure target is unavailable"));
            return 0;
        }
        int map_index = lua_gettop(state);
        lua_rawgetptagged(state, map_index, wrapper, 0);
        lua_remove(state, map_index);
        if (lua_type(state, -1) != LUA_TFUNCTION) {
            luaL_error(state, OBF("newcclosure target is unavailable"));
            return 0;
        }
        lua_insert(state, 1);
        return luaL_callyieldable(state, lua_gettop(state) - 1, LUA_MULTRET);
    }, OBF("newcclosure"), 0, [](lua_State* state, int status) -> int {
        if (status != LUA_OK) {
            lua_error(state);
            return 0;
        }
        return lua_gettop(state);
    });
    Closure* wrapper = reinterpret_cast<Closure*>(const_cast<void*>(lua_topointer(L, -1)));
    lua_rawgetp(L, LUA_REGISTRYINDEX, &wrapper_map_key);
    if (!lua_istable(L, -1)) {
        lua_pop(L, 1);
        lua_newtable(L);
        lua_pushvalue(L, -1);
        lua_rawsetp(L, LUA_REGISTRYINDEX, &wrapper_map_key);
    }
    int map_index = lua_gettop(L);
    lua_pushvalue(L, 1);
    lua_rawsetptagged(L, map_index, wrapper, 0);
    lua_remove(L, map_index);
    return 1;
}

std::int32_t run_on_actor(lua_State* L) {
    size_t source_size = 0;
    const char* source = luaL_checklstring(L, 2, &source_size);
    if (lua_type(L, 1) != LUA_TUSERDATA && lua_type(L, 1) != LUA_TLIGHTUSERDATA) {
        luaL_typeerrorL(L, 1, OBF("Actor"));
        return 0;
    }

    lua_State* actor_state = actor_global_state(L);
    if (!actor_state || !actor_state->global) {
        lua_pushstring(L, OBF("actor global state is unavailable"));
        lua_error(L);
        return 0;
    }

    script_context* context = roblox_manager.scriptctx;
    if (!context) {
        context = *(script_context**)((uintptr_t)actor_state->global + 0x4e0);
    }
    if (!context) {
        lua_pushstring(L, OBF("actor execution context is unavailable"));
        lua_error(L);
        return 0;
    }

    int status = roblox_manager.execute_script(source,
                                                source_size,
                                                OBF("=run_on_actor"),
                                                actor_state,
                                                context,
                                                execution_actor);
    if (status != 0) {
        lua_pushfstring(L, OBF("actor execution failed with status %d"), status);
        lua_error(L);
        return 0;
    }

    return 0;
}

void on_game_loaded(void* sender, void* data) {
    static std::atomic<uint32_t> fire_count{0};
    uint32_t current_fire = fire_count.fetch_add(1, std::memory_order_relaxed) + 1;
    if (current_fire != 2) {
        return;
    }

;
    const char* hook_source = hookmetamethod_script;
    int hook_status = roblox_manager.execute_script(hook_source,
                                                     strlen(hook_source),
                                                     OBF("=hookmetamethod"),
                                                     nullptr,
                                                     nullptr,
                                                     execution_hookmetamethod);
    if (hook_status != 0) {
        utility::utility_mgr.log([[NSString stringWithFormat:OBF_NS("hookmetamethod execution failed status=%d sender=%p data=%p"), hook_status, sender, data] UTF8String]);
    }

    const char* source = startup_script();
    int status = roblox_manager.execute_script(source,
                                                strlen(source),
                                                OBF("=ongameloaded"),
                                                nullptr,
                                                nullptr,
                                                execution_normal);
    if (status != 0) {
        utility::utility_mgr.log([[NSString stringWithFormat:OBF_NS("onGameLoaded execution failed status=%d sender=%p data=%p"), status, sender, data] UTF8String]);
    }
}

}
