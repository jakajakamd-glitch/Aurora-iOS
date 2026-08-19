#pragma once

#include <cstdint>

namespace managers {

class function_mgr_type {
public:
    void init(uintptr_t base);

    void* resolve(uintptr_t offset);

    void* get_global_state(void* ctx);
    void* lua_newthread(void* L);

private:
    uintptr_t base_ = 0;
};

extern function_mgr_type function_mgr;

}
