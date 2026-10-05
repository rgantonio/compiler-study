# Syllabus

A self-study course on compilers for RISC-V, for someone who knows digital
hardware and C but has never studied compilers.

## How the course works

- The course is split into parts, sections, exercises and milestones. There
  are no fixed dates. Each exercise states its expected time.
- Each exercise is one sheet: short theory, worked examples, then tasks the
  learner solves by hand, with tests. Questions on a sheet carry a folded
  answer, so a finished sheet can be read again as a tutorial.
- Each section ends with a milestone, which is a slightly larger task. It
  must pass before the next section starts.
- A task may ask for a drawing, such as a stack frame or a memory map. Drawing
  tasks are optional.
- RV32IM is the main target. Each sheet ends with a short RV64 comparison.
- Claude gives hints first and the full answer when asked. Set-up and tool
  questions are answered directly. A grading record is kept only on request.

## Tools

All tools are open source and live in one container image, built from
`util/container/Dockerfile` and published as
`ghcr.io/rgantonio/compiler-study`. The quick guide is in the top-level
`README.md`.

| Tool | Used for |
|---|---|
| RISC-V GNU toolchain (multilib) | Compiler, assembler, linker, GDB |
| QEMU | Main simulator |
| Spike and pk | Second simulator |
| Compiler Explorer | Quick looks at compiler output |

## Part 0: Setup (about 10 hours, plus build time)

| Exercise | Topic |
|---|---|
| e1 | Write the Dockerfile: toolchain, QEMU, Spike, pk. Publish the image. |
| e2 | Run preprocess, compile, assemble and link one step at a time. |
| e3 | Repo Makefile with an `XLEN` switch and a test runner. |
| **M0** | `make test` passes for both word sizes on a fresh clone. Optional: draw the toolchain pipeline. |

## Part 1: C to assembly (about 14 hours)

Main reading: Borin, "An Introduction to Assembly Programming with RISC-V",
and the RISC-V calling convention document.

### 1.1 Reading assembly (5 hours)

| Exercise | Topic |
|---|---|
| e1 | Annotate `-O0` output of small C functions. |
| e2 | Hand-write leaf functions. |
| e3 | Loops and memory access. |
| e4 | Pseudo-instructions and how constants and addresses are built. |
| **M1** | Reconstruct C from assembly. |

### 1.2 Calls and the stack (5 hours)

| Exercise | Topic |
|---|---|
| e5 | Caller-saved and callee-saved registers. |
| e6 | Stack frames. |
| e7 | Recursion and tail calls. |
| e8 | Argument passing: many arguments, structs, 64-bit values. |
| **M2** | `apply(a, n, f)` in assembly. Draw the stack at its deepest point. |

### 1.3 The optimizer (4 hours)

| Exercise | Topic |
|---|---|
| e9 | Catalogue the differences between `-O0` and `-O2`. |
| e10 | Predict the optimized output, then verify. |
| e11 | `switch` statements and jump tables. |
| e12 | Undefined behaviour and `volatile`. |
| **M3** | Hand-written dot product compared with `-O2`. |

## Part 2: Bare-metal C (about 15 hours)

Main reading: the GNU ld manual (linker scripts) and the RISC-V privileged
specification (machine mode).

### 2.1 Linking (5 hours)

| Exercise | Topic |
|---|---|
| e1 | Symbols, sections and relocations. |
| e2 | Which section does each declaration land in. |
| e3 | First linker script; an assembly-only program on QEMU. |
| e4 | Startup code: stack pointer, global pointer, clearing `.bss`. |
| **M4** | GDB trace from reset to `main`. Draw the memory map. |

### 2.2 Hardware access (5 hours)

| Exercise | Topic |
|---|---|
| e5 | UART `putchar` driver. |
| e6 | Print functions without the C library. |
| e7 | Separate ROM and RAM regions; copying `.data` at startup. |
| e8 | newlib stubs so `printf` and `malloc` work. |
| **M5** | Account for every section in the map file. |

### 2.3 Traps and Spike (5 hours)

| Exercise | Topic |
|---|---|
| e9 | Trap handler and decoding `mcause`. |
| e10 | Timer interrupt. |
| e11 | Port the platform code to Spike. |
| e12 | A small kernel on both simulators, both word sizes, `-O0` and `-O2`. |
| **M6** | Results write-up and oral exam on parts 1 and 2. |

## Later parts (outline only)

These get a detailed plan when part 2 is done.

| Part | Topic | Main source |
|---|---|---|
| 3 | Compiler internals: IR, control-flow graphs, dataflow analysis, basic optimizations | Selected lessons from Cornell CS 6120 |
| 4 | LLVM: reading LLVM IR, then writing one small pass | LLVM documentation |
| 5 | MLIR: xDSL in Python first, then the C++ side. CIRCT as an optional extra. | xDSL docs, Jeremy Kun's "MLIR for Beginners", the Toy tutorial |
