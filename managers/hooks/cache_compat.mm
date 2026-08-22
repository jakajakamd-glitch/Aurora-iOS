#import <libkern/OSCacheControl.h>

extern "C" void clear_cache_compat(char* begin, char* end) __asm__("___clear_cache");

extern "C" void clear_cache_compat(char* begin, char* end) {
    sys_icache_invalidate(begin, (size_t)(end - begin));
}
