#import "function_mgr.hpp"
#import "../utility/utility_mgr.hpp"
#import <Foundation/Foundation.h>

namespace managers {

function_mgr_type function_mgr;

namespace {
typedef void* (*getGlobalState_t)(void*, void*, void*);
typedef void  (*startScript_t)(void*, void*);
typedef int   (*vmLoad_t)(void*, const char*, const char*, int, int);
typedef int   (*luaResume_t)(void*, void*, int);
typedef void  (*childSandbox_t)(void*, void*, void*, void*);
typedef void* (*getCapabilityRecord_t)(void*, uint64_t);
typedef void  (*protoSetCaps_t)(void*, int, void*);
typedef uint64_t (*identityCapabilities_t)(uint32_t);
typedef int   (*directResume_t)(void*, void*, int);
typedef int   (*lowerResume_t)(void*, void*, int);
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

void* function_mgr_type::get_global_state(void* scriptctx) {
    if (base_ == 0 || !scriptctx) return nullptr;
    auto fn = (getGlobalState_t)(base_ + getGlobalState_offset);
    return fn(scriptctx, nullptr, nullptr);
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

void function_mgr_type::child_sandbox(void* thread, void* identity, void* owner, void* setup) {
    if (base_ == 0 || !thread) return;
    auto fn = (childSandbox_t)(base_ + childSandbox_offset);
    fn(thread, identity, owner, setup);
}

void* function_mgr_type::get_capability_record(void* scriptctx, uint64_t caps) {
    if (base_ == 0 || !scriptctx) return nullptr;
    auto fn = (getCapabilityRecord_t)(base_ + getCapabilityRecord_offset);
    return fn(scriptctx, caps);
}

void function_mgr_type::proto_set_caps(void* thread, int idx, void* capability_record) {
    if (base_ == 0 || !thread || !capability_record) return;
    auto fn = (protoSetCaps_t)(base_ + protoSetCaps_offset);
    fn(thread, idx, capability_record);
}

uint64_t function_mgr_type::identity_capabilities(uint32_t identity) {
    if (base_ == 0) return 0;
    auto fn = (identityCapabilities_t)(base_ + identityCapabilities_offset);
    return fn(identity);
}

int function_mgr_type::direct_resume(void* thread, void* from, int nargs) {
    if (base_ == 0 || !thread) return -1;
    auto fn = (directResume_t)(base_ + directResume_offset);
    return fn(thread, from, nargs);
}

int function_mgr_type::lower_resume(void* thread, void* from, int nargs) {
    if (base_ == 0 || !thread) return -1;
    auto fn = (lowerResume_t)(base_ + lowerResume_offset);
    return fn(thread, from, nargs);
}

}
