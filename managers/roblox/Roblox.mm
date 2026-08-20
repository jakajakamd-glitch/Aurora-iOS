#import "Roblox.hpp"
#import "../functions/function_mgr.hpp"
#import "../hooks/hook_mgr.hpp"
#import "../utility/utility_mgr.hpp"
#import "../../offsets/offsets.hpp"
#import <Foundation/Foundation.h>
#import <string.h>
#include "lua.h"
#include "lualib.h"
#include "Luau/Compiler.h"

namespace managers {

roblox_manager_t roblox_manager;

namespace {

constexpr uint32_t IDENTITY = 8;
constexpr uint64_t IDENTITY_CAPS = 0x200000000000003fULL;
constexpr uint64_t FALLBACK_CAPS = 0x003fffffffffff00ULL;
constexpr uint64_t FINAL_CAPS = IDENTITY_CAPS | FALLBACK_CAPS;

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
    const void* obj = lua_topointer(l, closure_index);
    if (!obj) return;

    lua_closure_view* closure = (lua_closure_view*)obj;
    proto_view* root = closure->proto;
    if (!root) return;

    set_one_proto_caps(root, capability_record);

    for (uint32_t i = 0; i < root->child_proto_count; ++i) {
        set_one_proto_caps(root->child_protos[i], capability_record);
    }
}

void (*orig_jobStart)(Job*) = nullptr;
void (*orig_startScript)(script_context*, ScriptStart*) = nullptr;
void (*orig_onServiceProvider)(script_context*, void*, void*) = nullptr;

void on_service_provider_hook(script_context* ctx, void* oldprovider, void* newprovider) {
    utility::utility_mgr.log([[NSString stringWithFormat:@"onServiceProvider ctx=%p old=%p new=%p", ctx, oldprovider, newprovider] UTF8String]);
    if (newprovider) {
        roblox_manager.setup_environment(nullptr);
    }
    orig_onServiceProvider(ctx, oldprovider, newprovider);
}

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
    void *onsp        = function_mgr.resolve(function_mgr_type::onServiceProvider_offset);

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
    if (onsp) {
        hook_mgr.hook(reinterpret_cast<uintptr_t>(onsp),
                      (void*)on_service_provider_hook,
                      (void**)&orig_onServiceProvider);
    }
    utility::utility_mgr.log([[NSString stringWithFormat:@"hooks installed jobStart=%p startScript=%p onSP=%p", jobstart, startscript, onsp] UTF8String]);
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

    utility::utility_mgr.log([[NSString stringWithFormat:@"setup_environment sc=%p state=%p thread=%p", scriptctx, selected_state, thread] UTF8String]);
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

    lua_State* l = lua_newthread(thread);
    if (!l) {
        utility::utility_mgr.log("execute_script: lua_newthread failed");
        return -1;
    }

    lua_createtable(l, 0, 0);
    lua_createtable(l, 0, 0);
    lua_pushliteral(l, "the metatable is locked");
    lua_setfield(l, -2, "__metatable");
    lua_pushliteral(l, "__index");
    lua_pushvalue(l, LUA_GLOBALSINDEX);
    lua_settable(l, -3);
    lua_setmetatable(l, -2);
    lua_replace(l, LUA_GLOBALSINDEX);

    void** exec_ptr = (void**)((char*)l + roblox_offsets::extraspace_ptr_l);
    if (!*exec_ptr) {
        utility::utility_mgr.log("execute_script: no execution context");
        return -1;
    }
    uint64_t* caps = (uint64_t*)((char*)(*exec_ptr) + roblox_offsets::extraspace_caps);
    *caps = FINAL_CAPS;

    std::string bytecode = Luau::compile(std::string(source, size));
    if (bytecode.empty()) {
        utility::utility_mgr.log("execute_script: compile failed");
        return -1;
    }

    int status = function_mgr.vm_load((void*)l,
                                       chunkname ? chunkname : "aurora",
                                       bytecode.data(),
                                       0, 0);
    if (status != 0) {
        utility::utility_mgr.log([[NSString stringWithFormat:@"execute_script: vm_load failed status=%d", status] UTF8String]);
        return status;
    }

    void* capability_record = function_mgr.get_capability_record((void*)scriptctx, *caps);
    if (!capability_record) {
        utility::utility_mgr.log("execute_script: no capability_record");
        return -1;
    }

    set_proto_caps(l, -1, capability_record);
    utility::utility_mgr.log([[NSString stringWithFormat:@"execute_script: proto caps set record=%p", capability_record] UTF8String]);

    status = function_mgr.lua_resume((void*)l, nullptr, 0);
    if (status != 0 && status != LUA_YIELD) {
        utility::utility_mgr.log([[NSString stringWithFormat:@"execute_script: resume failed status=%d", status] UTF8String]);
        return status;
    }

    utility::utility_mgr.log([[NSString stringWithFormat:@"execute_script: ok status=%d", status] UTF8String]);
    return 0;
}

}
