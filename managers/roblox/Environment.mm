#import "environment.hpp"
#import "Roblox.hpp"
#import "../functions/function_mgr.hpp"
#include <cstdint>
#include "lua.h"
#include "lualib.h"
#include "lmem.h"
#include "lobject.h"
#include "lstate.h"

namespace managers {

environment_manager_t environment_manager;

namespace {

static uint8_t genv_key;

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

std::int32_t getsenv(lua_State* L) {
    int type = lua_type(L, 1);
    if (type != LUA_TUSERDATA && type != LUA_TLIGHTUSERDATA) {
        luaL_typeerrorL(L, 1, "Script");
        return 0;
    }

    void* script = const_cast<void*>(lua_topointer(L, 1));
    if (!script || !L->global) {
        luaL_error(L, "script is not currently running");
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
            uintptr_t record = context + 0x130 + 0x18 + state_index * 0x210;
            uintptr_t handle = record + 0x1e8;
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
        luaL_error(L, "script is not currently running");
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
    const char* chunkname = luaL_optstring(L, 2, "=loadstring");
    int status = function_mgr.vm_load((void*)L, chunkname, source, 0, 0);
    if (status != 0) {
        if (!lua_isstring(L, -1)) {
            lua_pushfstring(L, "loadstring failed with status %d", status);
        }
        lua_pushnil(L);
        lua_insert(L, -2);
        return 2;
    }

    if (roblox_manager.scriptctx && L->userdata) {
        void* capability_record = function_mgr.get_capability_record(
            (void*)roblox_manager.scriptctx,
            L->userdata->capabilities
        );
        if (capability_record && lua_type(L, -1) == LUA_TFUNCTION) {
            const void* object = lua_topointer(L, -1);
            closure_view* closure = (closure_view*)object;
            proto_view* root = closure ? closure->proto : nullptr;
            if (root && (root->child_protos || root->child_proto_count == 0)) {
                root->capabilities = capability_record;
                for (uint32_t i = 0; i < root->child_proto_count; ++i) {
                    if (root->child_protos[i]) {
                        root->child_protos[i]->capabilities = capability_record;
                    }
                }
            }
        }
    }
    return 1;
}

}

void environment_manager_t::load_environment(lua_State* thread) {
    if (!thread) {
        return;
    }

    lua_pushcclosurek(thread, getsenv, "getsenv", 0, nullptr);
    lua_setglobal(thread, "getsenv");
    lua_pushcclosurek(thread, getrenv, "getrenv", 0, nullptr);
    lua_setglobal(thread, "getrenv");
    lua_pushcclosurek(thread, getgenv, "getgenv", 0, nullptr);
    lua_setglobal(thread, "getgenv");
    lua_pushcclosurek(thread, loadstring, "loadstring", 0, nullptr);
    lua_setglobal(thread, "loadstring");
}

}

