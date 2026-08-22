#pragma once

#include <cstdint>

struct lua_State;

namespace managers::core {

std::int32_t getsenv(lua_State* L);
std::int32_t getrenv(lua_State* L);
std::int32_t getgenv(lua_State* L);
std::int32_t loadstring(lua_State* L);
std::int32_t clonefunction(lua_State* L);
std::int32_t getinstances(lua_State* L);
std::int32_t hookfunction(lua_State* L);
std::int32_t newcclosure(lua_State* L);
std::int32_t run_on_actor(lua_State* L);
void on_game_loaded(void* sender, void* data);

}
