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
    static constexpr uintptr_t executorToScriptContext_offset = 0x179c624;
    static constexpr uintptr_t getGlobalState_offset = 0x1767794;
    static constexpr uintptr_t vmLoad_offset       = 0x0438dc50;
    static constexpr uintptr_t newThread_offset    = 0x04364490;
    static constexpr uintptr_t loadString_offset   = 0x0174c5f0;
    static constexpr uintptr_t luaResume_offset    = 0x04370cf0;
    static constexpr uintptr_t luauExecute_offset  = 0x4389148;
    static constexpr uintptr_t getCapabilityTable_offset = 0x01766d5c;
    static constexpr uintptr_t setProtoCaps_offset = 0x0176361c;
    static constexpr uintptr_t gameLoaded_offset = 0x0494004;

    void* get_global_state(void* scriptctx);
    void* new_thread(void* L);
    void  start_script(void* ctx, void* script_start);
    int   vm_load(void* L, const char* name, const char* data, int mode, int flags);
    int   load_string(void* L);
    int   lua_resume(void* L, void* from, int nargs);
    void  luau_execute(void* L);
    void* get_capability_table(void* scriptctx, uint64_t caps);
    void  set_proto_caps(void* L, int index, void* capability_table);

private:
    uintptr_t base_ = 0;
};

extern function_mgr_type function_mgr;

}
