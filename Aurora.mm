#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <dispatch/dispatch.h>
#import "function_mgr.hpp"
#import "hook_mgr.hpp"
#import "Roblox.hpp"
#import "managers.hpp"

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

__attribute__((constructor)) static void aurora_initialize(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        for (NSUInteger attempt = 0; attempt < 100; ++attempt) {
            const struct mach_header *header = find_image_header(@"RobloxLib");
            if (header != nullptr) {
                uintptr_t base = reinterpret_cast<uintptr_t>(header);
                managers::start_all(base);
                return;
            }
            [NSThread sleepForTimeInterval:0.1];
        }
    });
}
