# compiler-study

A self-study course on compilers for RISC-V. It starts at C and RISC-V
assembly, goes through bare-metal programming and compiler internals, and
ends at LLVM and MLIR.

This is a learning repo. The exercise sheets are written with Claude acting
as examiner, and all solution code is written by hand by the learner.

## Course path

| Part | Topic | Status |
|---|---|---|
| 0 | Setup: toolchain container, build steps, repo Makefile | Not started |
| 1 | C to RISC-V assembly | Not started |
| 2 | Bare-metal C with the GNU toolchain | Not started |
| 3 | Compiler internals: IR, control-flow graphs, dataflow | Planned |
| 4 | LLVM: reading IR and writing a pass | Planned |
| 5 | MLIR: xDSL first, then the C++ side | Planned |

The full plan is in [docs/syllabus.md](docs/syllabus.md).

## How it works

- Each exercise is one folder with a sheet (`README.md`), worked examples,
  the learner's code and the learner's tests.
- Each section ends with a milestone that must pass before the next section.
- RV32IM is the main target. Each sheet ends with a short RV64 comparison.
- All tools are open source and run from one container image.

The rules Claude follows as examiner are in [CLAUDE.md](CLAUDE.md).

## Getting started

The tool setup is the first exercise of part 0. It will be described in
`docs/setup.md` once that exercise is done.

## License

Apache-2.0. See [LICENSE](LICENSE).
