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
    script_context *gs = roblox_manager.globalstate;
    if (!gs) {
        gs = roblox_manager.get_global_state(ctx, capabilities::roblox_script);
    }
    utility::utility_mgr.log([[NSString stringWithFormat:@"startScript this=%p scriptStart=%p GS=%p", ctx, script_start, gs] UTF8String]);
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

script_context* roblox_manager_t::get_global_state(script_context* ctx, uint64_t capabilities) {
    if (!ctx) return nullptr;
    if ((capabilities & 0x8) == 0) {
        return (script_context*)function_mgr.get_global_state((void*)ctx);
    }
    return (script_context*)function_mgr.get_global_state((void*)ctx);
}

void roblox_manager_t::setup_environment(Job* whsj) {
    scriptctx   = nullptr;
    globalstate = nullptr;
    thread      = nullptr;

    if (!whsj) return;

    scriptctx = get_script_context_from_whsj(whsj);
    if (!scriptctx) {
        utility::utility_mgr.log("setup_environment: no script_context");
        return;
    }

    globalstate = get_global_state(scriptctx, capabilities::roblox_script);
    if (!globalstate) {
        utility::utility_mgr.log("setup_environment: no globalstate");
        return;
    }

    thread = lua_newthread((lua_State*)globalstate);
    if (!thread) {
        utility::utility_mgr.log("setup_environment: lua_newthread failed");
        return;
    }

    sandbox_thread(thread);

    utility::utility_mgr.log([[NSString stringWithFormat:@"setup_environment sc=%p gs=%p thread=%p", scriptctx, globalstate, thread] UTF8String]);
}

void roblox_manager_t::sandbox_thread(lua_State* thread) {
    if (!thread || !globalstate) return;

    lua_State* gs = (lua_State*)globalstate;

    lua_pushvalue(gs, LUA_GLOBALSINDEX);
    lua_pushvalue(gs, -1);
    lua_xmove(gs, thread, 1);

    lua_newtable(thread);
    lua_pushstring(thread, "_G");
    lua_pushvalue(thread, -3);
    lua_settable(thread, -3);
    lua_setglobal(thread, "_G");

    utility::utility_mgr.log([[NSString stringWithFormat:@"sandbox_thread gs=%p thread=%p", gs, thread] UTF8String]);
}

void roblox_manager_t::set_identity(lua_State* thread, uint32_t identity) {
    if (!thread) return;

    void** extraspace_ptr = (void**)((char*)thread + roblox_offsets::extraspace_ptr_l);
    if (*extraspace_ptr) {
        uint64_t* caps = (uint64_t*)((char*)(*extraspace_ptr) + roblox_offsets::extraspace_caps);
        *caps = capabilities::roblox_script;
        utility::utility_mgr.log([[NSString stringWithFormat:@"set_identity caps=0x%llx es=%p", (unsigned long long)*caps, *extraspace_ptr] UTF8String]);
    }
}

lua_State* roblox_manager_t::lua_newthread(lua_State* L) {
    if (!L) return nullptr;
    return ::lua_newthread(L);
}

void roblox_manager_t::start_script(script_context* ctx, ScriptStart* script_start) {
    function_mgr.start_script((void*)ctx, (void*)script_start);
}

int roblox_manager_t::execute_script(const char* source, size_t size, const char* chunkname) {
    if (!thread || !source || size == 0) {
        utility::utility_mgr.log("execute_script: no thread or source");
        return -1;
    }

    lua_State* exec_thread = lua_newthread(thread);
    if (!exec_thread) {
        utility::utility_mgr.log("execute_script: lua_newthread failed");
        return -1;
    }

    function_mgr.child_sandbox((void*)exec_thread, (void*)globalstate, nullptr, nullptr);

    function_mgr.load_cap_forward((void*)exec_thread, (void*)globalstate);

    std::string bytecode = Luau::compile(std::string(source, size));
    if (bytecode.empty()) {
        utility::utility_mgr.log("execute_script: compile failed");
        return -1;
    }

    int status = function_mgr.vm_load((void*)exec_thread,
                                       chunkname ? chunkname : "aurora",
                                       bytecode.data(),
                                       0, 0);
    if (status != 0) {
        utility::utility_mgr.log([[NSString stringWithFormat:@"execute_script: vm_load failed status=%d", status] UTF8String]);
        return status;
    }

    function_mgr.proto_cap_assign((void*)exec_thread, nullptr);

    status = function_mgr.direct_resume((void*)exec_thread, 0);
    if (status != 0 && status != LUA_YIELD) {
        utility::utility_mgr.log([[NSString stringWithFormat:@"execute_script: direct_resume failed status=%d", status] UTF8String]);
        return status;
    }

    utility::utility_mgr.log([[NSString stringWithFormat:@"execute_script: ok status=%d", status] UTF8String]);
    return 0;
}

}
