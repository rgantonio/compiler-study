# Part 0: Setup

This part gets the tools in place. You build one container image with the
RISC-V compiler and the simulators, look at each step from C file to
executable, and set up the Makefile and test runner that the later parts use.

The whole part takes about 10 hours of your own work, plus build time for
the toolchain. The plan is in [docs/syllabus.md](../docs/syllabus.md).

## Sections

| Exercise | Topic | Expected time | Sheet | Status |
|---|---|---|---|---|
| [e1](e1_dockerfile/README.md) | Write the Dockerfile: toolchain, QEMU, Spike, pk. Publish the image. | About a day, plus 1 to 3 hours of unattended build | Ready | In progress: the image builds and is checked locally. Publishing and `docs/setup.md` are open. |
| e2 | Run preprocess, compile, assemble and link one step at a time. | To be set | Not written | Not started |
| e3 | Repo Makefile with an `XLEN` switch and a test runner. | To be set | Not written | Not started |

Status is one of: Not started, In progress, Done.

## Milestone

| Milestone | Task | Sheet | Status |
|---|---|---|---|
| M0 | `make test` passes for both word sizes on a fresh clone. Optional: draw the toolchain pipeline. | Not written | Not started |

M0 should pass before part 1 starts.

## Where things go in this part

| Path | Who writes it | What |
|---|---|---|
| `util/container/Dockerfile` | Learner | The image recipe from e1. It is also the one place where versions, flags and tool paths are set. |
| `README.md` (top level) | Claude, on request | Quick guide to the image |
| `docs/setup.md` | Learner | How to pull the published image, and notes per machine |
| `p0_setup/eX_*/README.md` | Claude | Exercise sheets |
| `p0_setup/eX_*/examples/` | Claude | Worked examples |
| `p0_setup/eX_*/src/`, `test/` | Learner | Solutions and tests |
