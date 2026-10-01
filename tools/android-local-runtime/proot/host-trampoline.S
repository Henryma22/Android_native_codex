/*
 * A tiny static ARM64 first-exec trampoline for PRoot on Android.
 *
 * Android's /system/bin/sh is a dynamically linked Bionic executable. Using
 * it as PRoot's initial tracee would require exposing its linker and library
 * tree before PRoot has translated the guest command. This binary has no
 * interpreter or library dependency: it forwards argv[1..] to execve(2), so
 * PRoot can translate the guest command in the normal traced syscall path.
 */

.text
.p2align 2
.global _start
.type _start, %function

_start:
    /* Linux AArch64 process entry: sp points at argc, then argv. */
    ldr     x3, [sp]
    add     x3, x3, #2
    lsl     x3, x3, #3
    add     x2, sp, x3              /* envp = sp + (argc + 2) * 8 */
    add     x1, sp, #16             /* argv + 1; argv[1] is the guest path */
    ldr     x0, [x1]

    mov     x8, #221                /* __NR_execve on AArch64 */
    svc     #0

    /* Do not write diagnostics. The caller receives a fixed failure code. */
    mov     x0, #127
    mov     x8, #93                 /* __NR_exit on AArch64 */
    svc     #0
    b       .

.size _start, . - _start
