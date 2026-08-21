#import "hook_mgr.hpp"
#import "../utility/utility_mgr.hpp"
#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <mach/mach_init.h>
#import <mach/thread_act.h>
#import <mach-o/dyld.h>
#import <sys/mman.h>
#import <unistd.h>
#import <string.h>
#import <errno.h>
#import <libkern/OSCacheControl.h>

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

inline uint32_t encode_b(uintptr_t from_pc, uintptr_t to_pc) {
    int64_t off = (int64_t)to_pc - (int64_t)from_pc;
    if (off < -(1LL << 27) || off >= (1LL << 27)) return 0;
    return 0x14000000u | (uint32_t)((off >> 2) & 0x03FFFFFFu);
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
            int64_t new_imm;
            if (abs >= src_pc && abs < src_pc + n * 4) {
                new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
            } else {
                new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
                if (new_imm < -(1LL << 25) || new_imm >= (1LL << 25)) return false;
            }
            insn = op | (uint32_t)(new_imm & 0x03FFFFFFu);
            return true;
        };

        auto rewrite_imm19 = [&](uint32_t op_base, uint32_t extra_bits) -> bool {
            int64_t imm19 = (insn >> 5) & 0x7FFFFu;
            if (imm19 & (1LL << 18)) imm19 |= ~((1LL << 19) - 1);
            uintptr_t abs = spc + (uintptr_t)(imm19 << 2);
            int64_t new_imm;
            if (abs >= src_pc && abs < src_pc + n * 4) {
                new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
            } else {
                new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
                if (new_imm < -(1LL << 18) || new_imm >= (1LL << 18)) return false;
            }
            insn = (insn & 0xFF00001Fu) | (uint32_t)(new_imm & 0x7FFFFu) << 5 | extra_bits;
            return true;
        };

        auto rewrite_imm14 = [&](uint32_t op_base, uint32_t extra_bits) -> bool {
            int64_t imm14 = (insn >> 5) & 0x3FFFu;
            if (imm14 & (1LL << 13)) imm14 |= ~((1LL << 14) - 1);
            uintptr_t abs = spc + (uintptr_t)(imm14 << 2);
            int64_t new_imm;
            if (abs >= src_pc && abs < src_pc + n * 4) {
                new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
            } else {
                new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
                if (new_imm < -(1LL << 13) || new_imm >= (1LL << 13)) return false;
            }
            insn = (insn & 0xFFE0001Fu) | (uint32_t)(new_imm & 0x3FFFu) << 5 | extra_bits;
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
            int64_t new_imm;
            if (abs >= src_pc && abs < src_pc + n * 4) {
                new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
            } else {
                new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
                if (new_imm < -(1LL << 18) || new_imm >= (1LL << 18)) return 0;
            }
            insn = (insn & 0xFF00001Fu) | (uint32_t)(new_imm & 0x7FFFFu) << 5 | rt;
        }
        else if ((insn & 0xFF000000u) == 0x98000000u) {
            uint32_t rt = insn & 0x1Fu;
            int64_t imm19 = (insn >> 5) & 0x7FFFFu;
            if (imm19 & (1LL << 18)) imm19 |= ~((1LL << 19) - 1);
            uintptr_t abs = spc + (uintptr_t)(imm19 << 2);
            int64_t new_imm;
            if (abs >= src_pc && abs < src_pc + n * 4) {
                new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
            } else {
                new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
                if (new_imm < -(1LL << 18) || new_imm >= (1LL << 18)) return 0;
            }
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
            int64_t new_imm;
            if (abs >= src_pc && abs < src_pc + n * 4) {
                new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
            } else {
                new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
                if (new_imm < -(1LL << 18) || new_imm >= (1LL << 18)) return 0;
            }
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
            int64_t new_imm;
            if (abs >= src_pc && abs < src_pc + n * 4) {
                new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
            } else {
                new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
                if (new_imm < -(1LL << 13) || new_imm >= (1LL << 13)) return 0;
            }
            insn = (b5 << 31) | 0x36000000u | op | (b40 << 19) |
                   (uint32_t)(new_imm & 0x3FFFu) << 5 | rt;
        }

        dst[i] = insn;
    }
    return n * 4;
}

struct RelayPage {
    void* base;
    size_t size;
    size_t used;
};

static RelayPage* g_relay_pages = nullptr;
static size_t g_relay_page_count = 0;
static const size_t kMaxRelayPages = 64;

static void* alloc_relay_page(uintptr_t near_pc) {
    if (g_relay_page_count == 0) {
        g_relay_pages = (RelayPage*)mmap(nullptr, sizeof(RelayPage) * kMaxRelayPages,
                                          PROT_READ | PROT_WRITE,
                                          MAP_PRIVATE | MAP_ANON, -1, 0);
        if (g_relay_pages == MAP_FAILED) return nullptr;
    }
    for (size_t i = 0; i < g_relay_page_count; ++i) {
        RelayPage& rp = g_relay_pages[i];
        if (rp.size - rp.used >= 0x40) {
            void* p = (void*)((uintptr_t)rp.base + rp.used);
            rp.used += 0x40;
            return p;
        }
    }
    if (g_relay_page_count >= kMaxRelayPages) return nullptr;

    uintptr_t ps = page_size();
    for (size_t i = 1; i <= 32; ++i) {
        int64_t off = ((i & 1) ? 1 : -1) * (int64_t)(i / 2 + 1) * (int64_t)ps * 32;
        void *hint = (void *)(near_pc + off);
        void *p = mmap(hint, ps, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANON | MAP_FIXED, -1, 0);
        if (p != MAP_FAILED && p != nullptr) {
            RelayPage& rp = g_relay_pages[g_relay_page_count++];
            rp.base = p;
            rp.size = ps;
            rp.used = 0x40;
            return p;
        }
        if (p == MAP_FAILED && errno != EEXIST) break;
    }
    void *p = mmap(nullptr, ps, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANON, -1, 0);
    if (p == MAP_FAILED) return nullptr;
    RelayPage& rp = g_relay_pages[g_relay_page_count++];
    rp.base = p;
    rp.size = ps;
    rp.used = 0x40;
    return p;
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

static bool patch_atomic(uintptr_t addr, uint32_t new_insn, uint32_t* old_insn_out) {
    uintptr_t ps  = page_size();
    uintptr_t lo  = page_base(addr);
    uintptr_t hi  = page_base(addr + 3) + ps;
    size_t   span = hi - lo;

    kern_return_t kr = mprotect((void *)lo, span, PROT_READ | PROT_WRITE | PROT_EXEC);
    if (kr != 0) {
        NSLog(OBF_NS("[Aurora] patch_atomic: mprotect RWX failed errno=%d"), errno);
        return false;
    }

    if (old_insn_out) {
        memcpy(old_insn_out, (void*)addr, 4);
    }

    thread_act_t self_thread = mach_thread_self();
    suspend_other_threads(self_thread);

    *(volatile uint32_t*)addr = new_insn;
    sys_icache_invalidate((void*)addr, 4);

    resume_other_threads(self_thread);
    mach_port_deallocate(mach_task_self(), self_thread);

    kr = mprotect((void *)lo, span, PROT_READ | PROT_EXEC);
    if (kr != 0) {
        NSLog(OBF_NS("[Aurora] patch_atomic: RX restore failed errno=%d — ROLLING BACK"), errno);
        thread_act_t self_thread2 = mach_thread_self();
        suspend_other_threads(self_thread2);
        *(volatile uint32_t*)addr = *old_insn_out;
        sys_icache_invalidate((void*)addr, 4);
        resume_other_threads(self_thread2);
        mach_port_deallocate(mach_task_self(), self_thread2);
        return false;
    }

    return true;
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
              (void *)absolute_address, replacement);
        return;
    }

    uintptr_t target = absolute_address;
    uintptr_t fake    = (uintptr_t)replacement;

    void *relay = alloc_relay_page(target);
    if (!relay) {
        NSLog(OBF_NS("[Aurora] hook_mgr: relay alloc failed target=%p"), (void*)target);
        return;
    }

    uint32_t b_to_relay = encode_b(target, (uintptr_t)relay);
    if (b_to_relay == 0) {
        NSLog(OBF_NS("[Aurora] hook_mgr: relay out of B-range target=%p relay=%p"),
              (void*)target, relay);
        return;
    }

    uint32_t original_insn = 0;
    memcpy(&original_insn, (void*)target, 4);

    uint32_t relocated = 0;
    size_t written = relocate_arm64(&relocated, &original_insn, 1, target, (uintptr_t)relay + 16);
    if (written != 4) {
        NSLog(OBF_NS("[Aurora] hook_mgr: relocate failed target=%p"), (void*)target);
        return;
    }

    uint32_t b_back = encode_b((uintptr_t)relay + 20, target + 4);
    if (b_back == 0) {
        NSLog(OBF_NS("[Aurora] hook_mgr: B-back out of range target=%p relay=%p"),
              (void*)target, relay);
        return;
    }

    uint32_t veneer[8];
    veneer[0] = 0x58000050u;
    veneer[1] = 0xD61F0200u;
    veneer[2] = 0;
    veneer[3] = (uint32_t)(fake & 0xFFFFFFFFu);
    veneer[4] = (uint32_t)(fake >> 32);
    veneer[5] = relocated;
    veneer[6] = b_back;
    veneer[7] = 0xD503201Fu;

    memcpy(relay, veneer, sizeof(veneer));

    kern_return_t kr = mprotect((void*)((uintptr_t)relay & ~(page_size() - 1)),
                                 page_size(), PROT_READ | PROT_EXEC);
    if (kr != 0) {
        NSLog(OBF_NS("[Aurora] hook_mgr: relay RX failed errno=%d"), errno);
        return;
    }
    sys_icache_invalidate(relay, sizeof(veneer));

    uint32_t old = 0;
    if (!patch_atomic(target, b_to_relay, &old)) {
        NSLog(OBF_NS("[Aurora] hook_mgr: patch_atomic failed target=%p"), (void*)target);
        return;
    }

    if (backup) {
        void *tramp = (void*)((uintptr_t)relay + 20);
        *backup = tramp;
    }

    NSLog(OBF_NS("[Aurora] hook_mgr: hook ok target=%p repl=%p relay=%p tramp=%p"),
          (void*)target, replacement, relay, backup ? *backup : nullptr);
}

}
