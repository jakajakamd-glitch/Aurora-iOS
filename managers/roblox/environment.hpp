#pragma once

struct lua_State;

namespace managers {

class environment_manager_t {
public:
    void load_environment(lua_State* thread);

};

extern environment_manager_t environment_manager;

}

