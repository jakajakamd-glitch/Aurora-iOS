#import "function_mgr.hpp"
#import "../utility/utility_mgr.hpp"
#import <Foundation/Foundation.h>

namespace managers {

function_mgr_type function_mgr;

namespace {
typedef void* (*getGlobalState_t)(void*);
typedef void  (*startScript_t)(void*, void*);
typedef int   (*vmLoad_t)(void*, const char*, const char*, int, int);
typedef int   (*luaResume_t)(void*, void*, int);
typedef void  (*childSandbox_t)(void*, void*, void*, void*);
typedef void  (*loadCapForward_t)(void*, void*);
typedef void  (*protoCapAssign_t)(void*, void*);
typedef int   (*directResume_t)(void*, int);
typedef int   (*lowerResume_t)(void*, int);
}

void function_mgr_type::start(uintptr_t base) {
    base_ = base;
    NSLog(@"[Aurora] function_mgr::start base=%p", (void*)base_);
    utility::utility_mgr.log([[NSString stringWithFormat:@"function_mgr::start base=%p", (void*)base_] UTF8String]);
}

void* function_mgr_type::resolve(uintptr_t offset) {
    if (base_ == 0) return nullptr;
    return (void*)(base_ + offset);
}

void* function_mgr_type::get_global_state(void* ctx) {
    if (base_ == 0 || ctx == nullptr) return nullptr;
    auto fn = (getGlobalState_t)(base_ + getGlobalState_offset);
    return fn(ctx);
}

void function_mgr_type::start_script(void* ctx, void* script_start) {
    if (base_ == 0) return;
    auto fn = (startScript_t)(base_ + startScript_offset);
    fn(ctx, script_start);
}

int function_mgr_type::vm_load(void* L, const char* name, const char* data, int mode, int flags) {
    if (base_ == 0 || !L || !data) return -1;
    auto fn = (vmLoad_t)(base_ + vmLoad_offset);
    return fn(L, name, data, mode, flags);
}

int function_mgr_type::lua_resume(void* L, void* from, int nargs) {
    if (base_ == 0 || !L) return -1;
    auto fn = (luaResume_t)(base_ + luaResume_offset);
    return fn(L, from, nargs);
}

void function_mgr_type::child_sandbox(void* thread, void* identity, void* owner, void* flags) {
    if (base_ == 0 || !thread) return;
    auto fn = (childSandbox_t)(base_ + childSandbox_offset);
    fn(thread, identity, owner, flags);
}

void function_mgr_type::load_cap_forward(void* thread, void* source) {
    if (base_ == 0 || !thread) return;
    auto fn = (loadCapForward_t)(base_ + loadCapForward_offset);
    fn(thread, source);
}

void function_mgr_type::proto_cap_assign(void* thread, void* proto) {
    if (base_ == 0 || !thread) return;
    auto fn = (protoCapAssign_t)(base_ + protoCapAssign_offset);
    fn(thread, proto);
}

int function_mgr_type::direct_resume(void* thread, int nargs) {
    if (base_ == 0 || !thread) return -1;
    auto fn = (directResume_t)(base_ + directResume_offset);
    return fn(thread, nargs);
}

int function_mgr_type::lower_resume(void* thread, int nargs) {
    if (base_ == 0 || !thread) return -1;
    auto fn = (lowerResume_t)(base_ + lowerResume_offset);
    return fn(thread, nargs);
}

}
