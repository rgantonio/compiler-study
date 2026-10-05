# compiler-study

A self-study course on compilers for RISC-V. It starts at C and RISC-V
assembly, goes through bare-metal programming and compiler internals, and
ends at LLVM and MLIR.

This is a learning repo. The exercise sheets are written with Claude, which
explains, gives hints and reviews. The learner works through the tasks, and
finished sheets keep their answers folded so they can be read again as
tutorials.

## Course path

| Part | Topic | Status |
|---|---|---|
| 0 | Setup: toolchain container, build steps, repo Makefile | In progress |
| 1 | C to RISC-V assembly | Not started |
| 2 | Bare-metal C with the GNU toolchain | Not started |
| 3 | Compiler internals: IR, control-flow graphs, dataflow | Planned |
| 4 | LLVM: reading IR and writing a pass | Planned |
| 5 | MLIR: xDSL first, then the C++ side | Planned |

The full plan is in [docs/syllabus.md](docs/syllabus.md).

## How it works

- Each exercise is one folder with a sheet (`README.md`), worked examples,
  code and tests.
- Each section ends with a milestone that should pass before the next section.
- RV32IM is the main target. Each sheet ends with a short RV64 comparison.
- All tools are open source and run from one container image.

The rules Claude follows are in [CLAUDE.md](CLAUDE.md).

## Quick guide to the toolchain image

Everything runs inside one container image. Its recipe is
[util/container/Dockerfile](util/container/Dockerfile), and how it was
written is the subject of
[p0/e1](p0_setup/e1_dockerfile/README.md). All commands below are run from
the top folder of the repo.

### What is in the image

| Tool | Where | Pinned to |
|---|---|---|
| RISC-V GNU toolchain: GCC, binutils, newlib, GDB, with multilib | `/tools/riscv` | Release `2026.08.27` of `riscv-gnu-toolchain` |
| Spike | `/tools/spike` | Commit `609dbe0` of `riscv-isa-sim` |
| pk, for RV32 and RV64 | `/tools/pk` | Commit `9c61d29` of `riscv-pk` |
| QEMU, user mode and system mode | From apt | The version in Ubuntu 24.04 (8.2) |

The versions are set at the top of the Dockerfile and nowhere else.

### Build the image

The image is not published yet. Until it is, build it locally, one stage at
a time:

```
docker build --target spike     -t compiler-study:spike     -f util/container/Dockerfile util/container
docker build --target toolchain -t compiler-study:toolchain -f util/container/Dockerfile util/container
docker build --target final     -t compiler-study:dev       -f util/container/Dockerfile util/container
```

| Stage | Time | Notes |
|---|---|---|
| `spike` | Minutes | |
| `toolchain` | 1 to 3 hours | Needs about 20 GB of free disk while it builds |
| `final` | Minutes | Also builds the `pk` stage, and ends with a smoke test |

The default is 4 parallel jobs, which suits a machine with 8 GB of memory.
On a larger machine add `--build-arg JOBS=<n>`, with about 2 GB of memory
per job. Choose the value once: changing it makes the build steps run again.

For the long build, keep a log by adding `--progress=plain` and
`2>&1 | tee build.log`.

### Use the image

A shell in the container, with the repo mounted at `/work`:

```
docker run --rm -it -v "$PWD":/work compiler-study:dev
```

Add `--user "$(id -u):$(id -g)"` after `--rm` if files created in the repo
should belong to you and not to root.

Inside the container, compile and run a program for both word sizes:

```
cd p0_setup/e1_dockerfile/src

${CROSS_COMPILE}gcc $RV32_FLAGS -o /tmp/hello32 hello.c
qemu-riscv32 /tmp/hello32
spike --isa=$SPIKE32_ISA $PK32 /tmp/hello32

${CROSS_COMPILE}gcc $RV64_FLAGS -o /tmp/hello64 hello.c
qemu-riscv64 /tmp/hello64
spike --isa=$SPIKE64_ISA $PK64 /tmp/hello64
```

### Variables set in the image

These are set with `ENV` in the Dockerfile. Scripts and Makefiles in the repo
read them and do not define their own copies.

| Variable | Value | Meaning |
|---|---|---|
| `PATH` | starts with `/tools/riscv/bin:/tools/spike/bin` | The cross tools and Spike can be called by name |
| `CROSS_COMPILE` | `riscv64-unknown-elf-` | Name prefix of the cross tools: `${CROSS_COMPILE}gcc`, `${CROSS_COMPILE}objdump`, ... |
| `RV32_FLAGS` | `-march=rv32im -mabi=ilp32` | Compiler flags of the main target |
| `RV32_MULTILIB` | `rv32im/ilp32` | The library set those flags select |
| `SPIKE32_ISA` | `rv32imac` | `--isa` value for Spike with the 32-bit pk |
| `PK32` | `/tools/pk/riscv32-unknown-elf/bin/pk` | The 32-bit pk, given to Spike as a file |
| `RV64_FLAGS` | `-march=rv64imac -mabi=lp64` | Compiler flags of the 64-bit comparison |
| `RV64_MULTILIB` | `rv64imac/lp64` | The library set those flags select |
| `SPIKE64_ISA` | `rv64gc` | `--isa` value for Spike with the 64-bit pk |
| `PK64` | `/tools/pk/riscv64-unknown-elf/bin/pk` | The 64-bit pk |
| `RISCV_GNU_TOOLCHAIN_TAG`, `SPIKE_COMMIT`, `PK_COMMIT` | See the table above | What the image was built from |

`env | sort` inside the container shows them all.

### Check the image

```
docker run --rm -v "$PWD":/work compiler-study:dev bash p0_setup/e1_dockerfile/test/check_docker.sh
```

The script prints one line per test case and ends with the number of failed
checks. The test plan it follows is in section 8 of the
[p0/e1 sheet](p0_setup/e1_dockerfile/README.md).

### Still to come

Publishing the image as `ghcr.io/rgantonio/compiler-study:v1`, and
`docs/setup.md` with the pull commands and the notes per machine.

## License

Apache-2.0. See [LICENSE](LICENSE).
