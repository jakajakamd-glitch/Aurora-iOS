#import "hook_mgr.hpp"
#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <mach/vm_prot.h>
#import <mach-o/dyld.h>
#import <sys/mman.h>
#import <unistd.h>
#import <string.h>
#import <errno.h>
#import <libkern/OSCacheControl.h>

// =============================================================================
// arm64 inline-hook, fully custom. no Dobby.
//
// patch shape at target:
//   near (|fake-target| <= 128MB):  B fake                (1 insn, 4 bytes)
//   far  (otherwise)              :  LDR x16,[pc,#8]; BR x16; .quad fake  (16 B, 4 insn slots)
//
// trampoline page (what *backup points at):
//   [0..patch_len)    : relocated copy of the original instructions we displaced
//   [patch_len..+4)   : B (target + patch_len)   // jump back to original code
//
// the mprotect dance is the same on both pages:
//   RW -> memcpy -> RX -> sys_icache_invalidate
// arm64 has split i/d caches; skipping the invalidate = stale garbage on device.
// =============================================================================

namespace {

inline uintptr_t page_base(uintptr_t addr) {
    uintptr_t ps = (uintptr_t)sysconf(_SC_PAGESIZE);
    return addr & ~(ps - 1);
}

inline uintptr_t page_size(void) {
    return (uintptr_t)sysconf(_SC_PAGESIZE);
}

// --- arm64 instruction encoders ---------------------------------------------

// B imm26 : 0b000101 | imm26   range ±128MB
// returns 0 if out of range
inline uint32_t encode_b(uintptr_t from_pc, uintptr_t to_pc) {
    int64_t off = (int64_t)to_pc - (int64_t)from_pc;
    if (off < -(1LL << 27) || off >= (1LL << 27)) return 0;
    uint32_t imm26 = (uint32_t)((off >> 2) & 0x03FFFFFFu);
    return 0x14000000u | imm26;
}

// BL imm26 : 0b100101 | imm26
inline uint32_t encode_bl(uintptr_t from_pc, uintptr_t to_pc) {
    int64_t off = (int64_t)to_pc - (int64_t)from_pc;
    if (off < -(1LL << 27) || off >= (1LL << 27)) return 0;
    uint32_t imm26 = (uint32_t)((off >> 2) & 0x03FFFFFFu);
    return 0x94000000u | imm26;
}

// LDR x16, [pc, #8]   -> 0x58000050   (opc=01, V=0, imm19=2, Rt=16)
// BR x16              -> 0xD61F0200
struct far_branch {
    uint32_t ldr_x16_lit;  // 0x58000050
    uint32_t br_x16;       // 0xD61F0200
    uint64_t target_addr;
};
static_assert(sizeof(far_branch) == 16, "far_branch must be 16 bytes");

// --- arm64 pc-relative rewriter ---------------------------------------------
//
// copy n instructions from src to dst, rewriting pc-relative addressing so the
// absolute target stays the same. handles the common cases:
//   ADRP Xn, #imm21     (0x90000000 / 0x9F000000)
//   ADR  Xn, #imm21     (0x10000000 / 0x9F000000)
//   LDR  Xt, #imm19 lit (0x18000000 / 0xBF000000)
//   B    offset         (0x14000000 / 0xFC000000)
//   BL   offset         (0x94000000 / 0xFC000000)
//   B.cond              (0x54000000 / 0xFF000010)
//   CBZ/CBNZ            (0x34000000 / 0x7E000000)
//   TBZ/TBNZ            (0x36000000 / 0x7E000000)
//
// if a branch target is itself inside the relocated window, we rewrite it to
// land inside the trampoline (i.e. it keeps pointing at the same insn).
// anything not matched is copied verbatim.
//
// returns the number of bytes written (n*4) or 0 on an unrelocatable insn.
static size_t relocate_arm64(uint32_t *dst, const uint32_t *src, size_t n,
                              uintptr_t src_pc, uintptr_t dst_pc) {
    for (size_t i = 0; i < n; ++i) {
        uint32_t insn = src[i];
        uintptr_t spc = src_pc + i * 4;
        uintptr_t dpc = dst_pc + i * 4;
        int64_t shift = (int64_t)dpc - (int64_t)spc;

        // ADRP Xn, #imm21
        if ((insn & 0x9F000000u) == 0x90000000u) {
            uint32_t rd = insn & 0x1Fu;
            int64_t immlo = (insn >> 29) & 0x3u;
            int64_t immhi = (insn >> 5) & 0x7FFFFu;
            int64_t imm = (immhi << 2) | immlo;
            // sign-extend 21 bits
            if (imm & (1LL << 20)) imm |= ~((1LL << 21) - 1);
            // absolute page base targeted by the adrp at src
            uintptr_t abs_page = (spc & ~0xFFFULL) + (uintptr_t)(imm << 12);
            int64_t new_imm = (int64_t)((abs_page & ~0xFFFULL) >> 12) - (int64_t)((dpc & ~0xFFFULL) >> 12);
            // imm is 21-bit signed, range check
            if (new_imm < -(1LL << 20) || new_imm >= (1LL << 20)) {
                NSLog(@"[Aurora] relocate: ADRP overflow imm=%lld", new_imm);
                return 0;
            }
            uint32_t nlo = (uint32_t)(new_imm & 0x3u);
            uint32_t nhi = (uint32_t)((new_imm >> 2) & 0x7FFFFu);
            insn = 0x90000000u | (nlo << 29) | (nhi << 5) | rd;
        }
        // ADR Xn, #imm21
        else if ((insn & 0x9F000000u) == 0x10000000u) {
            uint32_t rd = insn & 0x1Fu;
            int64_t immlo = (insn >> 29) & 0x3u;
            int64_t immhi = (insn >> 5) & 0x7FFFFu;
            int64_t imm = (immhi << 2) | immlo;
            if (imm & (1LL << 20)) imm |= ~((1LL << 21) - 1);
            uintptr_t abs = spc + (uintptr_t)imm;
            int64_t new_imm = (int64_t)abs - (int64_t)dpc;
            if (new_imm < -(1LL << 20) || new_imm >= (1LL << 20)) {
                NSLog(@"[Aurora] relocate: ADR overflow imm=%lld", new_imm);
                return 0;
            }
            uint32_t nlo = (uint32_t)(new_imm & 0x3u);
            uint32_t nhi = (uint32_t)((new_imm >> 2) & 0x7FFFFu);
            insn = 0x10000000u | (nlo << 29) | (nhi << 5) | rd;
        }
        // LDR (literal) Xt, #imm19  (64-bit and 32-bit variants, opc=01/00, V=0)
        else if ((insn & 0xBF000000u) == 0x18000000u) {
            uint32_t rt = insn & 0x1Fu;
            int64_t imm19 = (insn >> 5) & 0x7FFFFu;
            if (imm19 & (1LL << 18)) imm19 |= ~((1LL << 19) - 1);
            uintptr_t abs = spc + (uintptr_t)(imm19 << 2);
            int64_t new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
            if (new_imm < -(1LL << 18) || new_imm >= (1LL << 18)) {
                NSLog(@"[Aurora] relocate: LDR-lit overflow imm=%lld", new_imm);
                return 0;
            }
            insn = (insn & 0xFF00001Fu) | ((uint32_t)(new_imm & 0x7FFFFu) << 5) | rt;
        }
        // B / BL imm26
        else if ((insn & 0x7C000000u) == 0x14000000u) {
            uint32_t op = insn & 0xFC000000u; // 0x14 B, 0x94 BL
            int64_t imm26 = insn & 0x03FFFFFFu;
            if (imm26 & (1LL << 25)) imm26 |= ~((1LL << 26) - 1);
            uintptr_t abs = spc + (uintptr_t)(imm26 << 2);
            int64_t new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
            if (new_imm < -(1LL << 25) || new_imm >= (1LL << 25)) {
                NSLog(@"[Aurora] relocate: B/BL overflow");
                return 0;
            }
            insn = op | (uint32_t)(new_imm & 0x03FFFFFFu);
        }
        // B.cond  (0x54000000, mask 0xFF000010)
        else if ((insn & 0xFF000010u) == 0x54000000u) {
            uint32_t cond = insn & 0xFu;
            int64_t imm19 = (insn >> 5) & 0x7FFFFu;
            if (imm19 & (1LL << 18)) imm19 |= ~((1LL << 19) - 1);
            uintptr_t abs = spc + (uintptr_t)(imm19 << 2);
            int64_t new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
            if (new_imm < -(1LL << 18) || new_imm >= (1LL << 18)) {
                NSLog(@"[Aurora] relocate: B.cond overflow");
                return 0;
            }
            insn = 0x54000000u | (uint32_t)(new_imm & 0x7FFFFu) << 5 | cond;
        }
        // CBZ / CBNZ  (0x34000000 / 0x35000000, mask 0x7E000000)
        else if ((insn & 0x7E000000u) == 0x34000000u) {
            uint32_t op = insn & 0x01000000u;
            uint32_t rt = insn & 0x1Fu;
            int64_t imm19 = (insn >> 5) & 0x7FFFFu;
            if (imm19 & (1LL << 18)) imm19 |= ~((1LL << 19) - 1);
            uintptr_t abs = spc + (uintptr_t)(imm19 << 2);
            int64_t new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
            if (new_imm < -(1LL << 18) || new_imm >= (1LL << 18)) {
                NSLog(@"[Aurora] relocate: CBZ/CBNZ overflow");
                return 0;
            }
            insn = 0x34000000u | op | (uint32_t)(new_imm & 0x7FFFFu) << 5 | rt;
        }
        // TBZ / TBNZ  (0x36000000 / 0x37000000, mask 0x7E000000)
        else if ((insn & 0x7E000000u) == 0x36000000u) {
            uint32_t op = insn & 0x01000000u;
            uint32_t rt = insn & 0x1Fu;
            uint32_t b40 = (insn >> 19) & 0x1Fu;
            uint32_t b5  = (insn >> 31) & 0x1u;
            int64_t imm14 = (insn >> 5) & 0x3FFFu;
            if (imm14 & (1LL << 13)) imm14 |= ~((1LL << 14) - 1);
            uintptr_t abs = spc + (uintptr_t)(imm14 << 2);
            int64_t new_imm = ((int64_t)abs - (int64_t)dpc) >> 2;
            if (new_imm < -(1LL << 13) || new_imm >= (1LL << 13)) {
                NSLog(@"[Aurora] relocate: TBZ/TBNZ overflow");
                return 0;
            }
            insn = (b5 << 31) | 0x36000000u | op | (b40 << 19) |
                   (uint32_t)(new_imm & 0x3FFFu) << 5 | rt;
        }
        // else: non-pc-relative insn, copy verbatim
        dst[i] = insn;
    }
    return n * 4;
}

// --- exec-page patcher ------------------------------------------------------
//
// mprotect RW -> memcpy -> mprotect RX -> sys_icache_invalidate.
// never leaves the page RWX, never executes from it while still writable.
static bool patch_exec(uintptr_t addr, const void *bytes, size_t len) {
    uintptr_t ps  = page_size();
    uintptr_t lo  = page_base(addr);
    uintptr_t hi  = page_base(addr + len - 1) + ps;
    size_t   span = hi - lo;

    kern_return_t kr = mprotect((void *)lo, span, PROT_READ | PROT_WRITE);
    if (kr != 0) {
        NSLog(@"[Aurora] patch_exec: mprotect RW failed base=%p span=%zu errno=%d",
              (void *)lo, span, errno);
        return false;
    }

    memcpy((void *)addr, bytes, len);

    kr = mprotect((void *)lo, span, PROT_READ | PROT_EXEC);
    if (kr != 0) {
        // catastrophic: page is still RW. do NOT keep going.
        NSLog(@"[Aurora] patch_exec: mprotect RX failed base=%p span=%zu errno=%d",
              (void *)lo, span, errno);
        return false;
    }

    sys_icache_invalidate((void *)addr, len);
    return true;
}

// --- trampoline allocator ---------------------------------------------------
//
// tries to land a RW page within ±64MB of `near_pc` so a B back from the
// trampoline to the target lands in range. falls back to anywhere if needed.
static void *alloc_trampoline_page(uintptr_t near_pc) {
    uintptr_t ps = page_size();
    // try a fan of hints within ±64MB
    for (size_t i = 1; i <= 32; ++i) {
        int64_t off = ((i & 1) ? 1 : -1) * (int64_t)(i / 2 + 1) * (int64_t)ps * 64;
        void *hint = (void *)(near_pc + off);
        void *p = mmap(hint, ps, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANON | MAP_FIXED, -1, 0);
        if (p != MAP_FAILED && p != nullptr) return p;
        if (p == MAP_FAILED && errno != EEXIST) break;
    }
    void *p = mmap(nullptr, ps, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANON, -1, 0);
    return (p == MAP_FAILED) ? nullptr : p;
}

} // namespace

namespace managers {

hook_mgr_type hook_mgr;

void hook_mgr_type::start() {
    NSLog(@"[Aurora] hook_mgr::start");
}

void hook_mgr_type::hook(uintptr_t absolute_address, void *replacement, void **backup) {
    if (backup) *backup = nullptr;
    if (absolute_address == 0 || replacement == nullptr) {
        NSLog(@"[Aurora] hook_mgr: refusing null input addr=%p repl=%p",
              (void *)absolute_address, replacement);
        return;
    }

    uintptr_t target = absolute_address;
    uintptr_t fake    = (uintptr_t)replacement;

    // ---- 0. decide patch shape --------------------------------------------
    uint32_t near_b = encode_b(target, fake);
    bool use_far = (near_b == 0);
    size_t patch_len = use_far ? sizeof(far_branch) : sizeof(uint32_t);
    size_t insn_count = patch_len / 4;

    // ---- 1. allocate trampoline page (RW) --------------------------------
    void *tramp = alloc_trampoline_page(target);
    if (tramp == nullptr) {
        NSLog(@"[Aurora] hook_mgr: trampoline mmap failed target=%p errno=%d",
              (void *)target, errno);
        return;
    }

    // ---- 2. build trampoline body: relocated original + branch back -------
    uint8_t tramp_buf[64] = {0};
    size_t  tramp_body = 0;

    size_t written = relocate_arm64((uint32_t *)tramp_buf,
                                    (const uint32_t *)target,
                                    insn_count,
                                    target,
                                    (uintptr_t)tramp);
    if (written != patch_len) {
        NSLog(@"[Aurora] hook_mgr: relocate failed target=%p", (void *)target);
        munmap(tramp, page_size());
        return;
    }
    tramp_body = patch_len;

    // branch back to target + patch_len
    uintptr_t back_from = (uintptr_t)tramp + tramp_body;
    uintptr_t back_to   = target + patch_len;
    uint32_t back_b = encode_b(back_from, back_to);
    if (back_b != 0) {
        memcpy(tramp_buf + tramp_body, &back_b, sizeof(back_b));
        tramp_body += sizeof(back_b);
    } else {
        // out of B range from trampoline -> far branch
        far_branch fb;
        fb.ldr_x16_lit = 0x58000050u;
        fb.br_x16      = 0xD61F0200u;
        fb.target_addr = back_to;
        memcpy(tramp_buf + tramp_body, &fb, sizeof(fb));
        tramp_body += sizeof(fb);
    }

    // ---- 3. publish trampoline: copy bytes, flip RW->RX, icache invalidate
    memcpy(tramp, tramp_buf, tramp_body);
    kern_return_t kr = mprotect(tramp, page_size(), PROT_READ | PROT_EXEC);
    if (kr != 0) {
        NSLog(@"[Aurora] hook_mgr: trampoline mprotect RX failed errno=%d", errno);
        munmap(tramp, page_size());
        return;
    }
    sys_icache_invalidate(tramp, tramp_body);

    // ---- 4. patch target: mprotect RW -> memcpy -> mprotect RX -> icache --
    if (use_far) {
        far_branch fb;
        fb.ldr_x16_lit = 0x58000050u;
        fb.br_x16      = 0xD61F0200u;
        fb.target_addr = fake;
        if (!patch_exec(target, &fb, sizeof(fb))) {
            munmap(tramp, page_size());
            return;
        }
    } else {
        if (!patch_exec(target, &near_b, sizeof(near_b))) {
            munmap(tramp, page_size());
            return;
        }
    }

    if (backup) *backup = tramp;
    NSLog(@"[Aurora] hook_mgr: hook ok target=%p repl=%p tramp=%p mode=%s insns=%zu",
          (void *)target, replacement, tramp, use_far ? "far" : "near", insn_count);
}

} // namespace managers
