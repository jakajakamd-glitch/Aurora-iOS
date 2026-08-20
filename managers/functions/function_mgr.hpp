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
    static constexpr uintptr_t onServiceProvider_offset = 0x01767b00;
    static constexpr uintptr_t childSandbox_offset     = 0x0179c8a8;
    static constexpr uintptr_t loadCapForward_offset   = 0x01766d5c;
    static constexpr uintptr_t protoCapAssign_offset   = 0x0179cc00;
    static constexpr uintptr_t directResume_offset     = 0x01774560;
    static constexpr uintptr_t lowerResume_offset      = 0x0437302c;

    void* get_global_state(void* ctx);
    void  start_script(void* ctx, void* script_start);
    int   vm_load(void* L, const char* name, const char* data, int mode, int flags);
    int   lua_resume(void* L, void* from, int nargs);
    void  child_sandbox(void* thread, void* identity, void* owner, void* flags);
    void  load_cap_forward(void* thread, void* source);
    void  proto_cap_assign(void* thread, void* proto);
    int   direct_resume(void* thread, int nargs);
    int   lower_resume(void* thread, int nargs);

private:
    uintptr_t base_ = 0;
};

extern function_mgr_type function_mgr;

}
