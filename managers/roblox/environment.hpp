#pragma once

#include <cstddef>
#include <string>

struct lua_State;

namespace managers {

namespace environment {

class thread_script {
public:
    virtual ~thread_script() = default;
    virtual bool make(std::string& bytecode) = 0;
    static thread_script* create(lua_State* thread, const char* source, size_t size);
};

}

class environment_manager_t {
public:
    void load_environment(lua_State* thread);

};

extern environment_manager_t environment_manager;

}

