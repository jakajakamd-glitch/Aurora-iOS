#pragma once

#include <cstdint>

namespace ROBLOX_OFFSETS {

constexpr uintptr_t job_name       = 0x18;
constexpr uintptr_t job_name_flag  = 0x2f;
constexpr uintptr_t whsj_script_context = 0x1a8;
inline const char* whsj_name = OBF("WaitingHybridScriptsJob");

}
