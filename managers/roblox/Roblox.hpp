#pragma once

#include <cstdint>

struct lua_State;

namespace managers {

class hook_mgr_type;
class function_mgr_type;

struct script_context;
struct ScriptStart;
struct Job;

namespace capabilities {
    enum : uint64_t {
        roblox_script = 0x2000000000000003ULL,
        fallback      = 0x003fffffffffff00ULL,
    };
}

class roblox_manager_t {
public:
    void start();
    void install_hooks();

    static const char* get_job_name(Job* job);
    static struct script_context* get_script_context_from_whsj(Job* whsj);
    static bool is_whsj(Job* job);

    void* get_global_state(struct script_context* ctx, uint64_t caps);
    lua_State* lua_newthread(lua_State* L);
    void start_script(struct script_context* ctx, ScriptStart* script_start);

    void setup_environment(Job* whsj);
    void set_identity(lua_State* thread, uint32_t identity);

    int execute_script(const char* source, size_t size, const char* chunkname);

    struct script_context* scriptctx   = nullptr;
    void*                  selected_state = nullptr;
    lua_State*             thread      = nullptr;
};

extern roblox_manager_t roblox_manager;

}
