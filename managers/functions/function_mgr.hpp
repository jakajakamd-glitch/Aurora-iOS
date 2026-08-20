#pragma once

#include <cstdint>

namespace managers {

class function_mgr_type {
public:
    void start(uintptr_t base);

    void* resolve(uintptr_t offset);

    static constexpr uintptr_t jobstart_offset    = 0x489eac8;
    static constexpr uintptr_t jobstop_offset     = 0x489ebd4;
    static constexpr uintptr_t startScript_offset = 0x179b568;
    static constexpr uintptr_t getGlobalState_offset = 0x179c624;
    static constexpr uintptr_t vmLoad_offset       = 0x0438dc50;
    static constexpr uintptr_t luaResume_offset    = 0x04370e34;

    void* get_global_state(void* ctx);
    void  start_script(void* ctx, void* script_start);
    int   vm_load(void* L, const char* name, const char* data, int mode, int flags);
    int   lua_resume(void* L, void* from, int nargs);

private:
    uintptr_t base_ = 0;
};

extern function_mgr_type function_mgr;

}
