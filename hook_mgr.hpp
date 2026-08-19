#pragma once

#include <cstdint>

namespace managers {

class hook_mgr_type {
public:
    void hook(uintptr_t absolute_address, void *replacement, void **backup);
};

extern hook_mgr_type hook_mgr;

}
