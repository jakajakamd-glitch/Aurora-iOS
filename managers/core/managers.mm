#import "../functions/function_mgr.hpp"
#import "../hooks/hook_mgr.hpp"
#import "../roblox/Roblox.hpp"
#import "../utility/utility_mgr.hpp"
#import "managers.hpp"
#import <Foundation/Foundation.h>

namespace managers {

static uintptr_t g_base = 0;

void start_all(uintptr_t base) {
    g_base = base;
    function_mgr.start(base);
    hook_mgr.start();
    roblox_manager.start();
    utility::utility_mgr.start();
    utility::utility_mgr.log([[NSString stringWithFormat:OBF_NS("all managers started base=%p"), (void*)base] UTF8String]);
}

uintptr_t current_base() { return g_base; }

}
