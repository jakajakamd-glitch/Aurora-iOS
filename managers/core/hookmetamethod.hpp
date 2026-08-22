#pragma once

#include <cstdint>

struct lua_State;

namespace managers::core {

std::int32_t hookmetamethod(lua_State* L);

}
