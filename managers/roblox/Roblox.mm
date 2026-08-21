#import "Roblox.hpp"
#import "environment.hpp"
#import "../core/core.hpp"
#import "../functions/function_mgr.hpp"
#import "../hooks/hook_mgr.hpp"
#import "../utility/utility_mgr.hpp"
#import "../../offsets/offsets.hpp"
#import <Foundation/Foundation.h>
#import <string.h>
#include "lua.h"
#include "lualib.h"
#include "lstate.h"
#include "lapi.h"

namespace managers {

roblox_manager_t roblox_manager;

namespace {

constexpr uint64_t fallback_caps = 0x003fffffffffff00ULL;
constexpr uintptr_t identity_table_offset = 0x53d4618;

struct proto_view {
    uint8_t unknown_00[0x20];
    proto_view** child_protos;
    uint8_t unknown_28[0x10];
    void* capabilities;
    uint8_t unknown_40[0x68];
    uint32_t child_proto_count;
};

struct lua_closure_view {
    uint8_t unknown_00[0x18];
    proto_view* proto;
};

void set_one_proto_caps(proto_view* proto, void* capability_table) {
    if (proto) {
        proto->capabilities = capability_table;
    }
}

void set_proto_caps_impl(lua_State* l, int closure_index, void* capability_table) {
    if (!l || !capability_table || lua_type(l, closure_index) != LUA_TFUNCTION) {
        return;
    }
    function_mgr.set_proto_caps((void*)l, closure_index, capability_table);
}

void set_identity_impl(lua_State* l, uint32_t identity) {
    if (!l || !l->userdata || identity == 0 || identity > 13) {
        return;
    }

    uint64_t* identity_table = reinterpret_cast<uint64_t*>(function_mgr.resolve(identity_table_offset));
    if (!identity_table) {
        return;
    }

    uint64_t raw_capabilities = identity_table[identity - 1];
    l->userdata->capabilities = raw_capabilities | fallback_caps;

    if (l->userdata->shared_identity) {
        *reinterpret_cast<uint64_t*>(reinterpret_cast<uint8_t*>(l->userdata->shared_identity) + 0x10) = identity;
    }
}

int native_loadstring_bridge(lua_State* L) {
    return function_mgr.load_string((void*)L);
}

void (*orig_jobStart)(Job*) = nullptr;
void (*orig_startScript)(script_context*, ScriptStart*) = nullptr;
void (*orig_gameLoaded)(void*, void*) = nullptr;

void job_start_hook(Job *job) {
    const char *name = roblox_manager_t::get_job_name(job);
    if (!name) {
        if (orig_jobStart) {
            orig_jobStart(job);
        }
        return;
    }
    utility::utility_mgr.log([[NSString stringWithFormat:OBF_NS("JobStart \\\"%s\\\" %p"), name, job] UTF8String]);
    if (roblox_manager_t::is_whsj(job)) {
        roblox_manager.setup_environment(job);
    }
    if (orig_jobStart) {
        orig_jobStart(job);
    }
}

void game_loaded_hook(void* sender, void* data) {
    if (orig_gameLoaded) {
        orig_gameLoaded(sender, data);
    }
    core::on_game_loaded(sender, data);
}

void start_script_hook(script_context *ctx, ScriptStart *script_start) {
    void *gs = roblox_manager.selected_state;
    if (!gs) {
        gs = roblox_manager.get_global_state(ctx);
    }
    utility::utility_mgr.log([[NSString stringWithFormat:OBF_NS("startScript this=%p scriptStart=%p state=%p"), ctx, script_start, gs] UTF8String]);
    if (orig_startScript) {
        orig_startScript(ctx, script_start);
    }
}
}

void roblox_manager_t::set_identity(lua_State* l, uint32_t identity) {
    set_identity_impl(l, identity);
}

void roblox_manager_t::set_proto_caps(lua_State* l, int closure_index, void* capability_table) {
    set_proto_caps_impl(l, closure_index, capability_table);
}

void roblox_manager_t::start() {
    utility::utility_mgr.log(OBF("roblox_manager_t::start"));
    install_hooks();
}

void roblox_manager_t::install_hooks() {
    void *jobstart    = function_mgr.resolve(function_mgr_type::jobstart_offset);
    void *startscript = function_mgr.resolve(function_mgr_type::startScript_offset);
    void *game_loaded = function_mgr.resolve(function_mgr_type::gameLoaded_offset);

    if (jobstart) {
        hook_mgr.hook(reinterpret_cast<uintptr_t>(jobstart),
                      (void*)job_start_hook,
                      (void**)&orig_jobStart);
    }
    if (startscript) {
        hook_mgr.hook(reinterpret_cast<uintptr_t>(startscript),
                      (void*)start_script_hook,
                      (void**)&orig_startScript);
    }
    if (game_loaded) {
        hook_mgr.hook(reinterpret_cast<uintptr_t>(game_loaded),
                      (void*)game_loaded_hook,
                      (void**)&orig_gameLoaded);
    }
    utility::utility_mgr.log([[NSString stringWithFormat:OBF_NS("hooks installed jobStart=%p startScript=%p gameLoaded=%p"), jobstart, startscript, game_loaded] UTF8String]);
}

const char* roblox_manager_t::get_job_name(Job* job) {
    if (!job) return nullptr;
    char* str_slot = (char*)((uintptr_t)job + roblox_offsets::job_name);
    int8_t flag = *(int8_t*)((uintptr_t)job + roblox_offsets::job_name_flag);
    if (flag < 0) {
        return *(const char**)str_slot;
    }
    return str_slot;
}

script_context* roblox_manager_t::get_script_context_from_whsj(Job* whsj) {
    if (!whsj) return nullptr;
    void** slot = (void**)((uintptr_t)whsj + roblox_offsets::whsj_script_context);
    return (script_context*)(*slot);
}

bool roblox_manager_t::is_whsj(Job* job) {
    const char* name = get_job_name(job);
    if (!name) return false;
    return strcmp(name, roblox_offsets::whsj_name) == 0;
}

void* roblox_manager_t::get_global_state(script_context* ctx) {
    if (!ctx) return nullptr;
    return function_mgr.get_global_state((void*)ctx);
}

void roblox_manager_t::setup_environment(Job* whsj) {
    scriptctx      = nullptr;
    selected_state = nullptr;
    thread         = nullptr;

    if (!whsj) return;

    scriptctx = get_script_context_from_whsj(whsj);
    if (!scriptctx) {
        utility::utility_mgr.log(OBF("setup_environment: no script_context"));
        return;
    }

    selected_state = get_global_state(scriptctx);
    if (!selected_state) {
        utility::utility_mgr.log(OBF("setup_environment: no selected_state"));
        return;
    }

    thread = lua_newthread((lua_State*)selected_state);
    if (!thread) {
        utility::utility_mgr.log(OBF("setup_environment: lua_newthread failed"));
        return;
    }

    sandbox_thread((lua_State*)selected_state, thread);
    set_identity(thread, 8);

    utility::utility_mgr.log([[NSString stringWithFormat:OBF_NS("setup_environment sc=%p state=%p thread=%p"), scriptctx, selected_state, thread] UTF8String]);
}

void roblox_manager_t::sandbox_thread(
    lua_State* parent_state,
    lua_State* child_thread
) {
    if (!parent_state || !child_thread) {
        return;
    }

    lua_newtable(child_thread);
    lua_newtable(child_thread);
    lua_pushstring(child_thread, OBF("the metatable is locked"));
    lua_setfield(child_thread, -2, OBF("__metatable"));
    lua_pushvalue(parent_state, LUA_GLOBALSINDEX);
    lua_xmove(parent_state, child_thread, 1);
    lua_pushstring(child_thread, OBF("__index"));
    lua_insert(child_thread, -2);
    lua_settable(child_thread, -3);
    lua_setmetatable(child_thread, -2);
    lua_replace(child_thread, LUA_GLOBALSINDEX);
    lua_newtable(child_thread);
    lua_setglobal(child_thread, OBF("shared"));
}

lua_State* roblox_manager_t::lua_newthread(lua_State* L) {
    if (!L) return nullptr;
    return (lua_State*)function_mgr.new_thread((void*)L);
}

void roblox_manager_t::start_script(script_context* ctx, ScriptStart* script_start) {
    function_mgr.start_script((void*)ctx, (void*)script_start);
}

int roblox_manager_t::execute_script(const char* source,
                                       size_t size,
                                       const char* chunkname,
                                       lua_State* parent_state,
                                       script_context* context_override,
                                       uint32_t flags) {
    lua_State* parent = parent_state ? parent_state : thread;
    script_context* context = context_override ? context_override : scriptctx;
    if (!parent || !source || size == 0 || !context) {
        utility::utility_mgr.log(OBF("execute_script: missing parent, context, or source"));
        return -1;
    }

    lua_State* new_thread = lua_newthread(parent);
    if (!new_thread) {
        utility::utility_mgr.log(OBF("execute_script: lua_newthread failed"));
        return -1;
    }

    sandbox_thread(parent, new_thread);

    if (!new_thread->userdata) {
        utility::utility_mgr.log(OBF("execute_script: no execution context"));
        return -1;
    }
    set_identity(new_thread, 8);
    environment_manager.load_environment(new_thread);

    int base = lua_gettop(new_thread);
    lua_pushlstring(new_thread, source, size);
    lua_pushstring(new_thread, chunkname ? chunkname : OBF("=aurora"));
    lua_pushcclosurek(new_thread, native_loadstring_bridge, OBF("=aurora_load"), 0, nullptr);
    lua_insert(new_thread, base + 1);

    int status = lua_pcall(new_thread, 2, 1, 0);
    if (status != 0) {
        utility::utility_mgr.log([[NSString stringWithFormat:OBF_NS("execute_script: native load failed status=%d flags=%u"), status, flags] UTF8String]);
        lua_settop(new_thread, base);
        lua_pop(parent, 1);
        return status;
    }

    if (lua_type(new_thread, -1) != LUA_TFUNCTION) {
        utility::utility_mgr.log(OBF("execute_script: native load returned non-function"));
        lua_settop(new_thread, base);
        lua_pop(parent, 1);
        return -1;
    }

    utility::utility_mgr.log([[NSString stringWithFormat:OBF_NS("execute_script: native load ok flags=%u"), flags] UTF8String]);

    status = function_mgr.lua_resume((void*)new_thread, nullptr, 0);
    if (status != 0 && status != LUA_YIELD) {
        utility::utility_mgr.log([[NSString stringWithFormat:OBF_NS("execute_script: resume failed status=%d flags=%u"), status, flags] UTF8String]);
        return status;
    }

    utility::utility_mgr.log([[NSString stringWithFormat:OBF_NS("execute_script: ok status=%d flags=%u"), status, flags] UTF8String]);
    if (status != LUA_YIELD) {
        lua_pop(parent, 1);
    }
    return 0;
}

}
