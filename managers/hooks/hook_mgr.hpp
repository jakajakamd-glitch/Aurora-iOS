#pragma once

#include <cstdint>

namespace managers {

class hook_mgr_type {
public:
    void start();
    bool hook(uintptr_t target,
              void* replacement,
              void** backup,
              void* trampoline,
              uintptr_t* return_slot,
              const uint32_t expected[4]);
};

extern hook_mgr_type hook_mgr;

}

extern "C" {
extern uintptr_t aurora_job_start_return;
extern uintptr_t aurora_start_script_return;
extern uintptr_t aurora_game_loaded_return;
void aurora_job_start_trampoline(void*, void*);
void aurora_start_script_trampoline(void*, void*);
void aurora_game_loaded_trampoline(void*, void*);
}
