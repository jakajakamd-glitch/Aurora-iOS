#import "function_mgr.hpp"
#import <Foundation/Foundation.h>

namespace managers {

function_mgr_type function_mgr;

namespace {
typedef void* (*getGlobalState_t)(void*);
typedef void* (*lua_newthread_t)(void*);
}

void function_mgr_type::init(uintptr_t base) {
    base_ = base;
    NSLog(@"[Aurora] function_mgr init: base=%p", (void*)base_);
}

void* function_mgr_type::resolve(uintptr_t offset) {
    if (base_ == 0) return nullptr;
    return (void*)(base_ + offset);
}

void* function_mgr_type::get_global_state(void* ctx) {
    if (base_ == 0 || ctx == nullptr) return nullptr;
    auto fn = (getGlobalState_t)(base_ + 0x179c624);
    return fn(ctx);
}

void* function_mgr_type::lua_newthread(void* L) {
    if (base_ == 0 || L == nullptr) return nullptr;
    auto fn = (lua_newthread_t)(base_ + 0x4364490);
    return fn(L);
}

}
