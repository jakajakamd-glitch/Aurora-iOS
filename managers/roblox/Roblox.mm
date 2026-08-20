#import "Roblox.hpp"
#import "../functions/function_mgr.hpp"
#import "../hooks/hook_mgr.hpp"
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

void job_start_hook(Job *job) {
    const char *name = roblox_manager_t::get_job_name(job);
    if (!name) {
        orig_jobStart(job);
        return;
    }
    NSLog(@"[Aurora] JobStart name=\"%s\" job=%p", name, job);
    if (roblox_manager_t::is_whsj(job)) {
        roblox_manager.setup_environment(job);
    }
    orig_jobStart(job);
}

void start_script_hook(script_context *ctx, ScriptStart *script_start) {
    script_context *gs = roblox_manager.gs();
    if (!gs) {
        gs = roblox_manager.get_global_state(ctx, capabilities::roblox_script);
    }
    NSLog(@"[Aurora] startScript this=%p scriptStart=%p GlobalState=%p",
          ctx, script_start, gs);
    orig_startScript(ctx, script_start);
}
}

void roblox_manager_t::start() {
    NSLog(@"[Aurora] roblox_manager_t::start");
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
    NSLog(@"[Aurora] roblox_manager_t: hooks installed (jobStart=%p startScript=%p)",
          jobstart, startscript);
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
    scriptctx    = nullptr;
    globalstate  = nullptr;
    luathread    = nullptr;

    if (!whsj) return;

    scriptctx = get_script_context_from_whsj(whsj);
    if (!scriptctx) {
        NSLog(@"[Aurora] setup_environment: WHSJ %p has no script_context", whsj);
        return;
    }

    globalstate = get_global_state(scriptctx, capabilities::roblox_script);
    if (!globalstate) {
        NSLog(@"[Aurora] setup_environment: GlobalState resolve failed for sc=%p", scriptctx);
        return;
    }

    luathread = lua_newthread((lua_State*)globalstate);

    NSLog(@"[Aurora] setup_environment: WHSJ=%p sc=%p gs=%p thread=%p",
          whsj, scriptctx, globalstate, luathread);
}

lua_State* roblox_manager_t::lua_newthread(lua_State* L) {
    if (!L) return nullptr;
    return ::lua_newthread(L);
}

void roblox_manager_t::start_script(script_context* ctx, ScriptStart* script_start) {
    function_mgr.start_script((void*)ctx, (void*)script_start);
}

int roblox_manager_t::execute_script(const char* source, size_t size, const char* chunkname) {
    if (!luathread || !source || size == 0) {
        NSLog(@"[Aurora] execute_script: no thread or source");
        return -1;
    }

    void** extraspace_ptr = (void**)((char*)luathread + roblox_offsets::extraspace_ptr_l);
    if (*extraspace_ptr) {
        uint64_t* caps = (uint64_t*)((char*)(*extraspace_ptr) + roblox_offsets::extraspace_caps);
        *caps = capabilities::roblox_script;
        NSLog(@"[Aurora] execute_script: set caps=0x%llx at es=%p",
              (unsigned long long)*caps, *extraspace_ptr);
    }

    std::string bytecode = Luau::compile(std::string(source, size));
    if (bytecode.empty()) {
        NSLog(@"[Aurora] execute_script: compile failed");
        return -1;
    }

    int status = function_mgr.vm_load((void*)luathread,
                                       chunkname ? chunkname : "aurora",
                                       bytecode.data(),
                                       0, 0);
    if (status != 0) {
        NSLog(@"[Aurora] execute_script: vm_load failed status=%d", status);
        return status;
    }

    status = function_mgr.lua_resume((void*)luathread, nullptr, 0);
    if (status != 0 && status != LUA_YIELD) {
        NSLog(@"[Aurora] execute_script: resume failed status=%d", status);
        return status;
    }

    NSLog(@"[Aurora] execute_script: ok status=%d", status);
    return 0;
}

}
