#import "function_mgr.hpp"
#import <Foundation/Foundation.h>

namespace managers {

function_mgr_type function_mgr;

namespace {
typedef void* (*getGlobalState_t)(void*);
typedef void  (*startScript_t)(void*, void*);
}

void function_mgr_type::start(uintptr_t base) {
    base_ = base;
    NSLog(OBF_NS("[Aurora] function_mgr::start base=%p"), (void*)base_);
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

}
