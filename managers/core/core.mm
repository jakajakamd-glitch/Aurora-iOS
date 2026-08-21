#import "core.hpp"
#import "../roblox/Roblox.hpp"
#import "../roblox/environment.hpp"
#import "../functions/function_mgr.hpp"
#include <cstdint>
#include <string>
#include "lua.h"
#include "lualib.h"
#include "lmem.h"
#include "lobject.h"
#include "lstate.h"
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

}

std::int32_t getsenv(lua_State* L) {
    int type = lua_type(L, 1);
    if (type != LUA_TUSERDATA && type != LUA_TLIGHTUSERDATA) {
        luaL_typeerrorL(L, 1, OBF("Script"));
        return 0;
    }

    void* script = const_cast<void*>(lua_topointer(L, 1));
    if (!script || !L->global) {
        lua_pushstring(L, OBF("script is not currently running"));
        lua_error(L);
        return 0;
    }

    lua_State* current = lua_mainthread(L);
    lua_State* found = nullptr;
    bool foreign = false;

    for (lua_Page* page = current->global->allgcopages; page && !found; page = luaM_getnextpage(page)) {
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
            if (candidate->global != current->global || !candidate->userdata) {
                continue;
            }
            void* active_script = *(void**)((uintptr_t)candidate->userdata + 0x40);
            if (active_script == script) {
                found = candidate;
                break;
            }
        }
    }

    if (!found && roblox_manager.scriptctx) {
        uintptr_t context = (uintptr_t)roblox_manager.scriptctx;
        for (size_t state_index = 0; state_index < 2 && !foreign; ++state_index) {
            uintptr_t state_entry = context + 0x130 + 0x18 + state_index * 0x210;
            uintptr_t handle = state_entry + 0x1e8;
            uint64_t low = (uint32_t)handle - *(uint32_t*)handle;
            uint64_t high = (uint32_t)(handle >> 32) - *(uint32_t*)(handle + 4);
            lua_State* alternate = (lua_State*)(low | (high << 32));
            if (!alternate || !alternate->global || alternate->global == current->global) {
                continue;
            }

            for (lua_Page* page = alternate->global->allgcopages; page && !foreign; page = luaM_getnextpage(page)) {
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
                    if (candidate->global != alternate->global || !candidate->userdata) {
                        continue;
                    }
                    void* active_script = *(void**)((uintptr_t)candidate->userdata + 0x40);
                    if (active_script == script) {
                        foreign = true;
                        break;
                    }
                }
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
    int status = function_mgr.vm_load((void*)L, chunkname, source, 0, 0);
    if (status != 0) {
        if (!lua_isstring(L, -1)) {
            lua_pushfstring(L, OBF("loadstring failed with status %d"), status);
        }
        lua_pushnil(L);
        lua_insert(L, -2);
        return 2;
    }

    if (roblox_manager.scriptctx && L->userdata) {
        void* capability_table = function_mgr.get_capability_table((void*)roblox_manager.scriptctx, L->userdata->capabilities);
        set_proto_caps(L, capability_table);
    }
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

    lua_State* actor_thread = ::lua_newthread(actor_state);
    if (!actor_thread) {
        lua_pushstring(L, OBF("actor thread creation failed"));
        lua_error(L);
        return 0;
    }

    roblox_manager.sandbox_thread(actor_state, actor_thread);
    roblox_manager.set_identity(actor_thread, 8);
    environment_manager.load_environment(actor_thread);

    std::string bytecode = Luau::compile(std::string(source, source_size));
    if (bytecode.empty()) {
        lua_pushstring(L, OBF("actor compile failed"));
        lua_error(L);
        return 0;
    }

    int status = function_mgr.vm_load((void*)actor_thread, OBF("=run_on_actor"), bytecode.data(), 0, 0);
    if (status != 0) {
        lua_pushfstring(L, OBF("actor vm_load failed with status %d"), status);
        lua_error(L);
        return 0;
    }

    script_context* context = roblox_manager.scriptctx;
    if (!context) {
        context = *(script_context**)((uintptr_t)actor_state->global + 0x4e0);
    }
    if (!context || !actor_thread->userdata) {
        lua_pushstring(L, OBF("actor execution context is unavailable"));
        lua_error(L);
        return 0;
    }

    void* capability_table = function_mgr.get_capability_table((void*)context, actor_thread->userdata->capabilities);
    if (!capability_table) {
        lua_pushstring(L, OBF("actor capability table is unavailable"));
        lua_error(L);
        return 0;
    }
    set_proto_caps(actor_thread, capability_table);

    status = function_mgr.lua_resume((void*)actor_thread, nullptr, 0);
    if (status != 0 && status != LUA_YIELD) {
        lua_pushfstring(L, OBF("actor resume failed with status %d"), status);
        lua_error(L);
        return 0;
    }

    return 0;
}

}
