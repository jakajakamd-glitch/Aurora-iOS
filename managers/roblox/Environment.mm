#import "environment.hpp"
#import "../core/core.hpp"
#import "../core/hookmetamethod.hpp"
#include "lua.h"
#include "Luau/Compiler.h"
#include <string>

namespace managers {

environment_manager_t environment_manager;

namespace environment {

namespace {

class lua_thread_script final : public thread_script {
public:
    lua_thread_script(lua_State* thread, const char* source, size_t size)
        : thread_(thread), source_(source ? source : "", size) {}

    bool make(std::string& bytecode) override {
        if (!thread_ || source_.empty()) {
            return false;
        }

        int base = lua_gettop(thread_);
        lua_getglobal(thread_, OBF("Instance"));
        if (lua_type(thread_, -1) == LUA_TNIL) {
            lua_settop(thread_, base);
            return false;
        }

        lua_getfield(thread_, -1, OBF("new"));
        if (lua_type(thread_, -1) != LUA_TFUNCTION) {
            lua_settop(thread_, base);
            return false;
        }

        lua_remove(thread_, -2);
        lua_pushstring(thread_, OBF("LocalScript"));
        lua_call(thread_, 1, 1);
        if (lua_type(thread_, -1) == LUA_TNIL) {
            lua_settop(thread_, base);
            return false;
        }

        lua_setglobal(thread_, OBF("script"));
        lua_settop(thread_, base);

        bytecode = Luau::compile(source_);
        return !bytecode.empty();
    }

private:
    lua_State* thread_;
    std::string source_;
};

}

thread_script* thread_script::create(lua_State* thread, const char* source, size_t size) {
    return new lua_thread_script(thread, source, size);
}

}

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
    lua_pushcclosurek(thread, core::clonefunction, OBF("clonefunction"), 0, nullptr);
    lua_setglobal(thread, OBF("clonefunction"));
    lua_pushcclosurek(thread, core::getinstances, OBF("getinstances"), 0, nullptr);
    lua_setglobal(thread, OBF("getinstances"));
    lua_pushcclosurek(thread, core::hookfunction, OBF("hookfunction"), 0, nullptr);
    lua_setglobal(thread, OBF("hookfunction"));
    int hookmetamethod_base = lua_gettop(thread);
    std::string hookmetamethod_bytecode = Luau::compile(core::hookmetamethod_script);
    if (luau_load(thread, OBF("=hookmetamethod"), hookmetamethod_bytecode.data(), hookmetamethod_bytecode.size(), 0) == 0 && lua_pcall(thread, 0, 1, 0) == 0 && lua_type(thread, -1) == LUA_TFUNCTION) {
        lua_setglobal(thread, OBF("hookmetamethod"));
    } else {
        lua_settop(thread, hookmetamethod_base);
    }
    lua_pushcclosurek(thread, core::newcclosure, OBF("newcclosure"), 0, nullptr);
    lua_setglobal(thread, OBF("newcclosure"));
    lua_pushcclosurek(thread, core::run_on_actor, OBF("run_on_actor"), 0, nullptr);
    lua_setglobal(thread, OBF("run_on_actor"));
}

}
