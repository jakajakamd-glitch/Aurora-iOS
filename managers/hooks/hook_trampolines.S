.section __TEXT,__text,regular,pure_instructions

.extern _aurora_job_start_return
.extern _aurora_start_script_return
.extern _aurora_game_loaded_return

.globl _aurora_job_start_trampoline
.p2align 2
_aurora_job_start_trampoline:
    stp x20, x19, [sp, #-0x20]!
    stp x29, x30, [sp, #0x10]
    add x29, sp, #0x10
    mov x19, x0
    adrp x16, _aurora_job_start_return@page
    ldr x16, [x16, _aurora_job_start_return@pageoff]
    br x16

.globl _aurora_start_script_trampoline
.p2align 2
_aurora_start_script_trampoline:
    stp x28, x27, [sp, #-0x60]!
    stp x26, x25, [sp, #0x10]
    stp x24, x23, [sp, #0x20]
    stp x22, x21, [sp, #0x30]
    adrp x16, _aurora_start_script_return@page
    ldr x16, [x16, _aurora_start_script_return@pageoff]
    br x16

.globl _aurora_game_loaded_trampoline
.p2align 2
_aurora_game_loaded_trampoline:
    sub sp, sp, #0x50
    stp x22, x21, [sp, #0x20]
    stp x20, x19, [sp, #0x30]
    stp x29, x30, [sp, #0x40]
    adrp x16, _aurora_game_loaded_return@page
    ldr x16, [x16, _aurora_game_loaded_return@pageoff]
    br x16

.section __DATA,__data
.p2align 3
.globl _aurora_job_start_return
_aurora_job_start_return:
    .quad 0
.globl _aurora_start_script_return
_aurora_start_script_return:
    .quad 0
.globl _aurora_game_loaded_return
_aurora_game_loaded_return:
    .quad 0
