#import "hook_mgr.hpp"
#import "../utility/utility_mgr.hpp"
#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <mach/mach_init.h>
#import <mach/vm_map.h>
#import <sys/mman.h>
#import <unistd.h>
#import <string.h>

namespace managers {

hook_mgr_type hook_mgr;

namespace {

inline uintptr_t page_base(uintptr_t address) {
    uintptr_t size = (uintptr_t)sysconf(_SC_PAGESIZE);
    return address & ~(size - 1);
}

inline uintptr_t page_size() {
    return (uintptr_t)sysconf(_SC_PAGESIZE);
}

bool target_matches(uintptr_t target, const uint32_t expected[4], uint32_t actual[4]) {
    memcpy(actual, (const void*)target, sizeof(uint32_t) * 4);
    return memcmp(actual, expected, sizeof(uint32_t) * 4) == 0;
}

bool already_patched(const uint32_t actual[4]) {
    return actual[0] == 0x58000050u && actual[1] == 0xd61f0200u;
}

bool make_page_writable(uintptr_t page, uintptr_t size) {
    kern_return_t status = vm_protect(mach_task_self(),
                                      (vm_address_t)page,
                                      (vm_size_t)size,
                                      FALSE,
                                      VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (status == KERN_SUCCESS) return true;
    status = vm_protect(mach_task_self(),
                        (vm_address_t)page,
                        (vm_size_t)size,
                        FALSE,
                        VM_PROT_READ | VM_PROT_WRITE);
    return status == KERN_SUCCESS;
}

void make_page_executable(uintptr_t page, uintptr_t size) {
    vm_protect(mach_task_self(),
               (vm_address_t)page,
               (vm_size_t)size,
               FALSE,
               VM_PROT_READ | VM_PROT_EXECUTE);
}

void invalidate_icache(void* address, size_t size) {
    __builtin___clear_cache((char*)address, (char*)address + size);
}

}

void hook_mgr_type::start() {
    NSLog(OBF_NS("[Aurora] hook_mgr::start"));
    utility::utility_mgr.log(OBF("hook_mgr::start"));
}

bool hook_mgr_type::hook(uintptr_t target,
                         void* replacement,
                         void** backup,
                         void* trampoline,
                         uintptr_t* return_slot,
                         const uint32_t expected[4]) {
    if (backup) *backup = nullptr;
    if (!target || !replacement || !trampoline || !return_slot || !expected) {
        NSLog(OBF_NS("[Aurora] hook_mgr: invalid hook arguments"));
        return false;
    }
    uint32_t actual[4];
    if (!target_matches(target, expected, actual) && !already_patched(actual)) {
        NSLog(OBF_NS("[Aurora] hook_mgr: prologue mismatch target=%p words=%08x %08x %08x %08x"),
              (void*)target, actual[0], actual[1], actual[2], actual[3]);
        return false;
    }
    if (already_patched(actual)) {
        NSLog(OBF_NS("[Aurora] hook_mgr: replacing existing patch target=%p"), (void*)target);
    }

    uintptr_t size = page_size();
    uintptr_t page = page_base(target);
    if (!make_page_writable(page, size)) {
        NSLog(OBF_NS("[Aurora] hook_mgr: target page not writable target=%p"), (void*)target);
        return false;
    }

    *return_slot = target + 16;
    uint32_t patch[4] = {
        0x58000050u,
        0xD61F0200u,
        (uint32_t)((uintptr_t)replacement & 0xffffffffu),
        (uint32_t)(((uintptr_t)replacement >> 32) & 0xffffffffu)
    };
    memcpy((void*)target, patch, sizeof(patch));
    invalidate_icache((void*)target, sizeof(patch));
    invalidate_icache(trampoline, 32);
    make_page_executable(page, size);

    if (backup) *backup = trampoline;
    NSLog(OBF_NS("[Aurora] hook_mgr: installed target=%p replacement=%p trampoline=%p"),
          (void*)target, replacement, trampoline);
    return true;
}

}
