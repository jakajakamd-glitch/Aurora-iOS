#import "../functions/function_mgr.hpp"
#import "../hooks/hook_mgr.hpp"
#import "../roblox/Roblox.hpp"
#import "managers.hpp"
#import <Foundation/Foundation.h>

namespace managers {

static uintptr_t g_base = 0;

void start_all(uintptr_t base) {
    g_base = base;
    function_mgr.start(base);
    hook_mgr.start();
    roblox_manager.start();
    NSLog(@"[Aurora] all managers started (base=%p)", (void*)base);
}

uintptr_t current_base() { return g_base; }

}
