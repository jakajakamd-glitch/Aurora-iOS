#import "hook_mgr.hpp"
#import "../utility/utility_mgr.hpp"
#import <Foundation/Foundation.h>
#include <dobby.h>

namespace managers {

hook_mgr_type hook_mgr;

void hook_mgr_type::start() {
    NSLog(OBF_NS("[Aurora] hook_mgr::start"));
    utility::utility_mgr.log(OBF("hook_mgr::start"));
}

void hook_mgr_type::hook(uintptr_t absolute_address, void *replacement, void **backup) {
    if (backup) {
        *backup = nullptr;
    }
    if (absolute_address == 0 || !replacement) {
        utility::utility_mgr.log(OBF("hook_mgr: invalid hook input"));
        return;
    }

    int status = DobbyHook((void*)absolute_address, replacement, backup);
    utility::utility_mgr.log([[NSString stringWithFormat:OBF_NS("hook_mgr: dobby status=%d target=%p replacement=%p origin=%p"), status, (void*)absolute_address, replacement, backup ? *backup : nullptr] UTF8String]);
}

}
