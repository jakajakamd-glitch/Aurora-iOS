#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <dispatch/dispatch.h>
#import "hook_mgr.hpp"
#import "function_mgr.hpp"

static const struct mach_header *find_image_header(NSString *image_basename) {
    const uint32_t image_count = _dyld_image_count();
    for (uint32_t index = 0; index < image_count; ++index) {
        const char *image_name = _dyld_get_image_name(index);
        if (image_name == nullptr) continue;
        NSString *path = [NSString stringWithUTF8String:image_name];
        NSString *basename = [path lastPathComponent];
        if ([basename caseInsensitiveCompare:image_basename] == NSOrderedSame) {
            return _dyld_get_image_header(index);
        }
    }
    return nullptr;
}

static void (*orig_startScript)(void *, void *) = nullptr;

static void hook_startScript(void *arg1, void *arg2) {
    void *gs = managers::function_mgr.get_global_state(arg1);
    NSLog(@"[Aurora] startScript this=%p scriptStart=%p GlobalState=%p", arg1, arg2, gs);
    orig_startScript(arg1, arg2);
}

static void install_hooks(uintptr_t base) {
    void *target = managers::function_mgr.resolve(0x179b568);
    managers::hook_mgr.hook(reinterpret_cast<uintptr_t>(target),
                            (void *)hook_startScript,
                            (void **)&orig_startScript);
}

__attribute__((constructor)) static void aurora_initialize(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        for (NSUInteger attempt = 0; attempt < 100; ++attempt) {
            const struct mach_header *header = find_image_header(@"RobloxLib");
            if (header != nullptr) {
                uintptr_t base = reinterpret_cast<uintptr_t>(header);
                managers::function_mgr.init(base);
                install_hooks(base);
                return;
            }
            [NSThread sleepForTimeInterval:0.1];
        }
    });
}
