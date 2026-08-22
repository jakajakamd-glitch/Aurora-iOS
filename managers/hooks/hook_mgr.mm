#import "hook_mgr.hpp"
#import "../utility/utility_mgr.hpp"
#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <mach/mach_init.h>
#import <mach/thread_act.h>
#import <mach/vm_map.h>
#import <mach-o/dyld.h>
#import <sys/mman.h>
#import <unistd.h>
#import <string.h>
#import <errno.h>

#ifndef VM_PROT_COPY
#define VM_PROT_COPY ((vm_prot_t)0x40)
#endif

namespace managers {

hook_mgr_type hook_mgr;

namespace {

inline uintptr_t page_base(uintptr_t addr) {
    uintptr_t ps = (uintptr_t)sysconf(_SC_PAGESIZE);
    return addr & ~(ps - 1);
}

inline uintptr_t page_size(void) {
    return (uintptr_t)sysconf(_SC_PAGESIZE);
}

static size_t relocate_arm64(uint32_t *dst, const uint32_t *src, size_t n,
                              uintptr_t src_pc, uintptr_t dst_pc) {
    for (size_t i = 0; i < n; ++i) {
        uint32_t insn = src[i];
        uintptr_t spc = src_pc + i * 4;
        uintptr_t dpc = dst_pc + i * 4;

        auto rewrite_imm26 = [&](uint32_t op) -> bool {
            int64_t imm26 = insn & 0x03FFFFFFu;
            if (imm26 & (1LL << 25)) imm26 |= ~((1LL << 26) - 1);
            uintptr_t abs = spc + (uintptr_t)(imm26 << 2);
            int64_t new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
            if (new_imm < -(1LL << 25) || new_imm >= (1LL << 25)) return false;
            insn = op | (uint32_t)(new_imm & 0x03FFFFFFu);
            return true;
        };

        auto rewrite_imm19 = [&](uint32_t op_base, uint32_t extra_bits) -> bool {
            int64_t imm19 = (insn >> 5) & 0x7FFFFu;
            if (imm19 & (1LL << 18)) imm19 |= ~((1LL << 19) - 1);
            uintptr_t abs = spc + (uintptr_t)(imm19 << 2);
            int64_t new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
            if (new_imm < -(1LL << 18) || new_imm >= (1LL << 18)) return false;
            insn = (insn & 0xFF00001Fu) | (uint32_t)(new_imm & 0x7FFFFu) << 5 | extra_bits;
            return true;
        };

        if ((insn & 0x9F000000u) == 0x90000000u) {
            uint32_t rd = insn & 0x1Fu;
            int64_t immlo = (insn >> 29) & 0x3u;
            int64_t immhi = (insn >> 5) & 0x7FFFFu;
            int64_t imm = (immhi << 2) | immlo;
            if (imm & (1LL << 20)) imm |= ~((1LL << 21) - 1);
            uintptr_t abs_page = (spc & ~0xFFFULL) + (uintptr_t)(imm << 12);
            int64_t new_imm = (int64_t)((abs_page & ~0xFFFULL) >> 12) - (int64_t)((dpc & ~0xFFFULL) >> 12);
            if (new_imm < -(1LL << 20) || new_imm >= (1LL << 20)) return 0;
            uint32_t nlo = (uint32_t)(new_imm & 0x3u);
            uint32_t nhi = (uint32_t)((new_imm >> 2) & 0x7FFFFu);
            insn = 0x90000000u | (nlo << 29) | (nhi << 5) | rd;
        }
        else if ((insn & 0x9F000000u) == 0x10000000u) {
            uint32_t rd = insn & 0x1Fu;
            int64_t immlo = (insn >> 29) & 0x3u;
            int64_t immhi = (insn >> 5) & 0x7FFFFu;
            int64_t imm = (immhi << 2) | immlo;
            if (imm & (1LL << 20)) imm |= ~((1LL << 21) - 1);
            uintptr_t abs = spc + (uintptr_t)imm;
            int64_t new_imm = (int64_t)abs - (int64_t)dpc;
            if (new_imm < -(1LL << 20) || new_imm >= (1LL << 20)) return 0;
            uint32_t nlo = (uint32_t)(new_imm & 0x3u);
            uint32_t nhi = (uint32_t)((new_imm >> 2) & 0x7FFFFu);
            insn = 0x10000000u | (nlo << 29) | (nhi << 5) | rd;
        }
        else if ((insn & 0xBF000000u) == 0x18000000u) {
            uint32_t rt = insn & 0x1Fu;
            int64_t imm19 = (insn >> 5) & 0x7FFFFu;
            if (imm19 & (1LL << 18)) imm19 |= ~((1LL << 19) - 1);
            uintptr_t abs = spc + (uintptr_t)(imm19 << 2);
            int64_t new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
            if (new_imm < -(1LL << 18) || new_imm >= (1LL << 18)) return 0;
            insn = (insn & 0xFF00001Fu) | (uint32_t)(new_imm & 0x7FFFFu) << 5 | rt;
        }
        else if ((insn & 0xFF000000u) == 0x98000000u) {
            uint32_t rt = insn & 0x1Fu;
            int64_t imm19 = (insn >> 5) & 0x7FFFFu;
            if (imm19 & (1LL << 18)) imm19 |= ~((1LL << 19) - 1);
            uintptr_t abs = spc + (uintptr_t)(imm19 << 2);
            int64_t new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
            if (new_imm < -(1LL << 18) || new_imm >= (1LL << 18)) return 0;
            insn = (insn & 0xFF00001Fu) | (uint32_t)(new_imm & 0x7FFFFu) << 5 | rt;
        }
        else if ((insn & 0x7C000000u) == 0x14000000u) {
            uint32_t op = insn & 0xFC000000u;
            if (!rewrite_imm26(op)) return 0;
        }
        else if ((insn & 0xFF000010u) == 0x54000000u) {
            uint32_t cond = insn & 0xFu;
            if (!rewrite_imm19(0x54000000u, cond)) return 0;
        }
        else if ((insn & 0x7E000000u) == 0x34000000u) {
            uint32_t sf = insn & 0x80000000u;
            uint32_t op = insn & 0x01000000u;
            uint32_t rt = insn & 0x1Fu;
            int64_t imm19 = (insn >> 5) & 0x7FFFFu;
            if (imm19 & (1LL << 18)) imm19 |= ~((1LL << 19) - 1);
            uintptr_t abs = spc + (uintptr_t)(imm19 << 2);
            int64_t new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
            if (new_imm < -(1LL << 18) || new_imm >= (1LL << 18)) return 0;
            insn = sf | 0x34000000u | op | (uint32_t)(new_imm & 0x7FFFFu) << 5 | rt;
        }
        else if ((insn & 0x7E000000u) == 0x36000000u) {
            uint32_t b5 = (insn >> 31) & 0x1u;
            uint32_t op = insn & 0x01000000u;
            uint32_t rt = insn & 0x1Fu;
            uint32_t b40 = (insn >> 19) & 0x1Fu;
            int64_t imm14 = (insn >> 5) & 0x3FFFu;
            if (imm14 & (1LL << 13)) imm14 |= ~((1LL << 14) - 1);
            uintptr_t abs = spc + (uintptr_t)(imm14 << 2);
            int64_t new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
            if (new_imm < -(1LL << 13) || new_imm >= (1LL << 13)) return 0;
            insn = (b5 << 31) | 0x36000000u | op | (b40 << 19) |
                   (uint32_t)(new_imm & 0x3FFFu) << 5 | rt;
        }

        dst[i] = insn;
    }
    return n * 4;
}

static void* find_trampoline_slot(uintptr_t scan_lo, uintptr_t scan_hi,
                                  uintptr_t avoid_lo, uintptr_t avoid_hi,
                                  size_t slots_needed) {
    uint32_t* begin = (uint32_t*)scan_lo;
    uint32_t* end   = (uint32_t*)scan_hi;
    size_t run = 0;
    uint32_t* run_start = nullptr;

    for (uint32_t* p = begin; p < end; ++p) {
        uintptr_t addr = (uintptr_t)p;
        if (addr >= avoid_lo && addr < avoid_hi) {
            run = 0;
            run_start = nullptr;
            continue;
        }
        uint32_t val = *p;
        if (val == 0xD503201Fu || val == 0x00000000u) {
            if (run == 0) run_start = p;
            ++run;
            if (run >= slots_needed) return (void*)run_start;
        } else {
            run = 0;
            run_start = nullptr;
        }
    }
    return nullptr;
}

static void suspend_other_threads(thread_act_t current) {
    thread_act_array_t threads;
    mach_msg_type_number_t count;
    if (task_threads(mach_task_self(), &threads, &count) != KERN_SUCCESS) return;
    for (mach_msg_type_number_t i = 0; i < count; ++i) {
        if (threads[i] != current) {
            thread_suspend(threads[i]);
        }
        mach_port_deallocate(mach_task_self(), threads[i]);
    }
}

static void resume_other_threads(thread_act_t current) {
    thread_act_array_t threads;
    mach_msg_type_number_t count;
    if (task_threads(mach_task_self(), &threads, &count) != KERN_SUCCESS) return;
    for (mach_msg_type_number_t i = 0; i < count; ++i) {
        if (threads[i] != current) {
            thread_resume(threads[i]);
        }
        mach_port_deallocate(mach_task_self(), threads[i]);
    }
}

static void invalidate_icache(void* addr, size_t len) {
    __builtin___clear_cache((char*)addr, (char*)addr + len);
}

}

void hook_mgr_type::start() {
    NSLog(OBF_NS("[Aurora] hook_mgr::start"));
    utility::utility_mgr.log(OBF("hook_mgr::start"));
}

void hook_mgr_type::hook(uintptr_t absolute_address, void *replacement, void **backup) {
    if (backup) *backup = nullptr;
    if (absolute_address == 0 || replacement == nullptr) {
        NSLog(OBF_NS("[Aurora] hook_mgr: refusing null input addr=%p repl=%p"),
              (void*)absolute_address, replacement);
        return;
    }

    uintptr_t target = absolute_address;
    uintptr_t fake   = (uintptr_t)replacement;
    uintptr_t ps     = page_size();
    uintptr_t pg_lo  = page_base(target);
    uintptr_t pg_hi  = pg_lo + ps;

    static const size_t kOverwrittenSlots = 4;
    static const size_t kPatchBytes       = kOverwrittenSlots * 4;
    static const size_t kTrampSlots       = kOverwrittenSlots + 1;
    static const size_t kTrampBytes       = kTrampSlots * 4;

    uint32_t original_insns[kOverwrittenSlots];
    memcpy(original_insns, (void*)target, kPatchBytes);

    kern_return_t kr;

    kr = vm_protect(mach_task_self(),
                    (vm_address_t)pg_lo,
                    (vm_size_t)ps,
                    FALSE,
                    VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    if (kr != KERN_SUCCESS) {
        kr = vm_protect(mach_task_self(),
                        (vm_address_t)pg_lo,
                        (vm_size_t)ps,
                        FALSE,
                        VM_PROT_READ | VM_PROT_WRITE);
    }
    if (kr != KERN_SUCCESS) {
        NSLog(OBF_NS("[Aurora] hook_mgr: vm_protect RW failed kr=%d target=%p"), kr, (void*)target);
        return;
    }

    void* tramp_slot = find_trampoline_slot(pg_lo, pg_hi,
                                            target, target + kPatchBytes,
                                            kTrampSlots);
    if (!tramp_slot) {
        NSLog(OBF_NS("[Aurora] hook_mgr: no trampoline space in page target=%p"), (void*)target);
        vm_protect(mach_task_self(), (vm_address_t)pg_lo, (vm_size_t)ps,
                   FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
        return;
    }

    uintptr_t tramp_addr = (uintptr_t)tramp_slot;

    uint32_t relocated[kOverwrittenSlots];
    size_t written = relocate_arm64(relocated, original_insns, kOverwrittenSlots,
                                    target, tramp_addr);
    if (written != kPatchBytes) {
        NSLog(OBF_NS("[Aurora] hook_mgr: relocate failed target=%p"), (void*)target);
        vm_protect(mach_task_self(), (vm_address_t)pg_lo, (vm_size_t)ps,
                   FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
        return;
    }

    int64_t b_back_off = (int64_t)(target + kPatchBytes) - (int64_t)(tramp_addr + kPatchBytes);
    if (b_back_off < -(1LL << 27) || b_back_off >= (1LL << 27)) {
        NSLog(OBF_NS("[Aurora] hook_mgr: B-back out of range target=%p tramp=%p"),
              (void*)target, (void*)tramp_addr);
        vm_protect(mach_task_self(), (vm_address_t)pg_lo, (vm_size_t)ps,
                   FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
        return;
    }
    uint32_t b_back = 0x14000000u | (uint32_t)((b_back_off >> 2) & 0x03FFFFFFu);

    thread_act_t self_thread = mach_thread_self();
    suspend_other_threads(self_thread);

    memcpy(tramp_slot, relocated, kPatchBytes);
    *(uint32_t*)((uintptr_t)tramp_slot + kPatchBytes) = b_back;

    uint32_t patch[kOverwrittenSlots];
    patch[0] = 0x58000050u;
    patch[1] = 0xD61F0200u;
    patch[2] = (uint32_t)(fake & 0xFFFFFFFFu);
    patch[3] = (uint32_t)(fake >> 32);
    memcpy((void*)target, patch, kPatchBytes);

    invalidate_icache((void*)target, kPatchBytes);
    invalidate_icache(tramp_slot, kTrampBytes);

    resume_other_threads(self_thread);
    mach_port_deallocate(mach_task_self(), self_thread);

    kr = vm_protect(mach_task_self(),
                    (vm_address_t)pg_lo,
                    (vm_size_t)ps,
                    FALSE,
                    VM_PROT_READ | VM_PROT_EXECUTE);
    if (kr != KERN_SUCCESS) {
        NSLog(OBF_NS("[Aurora] hook_mgr: RX restore failed kr=%d — page left RW"), kr);
        return;
    }

    if (backup) {
        *backup = tramp_slot;
    }

    NSLog(OBF_NS("[Aurora] hook_mgr: hook ok target=%p repl=%p tramp=%p"),
          (void*)target, replacement, tramp_slot);
}

}