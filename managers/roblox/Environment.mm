#import "environment.hpp"
#import "../core/core.hpp"
#include "lua.h"

namespace managers {

environment_manager_t environment_manager;

void environment_manager_t::load_environment(lua_State* thread) {
    if (!thread) {
        return;
    }

    lua_pushcclosurek(thread, core::getsenv, OBF("getsenv"), 0, nullptr);
    lua_setglobal(thread, OBF("getsenv"));
    lua_pushcclosurek(thread, core::getrenv, OBF("getrenv"), 0, nullptr);
    lua_setglobal(thread, OBF("getrenv"));
    lua_pushcclosurek(thread, core::getgenv, OBF("getgenv"), 0, nullptr);
    lua_setglobal(thread, OBF("getgenv"));
    lua_pushcclosurek(thread, core::loadstring, OBF("loadstring"), 0, nullptr);
    lua_setglobal(thread, OBF("loadstring"));
    lua_pushcclosurek(thread, core::run_on_actor, OBF("run_on_actor"), 0, nullptr);
    lua_setglobal(thread, OBF("run_on_actor"));
}

}
