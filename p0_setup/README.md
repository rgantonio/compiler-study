# Part 0: Setup

This part gets the tools in place. You build one container image with the
RISC-V compiler and the simulators, look at each step from C file to
executable, and set up the Makefile and test runner that the later parts use.

The whole part takes about 4 hours of your own work, plus build time for the
toolchain. The plan is in [docs/syllabus.md](../docs/syllabus.md).

## Sections

| Exercise | Topic | Expected time | Sheet | Status |
|---|---|---|---|---|
| [e1](e1_dockerfile/README.md) | Write the Dockerfile: toolchain, QEMU, Spike, pk. Publish the image. | 90 min, plus 1 to 3 hours of unattended build | Ready | Not started |
| e2 | Run preprocess, compile, assemble and link one step at a time. | To be set | Not written | Not started |
| e3 | Repo Makefile with an `XLEN` switch and a test runner. | To be set | Not written | Not started |

Status is one of: Not started, In progress, Handed in, Pass, Redo.

## Milestone

| Milestone | Task | Sheet | Status |
|---|---|---|---|
| M0 | `make test` passes for both word sizes on a fresh clone. Draw the toolchain pipeline. | Not written | Not started |

M0 must pass before part 1 starts.

## Where things go in this part

| Path | Who writes it | What |
|---|---|---|
| `util/container/Dockerfile` | Learner | The image recipe from e1 |
| `docs/setup.md` | Learner | How to get and use the image, written in e1 |
| `p0_setup/eX_*/README.md` | Claude | Exercise sheets |
| `p0_setup/eX_*/examples/` | Claude | Worked examples |
| `p0_setup/eX_*/src/`, `test/`, `drawings/` | Learner | Solutions, tests, sketches |
