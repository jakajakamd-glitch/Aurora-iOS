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

    const void* object = lua_topointer(l, closure_index);
    if (!object) {
        return;
    }

    lua_closure_view* closure = const_cast<lua_closure_view*>(
        reinterpret_cast<const lua_closure_view*>(object)
    );
    proto_view* root = closure->proto;
    if (!root || !root->child_protos && root->child_proto_count != 0) {
        return;
    }

    set_one_proto_caps(root, capability_table);

    for (uint32_t i = 0; i < root->child_proto_count; ++i) {
        set_one_proto_caps(root->child_protos[i], capability_table);
    }
}

int native_loadstring_bridge(lua_State* l) {
    return function_mgr.load_string((void*)l);
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

bool job_start_hook_installed = false;
bool start_script_hook_installed = false;
bool game_loaded_hook_installed = false;

int job_start_hook(Job *job, void* stats) {
    const char *name = roblox_manager_t::get_job_name(job);
    if (name) {
        utility::utility_mgr.log([[NSString stringWithFormat:OBF_NS("JobStart \\\"%s\\\" %p"), name, job] UTF8String]);
        if (roblox_manager_t::is_whsj(job)) {
            roblox_manager.setup_environment(job);
        }
    }
    if (job_start_hook_installed) {
        return reinterpret_cast<int (*)(Job*, void*)>(aurora_job_start_trampoline)(job, stats);
    }
    return 0;
}

void game_loaded_hook(void* sender, void* data) {
    if (game_loaded_hook_installed) {
        reinterpret_cast<void (*)(void*, void*)>(aurora_game_loaded_trampoline)(sender, data);
    }
    core::on_game_loaded(sender, data);
}

void start_script_hook(script_context *ctx, ScriptStart *script_start) {
    void *gs = roblox_manager.selected_state;
    if (!gs) {
        gs = roblox_manager.get_global_state(ctx);
    }
    utility::utility_mgr.log([[NSString stringWithFormat:OBF_NS("startScript this=%p scriptStart=%p state=%p"), ctx, script_start, gs] UTF8String]);
    if (start_script_hook_installed) {
        reinterpret_cast<void (*)(script_context*, ScriptStart*)>(aurora_start_script_trampoline)(ctx, script_start);
    }
}
}

void roblox_manager_t::set_identity(lua_State* l, uint32_t identity) {
    set_identity_impl(l, identity);
}

void roblox_manager_t::set_proto_caps(lua_State* l, int closure_index, void* capability_table) {
    function_mgr.set_proto_caps((void*)l, closure_index, capability_table);
}

void roblox_manager_t::start() {
    utility::utility_mgr.log(OBF("roblox_manager_t::start"));
    install_hooks();
}

void roblox_manager_t::install_hooks() {
    void *jobstart    = function_mgr.resolve(function_mgr_type::jobstart_offset);
    void *startscript = function_mgr.resolve(function_mgr_type::startScript_offset);
    void *game_loaded = function_mgr.resolve(function_mgr_type::gameLoaded_offset);

    static const uint32_t job_start_prologue[4] = {
        0xa9be4ff4u, 0xa9017bfdu, 0x910043fdu, 0xa00003f3u
    };
    static const uint32_t start_script_prologue[4] = {
        0xa9ba6ffcu, 0xa90167fau, 0xa9025ff8u, 0xa90357f6u
    };
    static const uint32_t game_loaded_prologue[4] = {
        0xd10143ffu, 0xa90257f6u, 0xa9034ff4u, 0xa9047bfdu
    };
    utility::utility_mgr.log([[NSString stringWithFormat:OBF_NS("hook targets job=%p start=%p loaded=%p"), jobstart, startscript, game_loaded] UTF8String]);
    if (jobstart) {
        job_start_hook_installed = hook_mgr.hook(reinterpret_cast<uintptr_t>(jobstart),
                                                 (void*)job_start_hook,
                                                 nullptr,
                                                 (void*)aurora_job_start_trampoline,
                                                 &aurora_job_start_return,
                                                 job_start_prologue);
    }
    if (startscript) {
        start_script_hook_installed = hook_mgr.hook(reinterpret_cast<uintptr_t>(startscript),
                                                    (void*)start_script_hook,
                                                    nullptr,
                                                    (void*)aurora_start_script_trampoline,
                                                    &aurora_start_script_return,
                                                    start_script_prologue);
    }
    if (game_loaded) {
        game_loaded_hook_installed = hook_mgr.hook(reinterpret_cast<uintptr_t>(game_loaded),
                                                   (void*)game_loaded_hook,
                                                   nullptr,
                                                   (void*)aurora_game_loaded_trampoline,
                                                   &aurora_game_loaded_return,
                                                   game_loaded_prologue);
    }
    utility::utility_mgr.log([[NSString stringWithFormat:OBF_NS("hooks result job=%d start=%d loaded=%d"), job_start_hook_installed, start_script_hook_installed, game_loaded_hook_installed] UTF8String]);
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
    return ::lua_newthread(L);
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

    int parent_top = lua_gettop(parent);
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
    lua_setsafeenv(new_thread, LUA_GLOBALSINDEX, 1);

    int status = function_mgr.vm_load((void*)new_thread,
                                       chunkname ? chunkname : OBF("=aurora"),
                                       source,
                                       0,
                                       0);
    if (status != 0) {
        utility::utility_mgr.log([[NSString stringWithFormat:OBF_NS("execute_script: vm_load failed status=%d flags=%u"), status, flags] UTF8String]);
        lua_settop(parent, parent_top);
        return status;
    }

    void* capability_table = function_mgr.get_capability_table((void*)context, new_thread->userdata->capabilities);
    if (!capability_table) {
        utility::utility_mgr.log(OBF("execute_script: no capability_table"));
        lua_settop(parent, parent_top);
        return -1;
    }

    set_proto_caps(new_thread, -1, capability_table);
    environment_manager.load_environment(new_thread);
    utility::utility_mgr.log([[NSString stringWithFormat:OBF_NS("execute_script: manual function ready table=%p flags=%u"), capability_table, flags] UTF8String]);

    status = function_mgr.lua_resume((void*)new_thread, nullptr, 0);
    if (status != 0 && status != LUA_YIELD) {
        utility::utility_mgr.log([[NSString stringWithFormat:OBF_NS("execute_script: resume failed status=%d flags=%u"), status, flags] UTF8String]);
        lua_settop(parent, parent_top);
        return status;
    }

    utility::utility_mgr.log([[NSString stringWithFormat:OBF_NS("execute_script: ok status=%d flags=%u"), status, flags] UTF8String]);
    if (status != LUA_YIELD) {
        lua_settop(parent, parent_top);
    }
    return 0;
}

}
