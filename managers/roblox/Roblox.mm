#import "Roblox.hpp"
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
#include "Luau/Compiler.h"

namespace managers {

roblox_manager_t roblox_manager;

namespace {

constexpr uint32_t identity = 8;
constexpr uint64_t identity_caps = 0x200000000000003fULL;
constexpr uint64_t fallback_caps = 0x003fffffffffff00ULL;
constexpr uint64_t final_caps = identity_caps | fallback_caps;

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

void set_one_proto_caps(proto_view* proto, void* capability_record) {
    if (proto) {
        proto->capabilities = capability_record;
    }
}

void set_proto_caps(lua_State* l, int closure_index, void* capability_record) {
    if (!l || !capability_record || lua_type(l, closure_index) != LUA_TFUNCTION) {
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

    set_one_proto_caps(root, capability_record);

    for (uint32_t i = 0; i < root->child_proto_count; ++i) {
        set_one_proto_caps(root->child_protos[i], capability_record);
    }
}

void set_identity(lua_State* l) {
    if (!l || !l->userdata) {
        return;
    }

    l->userdata->capabilities = final_caps;
}

void (*orig_jobStart)(Job*) = nullptr;
void (*orig_startScript)(script_context*, ScriptStart*) = nullptr;

void job_start_hook(Job *job) {
    const char *name = roblox_manager_t::get_job_name(job);
    if (!name) {
        orig_jobStart(job);
        return;
    }
    utility::utility_mgr.log([[NSString stringWithFormat:@"JobStart \"%s\" %p", name, job] UTF8String]);
    if (roblox_manager_t::is_whsj(job)) {
        roblox_manager.setup_environment(job);
    }
    orig_jobStart(job);
}

void start_script_hook(script_context *ctx, ScriptStart *script_start) {
    void *gs = roblox_manager.selected_state;
    if (!gs) {
        gs = roblox_manager.get_global_state(ctx);
    }
    utility::utility_mgr.log([[NSString stringWithFormat:@"startScript this=%p scriptStart=%p state=%p", ctx, script_start, gs] UTF8String]);
    orig_startScript(ctx, script_start);
}
}

void roblox_manager_t::start() {
    utility::utility_mgr.log("roblox_manager_t::start");
    install_hooks();
}

void roblox_manager_t::install_hooks() {
    void *jobstart    = function_mgr.resolve(function_mgr_type::jobstart_offset);
    void *startscript = function_mgr.resolve(function_mgr_type::startScript_offset);

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
    utility::utility_mgr.log([[NSString stringWithFormat:@"hooks installed jobStart=%p startScript=%p", jobstart, startscript] UTF8String]);
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
        utility::utility_mgr.log("setup_environment: no script_context");
        return;
    }

    selected_state = get_global_state(scriptctx);
    if (!selected_state) {
        utility::utility_mgr.log("setup_environment: no selected_state");
        return;
    }

    thread = lua_newthread((lua_State*)selected_state);
    if (!thread) {
        utility::utility_mgr.log("setup_environment: lua_newthread failed");
        return;
    }

    sandbox_thread((lua_State*)selected_state, thread);
    set_identity(thread);

    utility::utility_mgr.log([[NSString stringWithFormat:@"setup_environment sc=%p state=%p thread=%p", scriptctx, selected_state, thread] UTF8String]);
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
    lua_pushliteral(child_thread, "the metatable is locked");
    lua_setfield(child_thread, -2, "__metatable");
    lua_pushvalue(parent_state, LUA_GLOBALSINDEX);
    lua_xmove(parent_state, child_thread, 1);
    lua_pushliteral(child_thread, "__index");
    lua_insert(child_thread, -2);
    lua_settable(child_thread, -3);
    lua_setmetatable(child_thread, -2);
    lua_replace(child_thread, LUA_GLOBALSINDEX);
    lua_newtable(child_thread);
    lua_setglobal(child_thread, "shared");
}

lua_State* roblox_manager_t::lua_newthread(lua_State* L) {
    if (!L) return nullptr;
    return ::lua_newthread(L);
}

void roblox_manager_t::start_script(script_context* ctx, ScriptStart* script_start) {
    function_mgr.start_script((void*)ctx, (void*)script_start);
}

int roblox_manager_t::execute_script(const char* source, size_t size, const char* chunkname) {
    if (!thread || !source || size == 0 || !scriptctx) {
        utility::utility_mgr.log("execute_script: no thread or source");
        return -1;
    }

    lua_State* new_thread = lua_newthread(thread);
    if (!new_thread) {
        utility::utility_mgr.log("execute_script: lua_newthread failed");
        return -1;
    }

    sandbox_thread(thread, new_thread);

    if (!new_thread->userdata) {
        utility::utility_mgr.log("execute_script: no execution context");
        return -1;
    }
    set_identity(new_thread);

    std::string bytecode = Luau::compile(std::string(source, size));
    if (bytecode.empty()) {
        utility::utility_mgr.log("execute_script: compile failed");
        return -1;
    }

    int status = function_mgr.vm_load((void*)new_thread,
                                       chunkname ? chunkname : "aurora",
                                       bytecode.data(),
                                       0, 0);
    if (status != 0) {
        utility::utility_mgr.log([[NSString stringWithFormat:@"execute_script: vm_load failed status=%d", status] UTF8String]);
        return status;
    }

    void* capability_record = function_mgr.get_capability_record((void*)scriptctx, new_thread->userdata->capabilities);
    if (!capability_record) {
        utility::utility_mgr.log("execute_script: no capability_record");
        return -1;
    }

    set_proto_caps(new_thread, -1, capability_record);
    utility::utility_mgr.log([[NSString stringWithFormat:@"execute_script: proto caps set record=%p", capability_record] UTF8String]);

    status = function_mgr.lua_resume((void*)new_thread, nullptr, 0);
    if (status != 0 && status != LUA_YIELD) {
        utility::utility_mgr.log([[NSString stringWithFormat:@"execute_script: resume failed status=%d", status] UTF8String]);
        return status;
    }

    utility::utility_mgr.log([[NSString stringWithFormat:@"execute_script: ok status=%d", status] UTF8String]);
    return 0;
}

}
