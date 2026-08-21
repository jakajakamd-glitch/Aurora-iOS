#import "Roblox.hpp"
#import "function_mgr.hpp"
#import "hook_mgr.hpp"
#import "offsets.hpp"
#import <Foundation/Foundation.h>
#import <string.h>
#include "lua.h"

namespace managers {

roblox_manager_t roblox_manager;

namespace {
void (*orig_jobStart)(Job*) = nullptr;
void (*orig_jobStop)(Job*)  = nullptr;
void (*orig_startScript)(script_context*, ScriptStart*) = nullptr;

constexpr uint64_t DEFAULT_CLASSIFICATION = 0x2000000000000003ULL;

void job_start_hook(Job *job) {
    const char *name = roblox_manager_t::get_job_name(job);
    if (!name) {
        orig_jobStart(job);
        return;
    }
    NSLog(OBF_NS("[Aurora] JobStart name=\")%s\OBF(" job=%p"), name, job);
    if (roblox_manager_t::is_whsj(job)) {
        roblox_manager.setup_environment(job);
    }
    orig_jobStart(job);
}

void job_stop_hook(Job *job) {
    const char *name = roblox_manager_t::get_job_name(job);
    if (name) {
        NSLog(OBF_NS("[Aurora] JobStop name=\")%s\OBF(" job=%p"), name, job);
    }
    orig_jobStop(job);
}

void start_script_hook(script_context *ctx, ScriptStart *script_start) {
    script_context *gs = roblox_manager.gs();
    if (!gs) {
        gs = roblox_manager.select_global_state_handle(ctx, DEFAULT_CLASSIFICATION);
    }
    NSLog(OBF_NS("[Aurora] startScript this=%p scriptStart=%p GlobalState=%p"),
          ctx, script_start, gs);
    orig_startScript(ctx, script_start);
}
}

void roblox_manager_t::start() {
    NSLog(OBF_NS("[Aurora] roblox_manager_t::start"));
    install_hooks();
}

void roblox_manager_t::install_hooks() {
    void *jobstart    = function_mgr.resolve(function_mgr_type::jobstart_offset);
    void *jobstop     = function_mgr.resolve(function_mgr_type::jobstop_offset);
    void *startscript = function_mgr.resolve(function_mgr_type::startScript_offset);

    if (jobstart) {
        hook_mgr.hook(reinterpret_cast<uintptr_t>(jobstart),
                      (void*)job_start_hook,
                      (void**)&orig_jobStart);
    }
    if (jobstop) {
        hook_mgr.hook(reinterpret_cast<uintptr_t>(jobstop),
                      (void*)job_stop_hook,
                      (void**)&orig_jobStop);
    }
    if (startscript) {
        hook_mgr.hook(reinterpret_cast<uintptr_t>(startscript),
                      (void*)start_script_hook,
                      (void**)&orig_startScript);
    }
    NSLog(OBF_NS("[Aurora] roblox_manager_t: hooks installed (jobStart=%p jobStop=%p startScript=%p)"),
          jobstart, jobstop, startscript);
}

const char* roblox_manager_t::get_job_name(Job* job) {
    if (!job) return nullptr;
    char* str_slot = (char*)((uintptr_t)job + ROBLOX_OFFSETS::job_name);
    int8_t flag = *(int8_t*)((uintptr_t)job + ROBLOX_OFFSETS::job_name_flag);
    if (flag < 0) {
        return *(const char**)str_slot;
    }
    return str_slot;
}

script_context* roblox_manager_t::get_script_context_from_whsj(Job* whsj) {
    if (!whsj) return nullptr;
    void** slot = (void**)((uintptr_t)whsj + ROBLOX_OFFSETS::whsj_script_context);
    return (script_context*)(*slot);
}

bool roblox_manager_t::is_whsj(Job* job) {
    const char* name = get_job_name(job);
    if (!name) return false;
    return strcmp(name, ROBLOX_OFFSETS::whsj_name) == 0;
}

script_context* roblox_manager_t::get_global_state(script_context* ctx) {
    return (script_context*)function_mgr.get_global_state((void*)ctx);
}

script_context* roblox_manager_t::select_global_state_handle(
    script_context* sc, uint64_t classification) {
    if (!sc) return nullptr;
    if ((classification & 0x8) == 0) {
        return get_global_state(sc);
    }
    return get_global_state(sc);
}

void roblox_manager_t::setup_environment(Job* whsj) {
    sc_     = nullptr;
    gs_     = nullptr;
    thread_ = nullptr;

    if (!whsj) return;

    sc_ = get_script_context_from_whsj(whsj);
    if (!sc_) {
        NSLog(OBF_NS("[Aurora] setup_environment: WHSJ %p has no script_context"), whsj);
        return;
    }

    gs_ = select_global_state_handle(sc_, DEFAULT_CLASSIFICATION);
    if (!gs_) {
        NSLog(OBF_NS("[Aurora] setup_environment: GlobalState resolve failed for sc=%p"), sc_);
        return;
    }

    thread_ = lua_newthread((lua_State*)gs_);

    NSLog(OBF_NS("[Aurora] setup_environment: WHSJ=%p sc=%p gs=%p thread=%p"),
          whsj, sc_, gs_, thread_);
}

lua_State* roblox_manager_t::lua_newthread(lua_State* L) {
    if (!L) return nullptr;
    return ::lua_newthread(L);
}

void roblox_manager_t::start_script(script_context* ctx, ScriptStart* script_start) {
    function_mgr.start_script((void*)ctx, (void*)script_start);
}

}
