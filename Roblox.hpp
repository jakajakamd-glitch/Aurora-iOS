#pragma once

#include <cstdint>

struct lua_State;

namespace managers {

class hook_mgr_type;
class function_mgr_type;

struct script_context;
struct ScriptStart;
struct Job;

class roblox_manager_t {
public:
    void start();
    void install_hooks();

    static const char* get_job_name(Job* job);
    static struct script_context* get_script_context_from_whsj(Job* whsj);
    static bool is_whsj(Job* job);

    struct script_context* get_global_state(struct script_context* ctx);
    lua_State* lua_newthread(lua_State* L);
    void start_script(struct script_context* ctx, ScriptStart* script_start);

    struct script_context* select_global_state_handle(struct script_context* sc, uint64_t classification);

    void setup_environment(Job* whsj);

    struct script_context* sc()      const { return sc_; }
    struct script_context* gs()      const { return gs_; }
    lua_State*             thread()  const { return thread_; }

private:
    struct script_context* sc_     = nullptr;
    struct script_context* gs_     = nullptr;
    lua_State*             thread_ = nullptr;
};

extern roblox_manager_t roblox_manager;

}
