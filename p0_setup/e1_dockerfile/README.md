# p0/e1: Write the Dockerfile

## 1. Header

| | |
|---|---|
| Part | 0, Setup |
| Section | e1 (first exercise of the part) |
| Expected time | About a day the first time: three to four hours of your own work, split over several sittings, plus one to three hours of build time that you do not need to watch. |
| Prerequisites | A working Linux shell (WSL2 on the laptop). A GitHub account. No RISC-V or Docker knowledge is assumed. |
| You write | `util/container/Dockerfile`, `src/` and `test/` in this folder, and `docs/setup.md` |
| Result in this repo | [`util/container/Dockerfile`](../../util/container/Dockerfile), [`test/check_docker.sh`](test/check_docker.sh), and the quick guide in the top-level [`README.md`](../../README.md) |

The build of the compiler is slow. Plan the work so that the long build runs
while you do something else, for example overnight or during a meeting.

This sheet keeps the section numbers of the course format. Section 7
(drawing task) and section 13 (grading record) are not used here.

## 2. What you are learning

After this exercise you can:

- say what each tool in the image is for, and which machine it runs on;
- explain what a cross-compiler is, and why one compiler binary can serve
  both RV32 and RV64 once it has multilib;
- write a multi-stage Dockerfile that builds tools from source and keeps the
  final image free of build leftovers;
- find out which packages a tool needs to build and which it needs to run;
- publish an image to a registry and pull it on a second machine;
- prove with a script that the image does what the course needs.

## 3. Theory

Read sections 3.1 to 3.5 before the questions in section 5. Sections 3.6 to
3.10 are for the Dockerfile work, and you can read them when you get there.

### 3.1 The tools in the image

| Tool | What it is | What you use it for in this course |
|---|---|---|
| GCC | The C compiler. Turns C into RISC-V assembly, and drives the other steps. | Every exercise. |
| Binutils | The assembler, the linker, and tools that inspect object files. | Parts 1 and 2: reading compiler output, linker scripts. |
| newlib | A small C library for systems without an operating system. Gives you `printf`, `malloc`, `memcpy`. | Linked into your programs. Part 2 looks inside it. |
| GDB | The debugger. | Part 2: stepping from reset to `main`. |
| QEMU | A fast emulator. Runs RISC-V programs on your x86 machine. | The main simulator. |
| Spike | The reference simulator for the RISC-V instruction set. Slower than QEMU, but follows the specification closely and prints instruction traces. | The second simulator, to cross-check QEMU. |
| pk (proxy kernel) | A very small kernel that runs inside Spike. It loads your program and passes its system calls to the host. | Running a normal C program on Spike. |

The first four come from one repository, `riscv-gnu-toolchain`, which fetches
and builds GCC, Binutils, newlib and GDB together.

**What a toolchain is.** A toolchain is the set of programs that together
turn source code into something that runs. They are used one after another,
each taking the output of the one before, which is where "chain" comes from.

| Step | Program | Input | Output |
|---|---|---|---|
| Compile | The compiler proper (`cc1`, started by `gcc`) | C source | Assembly text (`.s`) |
| Assemble | The assembler (`as`) | Assembly text | Object file (`.o`): machine code with gaps for addresses not known yet |
| Link | The linker (`ld`) | Your object files plus libraries | One executable (an ELF file) |

The `gcc` command is a driver: it calls the three steps in order, so it looks
like one program. Around the three steps sit the libraries that get linked in
(newlib, `libgcc`, the startup file) and the inspection tools. This
three-step model is the usual one for languages that are compiled ahead of
time to machine code. C adds a preprocess step in front. Exercise e2 takes
the steps apart.

**The names of the tools.** Every tool has the same name pattern: the prefix
`riscv64-unknown-elf-` followed by the usual tool name. All of them accept
`--version`. They are installed in the `bin` folder under the install prefix,
and `ls <prefix>/bin` lists them all.

| Tool | Program name | What it does |
|---|---|---|
| Compiler | `riscv64-unknown-elf-gcc` | C to assembly, and drives the other steps |
| Assembler | `riscv64-unknown-elf-as` | Assembly text to object file |
| Linker | `riscv64-unknown-elf-ld` | Object files and libraries to one executable |
| Disassembler | `riscv64-unknown-elf-objdump` | Shows the instructions inside an object file or executable |
| ELF reader | `riscv64-unknown-elf-readelf` | Shows the headers and sections of an ELF file |
| Size | `riscv64-unknown-elf-size` | Shows the sizes of `text`, `data` and `bss` |
| Debugger | `riscv64-unknown-elf-gdb` | Steps through a program |

The prefix keeps these apart from the normal x86 tools. Plain `objdump` in
WSL is the x86 one.

### 3.2 What a cross-compiler is

A normal (native) compiler makes programs for the machine it runs on. A
cross-compiler runs on one kind of machine and makes programs for another.
Yours runs on x86-64 and makes programs for RISC-V. Its output is a linked
ELF file with RISC-V machine code in it. You cannot run that file directly
on your laptop: the kernel reads the ELF header, sees a machine type it
cannot run, and the shell reports `Exec format error`. This is why the image
also holds simulators.

Build systems use three words for the machines involved:

| Word | Meaning | For your compiler | For pk |
|---|---|---|---|
| build | The machine where the tool is compiled | x86-64 Linux (inside the container) | x86-64 Linux |
| host | The machine where the tool will run | x86-64 Linux | RISC-V |
| target | The machine the tool produces code for | RISC-V | Nothing. pk is not a compiler. |

You meet `--host` when you build pk. In a `configure` command it means "the
machine the program I am building will run on". pk runs on RISC-V, inside
Spike, so it must be compiled with your cross-compiler. The value you give,
`riscv64-unknown-elf`, is also the name prefix of that compiler, which is how
`configure` finds it.

The name of the compiler tells you its target. `riscv64-unknown-elf` reads as
architecture, vendor, system. `elf` means there is no operating system: the
program is a plain ELF file and the C library is newlib. The other common
target, `riscv64-unknown-linux-gnu`, makes programs for RISC-V Linux with
glibc. This course uses the `elf` one, because part 2 is bare-metal.

### 3.3 `-march` and `-mabi`

Two flags tell GCC what kind of RISC-V code to make. The `-m` at the front
means "machine option": a flag that only exists for one processor family. So
the names split as `-m` + `arch` and `-m` + `abi`.

`-march` is the architecture: the set of instructions the processor has, and
so the ones the compiler may use. `rv32im` means the 32-bit base
instructions (`rv32i`) plus multiply and divide (`m`). The other letters you
will see:

| Letter | Extension |
|---|---|
| `m` | Multiply and divide |
| `a` | Atomic instructions, for locks and multi-core code |
| `f` | Single-precision floating point |
| `d` | Double-precision floating point |
| `c` | Compressed instructions: 16-bit short forms of common instructions |
| `g` | Short for `imafd` |

`-mabi` is the application binary interface: the agreement that separately
compiled pieces of code follow so that they can call each other. It fixes
the sizes of the C types, which registers carry arguments and return values,
which registers a function must restore before it returns, and how the stack
is aligned.

| ABI | `int`, `long`, pointer | Floating-point arguments travel in | Needs |
|---|---|---|---|
| `ilp32` | 32, 32, 32 bits | Integer registers | Any RV32 |
| `ilp32f`, `ilp32d` | 32, 32, 32 bits | Floating-point registers | The F or D extension |
| `lp64` | 32, 64, 64 bits | Integer registers | Any RV64 |
| `lp64f`, `lp64d` | 32, 64, 64 bits | Floating-point registers | The F or D extension |

You can still use `float` and `double` with `rv32im` and `ilp32`. The
arithmetic is then done by helper routines in `libgcc` and not by
instructions. That is called soft float.

The processor does not enforce the ABI. It is a protocol on top of the
instruction set, like two hardware blocks agreeing on a handshake over the
same wires. All object files and libraries in one program must use the same
ABI. Part 1.2 of the course works through it in detail.

### 3.4 What multilib is

The compiler can emit instructions for any `-march` you ask for. The problem
is at link time. Compile and assemble need only your own source. The link
step is the first one that combines your code with libraries that were
compiled earlier: newlib, the startup file, and `libgcc`. Those libraries
must match your `-march` and `-mabi`. A library full of 64-bit code cannot be
linked into a 32-bit program.

Multilib means the toolchain was built with several copies of these
libraries, one per combination of `-march` and `-mabi`. Without multilib,
the toolchain has one copy, for one combination, and that is the only thing
it can link for, whatever its name says.

Multilib is not a flag you pass when you compile a program. There are two
different moments:

| When | What you choose | Effect |
|---|---|---|
| Building the toolchain (once, in the Dockerfile) | Multilib on or off, and which combinations | Which copies of newlib, `libgcc` and the startup file exist in the install folder |
| Compiling your program (every time) | `-march` and `-mabi` | What code is made from your source, and which of the existing library copies the linker is given |

So `-march` and `-mabi` do not switch multilib on. They select from what was
installed. In chip-design terms: multilib is deciding which standard-cell
libraries ship in the PDK, and the two flags pick one of them for a run.

Three commands show what a finished toolchain has:

| Command | Shows |
|---|---|
| `riscv64-unknown-elf-gcc -print-multi-lib` | Every library set that was built |
| `riscv64-unknown-elf-gcc -march=... -mabi=... -print-multi-directory` | Which set GCC picks for these flags |
| `riscv64-unknown-elf-gcc -march=... -mabi=... -print-libgcc-file-name` | The exact `libgcc.a` it would link |

The first one prints lines like these (this is the default list of the
toolchain release used in this repo):

```
.;
rv32i/ilp32;@march=rv32i@mabi=ilp32
rv32im/ilp32;@march=rv32im@mabi=ilp32
rv32iac/ilp32;@march=rv32iac@mabi=ilp32
rv32imac/ilp32;@march=rv32imac@mabi=ilp32
rv32imafc/ilp32f;@march=rv32imafc@mabi=ilp32f
rv64imac/lp64;@march=rv64imac@mabi=lp64
rv64imafdc/lp64d;@march=rv64imafdc@mabi=lp64d
```

Each line is one library set. The part before the semicolon is the folder
the libraries are in. The part after it lists the flags that select the set,
with `@` standing for `-`. The first line, `.;`, is the default set, used
when you give no flags.

This list has `rv32im`, the main target of the course, but no plain
`rv64im`. The course therefore uses `-march=rv64imac -mabi=lp64` as its
64-bit configuration. It is the closest to RV32IM: no floating-point
hardware and the same style of ABI.

### 3.5 The simulators

QEMU has two modes, and both are used in this course.

| Mode | Program name | What it simulates | Used in |
|---|---|---|---|
| User mode | `qemu-riscv32`, `qemu-riscv64` | Only the CPU. System calls from your program are handed to the Linux kernel of the host. | Part 1, and this exercise |
| System mode | `qemu-system-riscv32`, `qemu-system-riscv64` | A whole board: CPU, memory, UART, timer. | Part 2 |

Spike simulates a bare RISC-V processor and memory. There is no operating
system inside it, so a program that calls `printf` has nobody to give the
output to. pk fills that gap: Spike starts pk, and pk loads your program and
handles its system calls. pk plays the role of the kernel under your
program, so it must be built for the same word size. A 32-bit program needs
a 32-bit pk.

Spike takes the pk file as its first argument and your program as the
second. It simulates RV64 unless you tell it otherwise with `--isa`, and the
value must cover what pk and your program were compiled for.

**How `printf` reaches your terminal.** `printf` is not a system call. It is
a newlib function that runs inside your program as RISC-V code. It builds
the text and calls `write`, a small newlib routine. That routine puts the
system call number in register `a7` and the arguments in `a0` to `a2`, and
executes one instruction: `ecall`. The `ecall` is the system call. Up to
this point both simulators run the same code. They differ in what happens at
the `ecall`:

| | What handles the `ecall` | Path to the terminal |
|---|---|---|
| QEMU user mode | QEMU itself, which is x86 code. It reads the simulated registers and makes the matching real system call. No RISC-V code is involved. | QEMU → host kernel → terminal |
| Spike with pk | The `ecall` raises a trap, as on real hardware. The processor jumps to the address in the control register `mtvec`, which pk set at start-up. pk's trap handler is RISC-V code. | pk → `tohost` → Spike → host kernel → terminal |

pk has no terminal of its own. It writes a request into a memory location
called `tohost`. Spike watches that location, makes the real `write` call on
your machine, and puts the reply in `fromhost`. This mechanism is called
HTIF, the host-target interface.

QEMU user mode is the quick one. Spike with pk is closer to what a real
machine does. Traps are the topic of part 2.3.

Both simulators pass on the exit code of your program. A program that
returns 7 from `main` makes `qemu-riscv32` and `spike` exit with 7.

### 3.6 Images, layers and the build cache

A few words first.

- An **image** is a read-only file system plus some settings (environment
  variables, default command). It is what you build and publish.
- A **container** is a running copy of an image. It gets a thin writable
  layer on top, which is thrown away when the container is removed. Nothing
  you do in a container changes the image.
- A **Dockerfile** is the recipe for an image.
- A **layer** is the set of file changes made by one instruction. An image is
  a stack of layers.
- The **build context** is the folder you pass to `docker build`. Only files
  in it can be used by `COPY`.
- A **registry** is a server that stores images (Docker Hub, ghcr.io).

Three rules explain most of what you will see.

**Layers only add.** If one instruction creates a file and a later
instruction deletes it, the file is hidden in the final file system, but its
bytes are still stored in the earlier layer and are still downloaded by
everyone who pulls the image. Files that are created and deleted inside the
same `RUN` never reach a layer.

**The cache works per instruction, top to bottom.** Docker reuses a layer if
the instruction and its inputs did not change, and if every layer above it
was reused too. Once one instruction changes, everything below it in the
same stage runs again. An `ARG` counts as an input of every `RUN` below it,
so declare an `ARG` just before its first use.

**A `RUN` that fails saves nothing.** If a two-hour `RUN` fails after 110
minutes, it starts from zero. The steps above it stay cached.

The cache lives in Docker's storage on your machine. It is not part of the
image and is not pushed. `docker system df` shows its size. It is not
permanent: `docker builder prune` and `docker system prune` delete it, and
Docker clears old cache by itself when it grows large.

**Multi-stage builds.** A Dockerfile can have several `FROM` lines. Each one
starts a new stage with an empty history.

- `FROM image AS name` gives the stage a name. You use it in
  `COPY --from=name` and in `docker build --target name`.
- `COPY --from=name SOURCE DESTINATION` copies one folder out of another
  stage. The order is source, then destination, as with `cp`.
- A stage can also start from another stage: `FROM name AS other`. It then
  has everything that stage has.
- Only the last stage becomes the image. It is called the final stage in
  this sheet. Compilers and source trees stay behind in the earlier stages.
- Docker only builds the stages that the target needs. The order of the
  stages in the file is not the order you have to write or build them in.

A final stage normally holds four things: the install folders copied from
the builder stages, the run-time packages those tools need, tools that come
as ready-made packages anyway, and the settings (`PATH`, variables, working
folder).

**`ARG` and `ENV`.** An `ARG` exists only while the image is being built. An
`ENV` is set during the build and in every container started from the image.
An `export` inside a `RUN` lasts for that one `RUN` only.

### 3.7 Packages and shared libraries

**Finding a package.** `apt-cache search <word>` lists packages by keyword,
and `apt-cache show <package>` prints the details of one. In that output,
`Provides` lists what the package contains under other names, `Depends` is
installed with it automatically, `Recommends` is installed too unless you
pass `--no-install-recommends`, and `Installed-Size` is in kB. After
installing, `dpkg -L <package>` lists its files.

Ubuntu has no QEMU package named after RISC-V. The RISC-V emulators are
bundled with other architectures: `qemu-user` holds `qemu-riscv32` and
`qemu-riscv64`, and `qemu-system-misc` holds `qemu-system-riscv32` and
`qemu-system-riscv64`. The package `qemu-efi-riscv64` is boot firmware, not
an emulator.

**`DEBIAN_FRONTEND=noninteractive`.** Debian packages ask their set-up
questions through a system called debconf. This variable tells debconf to
show nothing and take the default answer. Without it, the `tzdata` package
asks for your time zone and the build hangs. Set it with `ARG`, so that it
does not stay in the finished image.

**Build-time and run-time packages.** Library packages come in pairs. The
`-dev` package holds the header files needed to compile against the library.
Its partner, without `-dev`, holds the shared library file that a finished
program loads when it starts. Installing `libmpc-dev` pulls in `libmpc3`
automatically, and `apt-cache depends libmpc-dev` shows the partner's name.
A builder stage needs the `-dev` packages. The final stage needs only the
partners.

**Shared libraries and `ldd`.** When a program is linked, the code of common
libraries is usually not copied into it. The linker only records "this
program needs `libfoo.so.N`", and the system loads that file each time the
program starts. If the file is missing, the program does not start at all.
`ldd <program>` prints the list:

```
libstdc++.so.6 => /lib/x86_64-linux-gnu/libstdc++.so.6 (0x...)
libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x...)
```

A line that says `not found` names a library that is missing on this
machine. System libraries live in `/usr/lib`, so a `COPY --from` of an
install folder does not bring them along. The way to find what a final stage
needs:

1. Run `ldd` on the program in the final stage.
2. For each `not found` line, find the package: `dpkg -S <file name>` in the
   builder stage, for example `dpkg -S libmpc.so.3`. Search by file name
   only. The path that `ldd` prints starts with `/lib`, which is a link to
   `/usr/lib`, and `dpkg` does not match it.
3. Install that package in the final stage and check again.

Libraries that are already in the base image need nothing. A compiler
package such as `build-essential` is for building programs, not for running
them, and does not belong in a final stage.

Two things `ldd` cannot show: a separate program that a tool starts while it
runs, and a helper program that sits behind a front end. `gcc --version`
works even when the compiler proper, `cc1`, cannot load its libraries. Only
a real run shows these, which is why the final stage ends with a smoke test
that compiles and runs something.

### 3.8 Docker commands you will use

| Command | What it does |
|---|---|
| `docker build -t NAME:TAG -f path/Dockerfile CONTEXT` | Build an image. `CONTEXT` is the folder sent to the builder. |
| `docker build --target STAGE ...` | Stop after one stage. Good for working on stages one at a time. |
| `docker build --build-arg KEY=VALUE ...` | Override an `ARG`. |
| `docker build --progress=plain ...` | Show the full output of each step, not the folded view. |
| `docker build --no-cache ...` | Ignore the cache. Rarely what you want with a two-hour step. |
| `docker pull NAME:TAG` | Download an image. Also the way to see the size of a base image such as `ubuntu:24.04`. |
| `docker images` | List local images and their sizes. |
| `docker history NAME:TAG` | List the layers of an image with the size of each. Add `--no-trunc` to see the full commands. |
| `docker run --rm -it NAME:TAG bash` | Start a container with a shell. `--rm` removes the container on exit, so nothing you did inside is kept. |
| `docker run --rm -v "$PWD":/work -w /work NAME:TAG CMD` | Run one command with the current folder mounted at `/work`. |
| `docker run --user "$(id -u):$(id -g)" ...` | Run as your own user, so files written to a mounted folder belong to you. |
| `docker ps -a` | List containers, including stopped ones. |
| `docker exec -it CONTAINER bash` | Open a second shell in a running container. |
| `docker inspect NAME:TAG` | Show settings of an image: environment, labels, digest. |
| `docker tag OLD NEW` | Give an image a second name, for example the registry name. |
| `docker login REGISTRY` | Log in before pushing. |
| `docker push NAME:TAG` | Upload an image. |
| `docker system df` | Show how much disk Docker uses. |
| `docker builder prune` | Delete the build cache. This throws away your long build. |
| `docker image rm NAME:TAG` | Delete one local image. |

In `docker history`, the `IMAGE` column shows `<missing>` for all layers but
the top one. That is normal: only the top layer has an image ID on your
machine.

The build command used in this exercise, piece by piece:

```
docker build --progress=plain --target toolchain -t compiler-study:toolchain -f util/container/Dockerfile util/container 2>&1 | tee build.log
```

| Part | What it does |
|---|---|
| `--progress=plain` | Prints the full output of every step. When `make` fails after an hour, this is where the error is. |
| `--target toolchain` | Stops after the stage with that name. |
| `-t compiler-study:toolchain` | Gives the result a name and a tag. A tagged stage can be started with `docker run`. |
| `-f util/container/Dockerfile` | The path to the Dockerfile. |
| `util/container` | The build context. This Dockerfile copies nothing from disk, so a small folder is best. |
| `2>&1` | A shell feature, not Docker. Sends the error stream to the same place as the normal output. Docker prints its build log on the error stream. |
| `\| tee build.log` | Also shell. Shows the output on the screen and writes it to `build.log`. |

A backslash continues a command on the next line only when it is the last
character on its line.

When a build step fails, build the stage up to the step before it with
`--target`, start a shell in that image, and run the failing command by
hand.

### 3.9 Registries and tags

An image name has the form `registry/owner/name:tag`. If you leave out the
registry, Docker Hub is assumed. If you leave out the tag, `latest` is
assumed. `latest` is only a name. It does not mean newest, and it moves
whenever someone pushes without a tag. A **digest** (`sha256:...`) names one
exact image and never moves.

| | Docker Hub | ghcr.io (GitHub Container Registry) |
|---|---|---|
| Account | Separate Docker account | Your GitHub account |
| Log in with | Docker password or access token | A GitHub personal access token that may write packages |
| Image name | `owner/name:tag` | `ghcr.io/owner/name:tag` |
| Link to the repo | By hand, in the description | A label on the image can link it to the GitHub repo |
| Visibility | Public by default on a free account | A new package starts private. You switch it to public in the package settings. |
| Pull limits | Anonymous pulls are rate limited | Public images pull without login |

A tag such as `main` or `latest` is a moving name: every push makes it point
at a different image. For an image that exercises depend on, push a fixed
tag that is never reused, and name that one in the docs.

| Fixed tag | Example | Good for |
|---|---|---|
| Date | `:2026.10.05` | Simple, and it matches how the toolchain itself is tagged |
| Version number | `:v1`, `:v2` | Easy to refer to in docs |
| Git commit of the Dockerfile | `:a1cd874` | Ties the image to the exact recipe |

### 3.10 Your two machines

**WSL2 on the laptop.**

- Docker runs either through Docker Desktop on Windows with WSL integration
  turned on, or as Docker Engine installed inside the WSL distribution.
- To use `docker` without `sudo`, add your user to the `docker` group
  (`sudo usermod -aG docker $USER`) and restart WSL. Anyone in that group
  can in effect become root on the machine, which is fine on your own laptop
  and is the reason shared servers often do not offer it.
- Keep the repo in the Linux file system. `pwd` should show a path under
  `/home/...`, not under `/mnt/c/...`, or file access gets slow.
- WSL2 gets only part of the laptop's memory, half of it by default.
  `free -h` and `nproc` show what it has. Compiling GCC needs about 2 GB per
  parallel job at its peak, so choose the job count for `make` from the
  memory, not from the number of cores.
- To give WSL more memory, create `C:\Users\<your-name>\.wslconfig` with a
  `[wsl2]` section and the keys `memory=`, `processors=` and `swap=`, then
  run `wsl --shutdown` in PowerShell and start WSL again.

**The shared server.** You may not have Docker there. The same published
image works with the other common tools:

| Tool | Builds from a Dockerfile | Runs your published image | Who you are inside |
|---|---|---|---|
| Docker | Yes | Yes | Root, unless the image or `--user` says otherwise |
| Podman | Yes, same file and almost the same commands | Yes | In rootless mode: root inside, mapped to your own user outside |
| Apptainer | No. It has its own recipe format. | Yes, it converts the image to a `.sif` file | Always your own user. The image is read-only and your home folder is mounted. |

This has consequences for the Dockerfile:

| A Dockerfile that... | Breaks under Apptainer because... |
|---|---|
| installs the tools under `/root` | you are not root, and a normal user cannot read `/root` |
| puts files in the image's home folder, such as `PATH` set in `~/.bashrc` | your real home folder from the server is mounted over it |
| expects root at run time, for example a start script that runs `apt-get` | you are always your own user |
| relies on `USER` to pick a specific user | Apptainer ignores `USER` |
| has a tool that writes inside the image at run time | the image is read-only |
| installs files readable by root only | your user cannot open them |

So: install under a neutral folder such as `/opt` or `/tools`, set `PATH`
and other variables with `ENV`, and do not depend on being root at run time.

**Who owns the files.** A Docker container runs as root by default. With the
repo mounted, a file created in the container belongs to root on your
laptop, and `rm` or `git clean` then fail without `sudo`. The option
`--user "$(id -u):$(id -g)"` on the `docker run` line runs the container as
your own user: `id -u` and `id -g` print your user and group numbers. `USER`
in the Dockerfile sets a default user for the image. Both are conveniences.
What matters is that the image also works when it is not run as root.

### 3.11 Pages to read

| Topic | Where | What to read |
|---|---|---|
| Docker concepts | <https://docs.docker.com/get-started/docker-overview/> | "Docker objects" |
| Dockerfile instructions | <https://docs.docker.com/reference/dockerfile/> | `FROM`, `RUN`, `ARG`, `ENV`, `COPY`, `WORKDIR`, `USER`, `LABEL` |
| Multi-stage builds | <https://docs.docker.com/build/building/multi-stage/> | Whole page |
| Build cache | <https://docs.docker.com/build/cache/> | "How the build cache works" |
| Toolchain build | <https://github.com/riscv-collab/riscv-gnu-toolchain> | README: Prerequisites, Installation (Newlib), Installation (Newlib/Linux multilib), and the notes on disk space and submodules |
| RISC-V flags | <https://gcc.gnu.org/onlinedocs/gcc/RISC-V-Options.html> | `-march`, `-mabi` |
| Spike | <https://github.com/riscv-software-src/riscv-isa-sim> | README: Build Steps, Compiling and Running a Simple C Program |
| pk | <https://github.com/riscv-software-src/riscv-pk> | README: Build Steps |
| QEMU user mode | <https://www.qemu.org/docs/master/user/main.html> | "QEMU User space emulator", first sections |
| ghcr.io | <https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry> | Authenticating, Pushing, Labelling |
| Apptainer and Docker images | <https://apptainer.org/docs/user/main/docker_and_oci.html> | First two sections |
| WSL memory | <https://learn.microsoft.com/en-us/windows/wsl/wsl-config> | `.wslconfig`, the `memory` and `processors` keys |

## 4. Worked examples

The first three examples build two small tools that have nothing to do with
RISC-V: `lz4` (a file compressor) and `htop` (a process viewer). Each builds
in a minute or two, so you can try things quickly. Build all three and
compare them before you start your own file. The fourth example is a check
script.

```
cd p0_setup/e1_dockerfile/examples
docker build -t ex1 ex1_plain
docker build -t ex2 ex2_one_layer
docker build -t ex3 ex3_multi_stage
docker images
```

The `docker history` outputs below are from one run on 2026-10-04. Your
sizes will differ a little with the version of the base image.

### Example 1: build from source, one step per line

File: [`examples/ex1_plain/Dockerfile`](examples/ex1_plain/Dockerfile)

This is the direct way: install a compiler, clone, check out a version,
`make`, `make install`. Every step is its own `RUN`, which is pleasant while
you are still finding out which commands work, because a failed step does not
redo the ones above it.

Things to notice in the file:

- `ARG LZ4_VERSION` pins the version. A build next month gives the same tool.
- `make install PREFIX=/opt/lz4` puts everything under one folder.
- `ENV PATH=...` makes the tool available in every container.
- The last `RUN rm -rf` does not shrink the image.

Run `docker history ex1`. Find the layer that holds the compiler and the
layer that holds the git clone. They are still there after the `rm`.

```
IMAGE          CREATED         CREATED BY                                      SIZE      COMMENT
2f71b6306b91   5 minutes ago   CMD ["lz4" "--version"]                         0B        buildkit.dockerfile.v0
<missing>      5 minutes ago   WORKDIR /work                                   0B        buildkit.dockerfile.v0
<missing>      5 minutes ago   ENV PATH=/opt/lz4/bin:/usr/local/sbin:/usr/l…   0B        buildkit.dockerfile.v0
<missing>      5 minutes ago   RUN |1 LZ4_VERSION=v1.10.0 /bin/sh -c rm -rf…   0B        buildkit.dockerfile.v0
<missing>      5 minutes ago   WORKDIR /                                       0B        buildkit.dockerfile.v0
<missing>      5 minutes ago   RUN |1 LZ4_VERSION=v1.10.0 /bin/sh -c make i…   1.03MB    buildkit.dockerfile.v0
<missing>      5 minutes ago   RUN |1 LZ4_VERSION=v1.10.0 /bin/sh -c make -…   1.44MB    buildkit.dockerfile.v0
<missing>      5 minutes ago   RUN |1 LZ4_VERSION=v1.10.0 /bin/sh -c git ch…   1.21MB    buildkit.dockerfile.v0
<missing>      5 minutes ago   WORKDIR /tmp/lz4                                0B        buildkit.dockerfile.v0
<missing>      5 minutes ago   RUN |1 LZ4_VERSION=v1.10.0 /bin/sh -c git cl…   9.72MB    buildkit.dockerfile.v0
<missing>      5 minutes ago   RUN |1 LZ4_VERSION=v1.10.0 /bin/sh -c apt-ge…   355MB     buildkit.dockerfile.v0
<missing>      6 minutes ago   RUN |1 LZ4_VERSION=v1.10.0 /bin/sh -c apt-ge…   54MB      buildkit.dockerfile.v0
<missing>      6 minutes ago   ARG LZ4_VERSION=v1.10.0                         0B        buildkit.dockerfile.v0
<missing>      2 weeks ago     /bin/sh -c #(nop)  CMD ["/bin/bash"]            0B
<missing>      2 weeks ago     /bin/sh -c #(nop) ADD file:6c214fc3c3c22122c…   78.2MB
<missing>      2 weeks ago     /bin/sh -c #(nop)  LABEL org.opencontainers.…   0B
<missing>      2 weeks ago     /bin/sh -c #(nop)  ARG LAUNCHPAD_BUILD_ARCH     0B
<missing>      2 weeks ago     /bin/sh -c #(nop)  ARG RELEASE                  0B
```

The image is 501 MB, which is the sum of the layers. The `rm -rf` layer is
0 B, and the clone, checkout and `make` layers above it are still counted.
The sources are only about 12 MB of the waste, though. The 355 MB of
compiler and git packages and the 54 MB of apt package lists are the rest.

### Example 2: the same build in one layer

File: [`examples/ex2_one_layer/Dockerfile`](examples/ex2_one_layer/Dockerfile)

Same tool, same result, but the install of the build tools, the build and the
cleanup are one `RUN`. Whatever is created and deleted inside one `RUN` never
becomes part of a layer.

Things to notice:

- `--no-install-recommends` stops apt from pulling in optional packages.
- `git clone --depth 1 --branch <tag>` downloads one version, not the history.
- `rm -rf /var/lib/apt/lists/*` removes the package index that
  `apt-get update` downloaded.
- `ARG DEBIAN_FRONTEND=noninteractive` keeps apt from asking questions, and
  as an `ARG` it does not stay in the final image.

Run `docker history ex2` and compare with example 1. The layers of the base
image are the same as above and are left out here.

```
IMAGE          CREATED              CREATED BY                                      SIZE      COMMENT
6b97ebb2f60d   About a minute ago   CMD ["lz4" "--version"]                         0B        buildkit.dockerfile.v0
<missing>      About a minute ago   WORKDIR /work                                   0B        buildkit.dockerfile.v0
<missing>      About a minute ago   ENV PATH=/opt/lz4/bin:/usr/local/sbin:/usr/l…   0B        buildkit.dockerfile.v0
<missing>      About a minute ago   RUN |2 LZ4_VERSION=v1.10.0 DEBIAN_FRONTEND=n…   10.6MB    buildkit.dockerfile.v0
<missing>      About a minute ago   ARG DEBIAN_FRONTEND=noninteractive              0B        buildkit.dockerfile.v0
<missing>      About a minute ago   ARG LZ4_VERSION=v1.10.0                         0B        buildkit.dockerfile.v0
```

The image is 89 MB. The single `RUN` layer is 10.6 MB, while `make install`
in example 1 was about 1 MB. The rest of that layer is what stayed behind:
`ca-certificates` and the packages it needs, which were not purged, and
apt's own records.

The price of this style: the single `RUN` is all or nothing. Change one
character and the whole thing runs again. For a one-minute build that is
fine. Think about what it would mean for a two-hour build.

### Example 3: multi-stage

File: [`examples/ex3_multi_stage/Dockerfile`](examples/ex3_multi_stage/Dockerfile)

Now the build happens in a stage called `builder`, and the final stage starts
from a clean base and copies only `/opt/htop`. You get the small image of
example 2 and keep the step-by-step caching of example 1, because the builder
stage can have as many layers as you like. None of them are shipped.

Things to notice:

- `./configure --prefix=/opt/htop` is the autotools way to choose the install
  folder. One prefix means one `COPY --from`.
- htop is built with hwloc support here. The builder needs `libhwloc-dev`
  (headers). The final stage needs only `libhwloc15` (the shared library).
  Build-time and run-time needs differ.
- `RUN htop --version` in the final stage is a smoke test. If you forget the
  run-time library, the build fails right there.
- `USER ubuntu` makes containers run as a normal user.

`docker history ex3`, again without the layers of the base image:

```
IMAGE          CREATED         CREATED BY                                      SIZE      COMMENT
699440aa9022   5 minutes ago   CMD ["htop" "--version"]                        0B        buildkit.dockerfile.v0
<missing>      5 minutes ago   WORKDIR /work                                   0B        buildkit.dockerfile.v0
<missing>      5 minutes ago   USER ubuntu                                     0B        buildkit.dockerfile.v0
<missing>      5 minutes ago   RUN |1 DEBIAN_FRONTEND=noninteractive /bin/s…   0B        buildkit.dockerfile.v0
<missing>      5 minutes ago   ENV PATH=/opt/htop/bin:/usr/local/sbin:/usr/…   0B        buildkit.dockerfile.v0
<missing>      5 minutes ago   COPY /opt/htop /opt/htop # buildkit             1.78MB    buildkit.dockerfile.v0
<missing>      6 minutes ago   RUN |1 DEBIAN_FRONTEND=noninteractive /bin/s…   1.28MB    buildkit.dockerfile.v0
<missing>      6 minutes ago   ARG DEBIAN_FRONTEND=noninteractive              0B        buildkit.dockerfile.v0
```

The image is 81.2 MB: the base, 1.28 MB for the run-time library and
1.78 MB for htop. It is smaller than example 2 even though htop is the
bigger tool, because nothing from the build is left behind.

Try these:

```
docker build --target builder -t ex3-builder ex3_multi_stage
docker run --rm ex3-builder ldd /opt/htop/bin/htop
docker run --rm ex3 id
```

`ldd` lists the shared libraries a program needs (section 3.7). That is how
the `libhwloc15` line in the final stage was found. Then remove that
`apt-get` block from the final stage, rebuild, and read the error.

The `ex3-builder` stage is 427 MB. It installs more packages than example 1
and is still smaller, because it uses `--no-install-recommends`, removes the
apt package lists and makes a shallow clone.

### Measure

Fill in this table from `docker images` and `docker history` on your
machine. `ubuntu:24.04` only appears in `docker images` after
`docker pull ubuntu:24.04`, because the builder keeps base images in its own
cache. The values below are from the run on 2026-10-04.

| Image | Size (MB) | Biggest layer and what is in it |
|---|---|---|
| `ubuntu:24.04` | 78.2 | 78.2 MB: the whole Ubuntu base file system, added as one layer |
| `ex1` | 501 | 355 MB: the compiler, git and what they depend on |
| `ex2` | 88.8 | 78.2 MB: the base. Its own layer is 10.6 MB. |
| `ex3-builder` | 427 | The apt layer: compiler, autotools, git and the `-dev` packages |
| `ex3` | 81.2 | 78.2 MB: the base. Its own layers are 1.28 MB and 1.78 MB. |

### Example 4: a check script

File: [`examples/ex4_check_script/check_host.sh`](examples/ex4_check_script/check_host.sh)

This script checks the normal x86 tools in WSL, not the RISC-V ones. Run it
with `bash check_host.sh`. It decides pass or fail with exit codes: every
command hands a number back to the shell when it ends, 0 for success and
anything else for failure.

It shows the three patterns that the check script for the image is built
from:

1. A tool is installed and runs: `check ID "text" gcc --version`.
2. The output of a command contains some text: a pipeline that ends in
   `grep -q`, given to `bash -c` as one command.
3. Compile a program, run it, and compare its exit code with a number.

The shell pieces it uses:

| Piece | Meaning |
|---|---|
| `name=value` | Set a variable. No spaces around `=`. Read it back with `$name`. |
| `check() { ... }` | Define a function. Inside it, `$1` and `$2` are the first two arguments and `"$@"` is all of them. |
| `if command; then ... else ... fi` | Run the command, and take the first branch if its exit code is 0. |
| `> /dev/null 2>&1` | Throw away the command's output, so only the PASS or FAIL line shows. |
| `$?` | The exit code of the command that just ran. |
| `$(command)` | Run a command and use its output as text. |
| `grep -q text` | Returns 0 if the input contains the text, and prints nothing. In a pipeline, the exit code is that of the last command. |
| `test "$a" -eq 7` | Returns 0 if the two numbers are equal. |
| `exit 1` | End the script with a failing exit code. |

To see a failure, change `make` to a name that does not exist and run it
again.

## 5. Questions before coding

Answer these in your own words before you write the Dockerfile. Each one can
be answered from section 3. The answers are folded, so try first.

**Q1.** Your laptop has an Intel CPU. Which machine does
`riscv64-unknown-elf-gcc` run on, and which machine does its output run on?
What happens if you type `./hello` in WSL after compiling with it?

<details>
<summary>Answer</summary>

The compiler runs on x86-64. Its output is a linked ELF file with RISC-V
machine code, so it runs on a RISC-V machine. Here that machine is a
simulator, QEMU or Spike.

Typing `./hello` in WSL fails with `Exec format error`: the kernel reads the
ELF header and sees a machine type it cannot run. On a machine where Linux
is set up to hand foreign programs to QEMU automatically (this is called
binfmt), `./hello` would work, and that can hide the fact that a simulator
is involved.

</details>

**Q2.** The compiler is called `riscv64-...`, and you will use it for RV32IM.
What has to be in the toolchain for that to work? If it is missing, at which
step do you expect the failure: compile, assemble or link? Why that step?

<details>
<summary>Answer</summary>

The toolchain must be built with multilib, so that it has a copy of newlib,
`libgcc` and the startup file for `rv32im` with `ilp32`.

Without it the failure comes at the link step. Compile and assemble need
only your own source, and the compiler can emit RV32IM instructions in any
case. The linker is the first step that has to combine your code with the
prebuilt libraries, and it cannot link 32-bit code with libraries that were
built as 64-bit code.

</details>

**Q3.** Which `-mabi` goes with `-march=rv32im`? Why can it not be `ilp32d`?

<details>
<summary>Answer</summary>

`ilp32`. The `d` in `ilp32d` means floating-point arguments are passed in
the double-precision floating-point registers of the D extension. `ilp32f`
is the single-precision version and needs F. `rv32im` has neither, so both
are ruled out.

`float` and `double` still work with `rv32im` and `ilp32`. The values are
passed in integer registers and the arithmetic is done by helper routines in
`libgcc` (soft float). There is one more 32-bit ABI, `ilp32e`, which goes
with the reduced `rv32e` base of 16 registers. It is not for `rv32im`
either.

</details>

**Q4.** A Dockerfile has one `RUN` that clones 6 GB of sources and builds
them, and a later `RUN` that deletes the sources. How big is the image,
roughly, compared with one that never had the sources? Name two ways to fix
it, and say which one suits a two-hour build better.

<details>
<summary>Answer</summary>

The image is at least 6 GB larger. The sources sit in full in the layer of
the first `RUN`, together with the object files of the build, and a later
`RUN` cannot remove anything from an earlier layer.

Two fixes:

1. Clone, build and delete in one `RUN`.
2. Build in a builder stage and copy only the install folder into the final
   stage with `COPY --from`.

The builder stage suits a two-hour build better. With one combined `RUN`,
any change to that line, or to anything above it, reruns the whole two
hours. In a builder stage the work can be split over several `RUN` lines,
and the ones that did not change come from the cache, because none of those
layers are shipped anyway.

The two can also be combined, as the Dockerfile in this repo does for the
toolchain: a builder stage, and inside it one `RUN` that removes the sources
at the end. That keeps the builder stage small on your own disk too.

</details>

**Q5.** Your program calls `printf("hi\n")`. Follow the text from your
program to your terminal in two cases: under `qemu-riscv32`, and under Spike
with pk. Who handles the system call in each case?

<details>
<summary>Answer</summary>

The first part is the same in both cases. `printf` is a newlib function
inside your program. It builds the text and calls `write`, which puts the
system call number in `a7` and the arguments in `a0` to `a2` and executes
`ecall`.

- **QEMU user mode.** QEMU itself handles the `ecall`. It is x86 code: it
  reads the simulated registers, makes the matching real system call to the
  Linux kernel of your machine, writes the result into the simulated `a0`
  and carries on. The path is QEMU → host kernel → terminal.
- **Spike with pk.** The `ecall` raises a trap. The simulated processor
  jumps to the address in `mtvec`, which is pk's trap handler, and that
  handler is RISC-V code. pk writes a request to `tohost`. Spike picks it
  up, makes the real `write` call and puts the reply in `fromhost`. The path
  is pk → `tohost` → Spike → host kernel → terminal.

</details>

**Q6.** pk is built with `--host=riscv64-unknown-elf`. What does that tell
you about where pk runs? Which of your build stages must already be finished
before pk can be built? How many pk binaries do you need?

<details>
<summary>Answer</summary>

`--host` names the machine the built program will run on, so pk is a RISC-V
program. It never runs on the laptop's processor. It runs inside Spike, on
the simulated one. The table in section 3.2 puts it next to the compiler.

The toolchain stage must be finished first. A RISC-V program needs a
compiler that outputs RISC-V code, and the only one you have is the
cross-compiler. The value `riscv64-unknown-elf` is the name prefix of that
compiler, so `configure` knows to call `riscv64-unknown-elf-gcc`.

You need two pk binaries, one for RV32 and one for RV64. pk is the kernel
under your program: it loads the ELF file, sets up the stack and handles the
traps. A pk compiled as 64-bit code cannot run on a simulated 32-bit
processor, and Spike simulates one or the other in a given run.

`--host` stays `riscv64-unknown-elf` for both builds, because there is only
one compiler. The 32-bit build is selected with `--with-arch`.

</details>

**Q7.** Which registry will you publish to, and why? Write down the full
image name and the tag scheme you will use.

<details>
<summary>Answer</summary>

The GitHub Container Registry, because it uses the same GitHub account as
the repo and the image can be linked to the repo.

The image is `ghcr.io/rgantonio/compiler-study`, with numbered tags: `v1`,
`v2` and so on. A version tag is never pushed twice. Any published change to
the Dockerfile gets the next number, and `docs/setup.md` names the exact
version to pull.

</details>

**Q8.** On the shared server you might run the image with Apptainer, as your
own user, with a read-only image. Name two things you could write in a
Dockerfile that would break there.

<details>
<summary>Answer</summary>

Any two rows of the Apptainer table in section 3.10. For example: installing
the tools under `/root`, which a normal user cannot read, and setting `PATH`
in `~/.bashrc` of the image, which is hidden when the real home folder is
mounted over it.

Note that the question is about choices in the Dockerfile. "Apptainer cannot
build from a Dockerfile" and "the image is read-only" are facts about
Apptainer, not things a Dockerfile does.

</details>

## 6. Tasks

The Dockerfile goes in `util/container/Dockerfile`. Everything else you write
for this exercise goes in this folder's `src/` and `test/`, and in
`docs/setup.md`.

### Requirements for the image

| | Requirement |
|---|---|
| R1 | The base is `ubuntu:24.04`. |
| R2 | The RISC-V GNU toolchain is built from source, newlib variant, with multilib. RV32IM with the ILP32 ABI and at least one RV64 combination must be in the multilib list. |
| R3 | QEMU comes from apt, with user mode and system mode for both word sizes. |
| R4 | Spike is built from source. |
| R5 | pk is built from source with your own toolchain, once for RV32 and once for RV64. |
| R6 | Every source version is pinned with an `ARG` (a tag or a commit), not "whatever is newest today". |
| R7 | It is a multi-stage build. The final image has no source trees, no build folders and no git clones. |
| R8 | All tools are on `PATH` for any user. The image works when run as a non-root user and with a read-only file system. |
| R9 | No passwords or tokens are in the Dockerfile or the image. |
| R10 | The Dockerfile starts with an SPDX header, and each stage has a comment saying what it is for. |
| R11 | Settings that scripts need (flags, pk files, `--isa` values) are set once, with `ENV` in the Dockerfile, and scripts read them from there. |

### How to work

Do not write the whole Dockerfile and then wait two hours to see whether it
works. Work in a loop:

1. Start a throwaway container: `docker run --rm -it ubuntu:24.04 bash`.
2. Type the commands by hand until one tool builds and runs. Keep a text
   file open and paste in each command that worked.
3. Copy the working commands into the Dockerfile, as one stage.
4. Build only that stage with `--target` and check it.
5. Move on to the next tool.

A clean `ubuntu:24.04` container is the right place for step 2, because it
has nothing installed that could hide a missing package. To find out what a
tool needs, install only what you are sure of and run its `configure`. It
stops at the first thing that is missing and names it.

Lay out the whole file before any long build:

| Stage | Starts from | Needs from other stages | Build time |
|---|---|---|---|
| Toolchain | `ubuntu:24.04` | Nothing | 1 to 3 hours |
| Spike | `ubuntu:24.04` | Nothing. It is an x86 program built with the normal compiler. | Minutes |
| pk | The toolchain stage | The cross-compiler | Minutes |
| Final | `ubuntu:24.04` | The install folders of the three above, plus QEMU from apt | Minutes |

Then work from cheap to expensive:

| Step | Do | Check |
|---|---|---|
| A | T1: disk, memory, Docker works, what the server has | The numbers are written down |
| B | Final stage with only QEMU from apt | TC-03, TC-04 by hand |
| C | Spike stage, copied into the final stage | `ldd`, TC-05 |
| D | Toolchain stage. Test clone and configure first with the `make` line commented out, then start the long build. | TC-01, TC-02, TC-07, TC-08 in a shell in that stage |
| E | While D runs: `hello.c`, the check script, the first half of `docs/setup.md` | The script runs and fails for the right reasons |
| F | pk stage, tried by hand first in the tagged toolchain image | TC-06 |
| G | Finish the final stage: copies, run-time libraries, `ENV`, smoke test | TC-09 to TC-14 with the script |
| H | T8 and T9 | TC-15 |

While the toolchain stage is not built yet, keep its `COPY --from` line out
of the final stage. Otherwise building the final stage starts the long
build. Build Spike before the toolchain, not at the same time, on a machine
with little memory.

### Steps

**T1. Check your machines.** Make sure `docker build` works in WSL2 (run
example 1). Note the free disk (`df -h .`), the memory (`free -h`) and the
cores (`nproc`). Have about 20 GB of disk free for the toolchain build. Log
in to the shared server and find out which container tool it has. Write down
what you found. It goes into `docs/setup.md` later.

**T2. Plan.** Write the skeleton first: the `FROM ... AS ...` lines with a
comment under each saying what the stage installs and what it hands on.
Decide the install prefix and make a table of the versions you will pin.

**T3. The toolchain stage.** Write it and build only this stage with
`--target`, with `--progress=plain` and a log file. Decide the number of
parallel jobs from your memory before you start. When it is done, start a
shell in the stage, look at the multilib list, and compile `hello.c` for
RV32IM. The program cannot be run in this stage, since QEMU is only in the
final stage.

**T4. Spike and pk.** Add a stage for each. Check with `ldd` what Spike
needs at run time, the way example 3 does for htop. Check what kind of file
each pk is with `readelf -h`.

**T5. The final stage.** Start from a clean base, install QEMU and the
run-time libraries, copy in the tools, and set `PATH` and the other
variables with `ENV`. Add a smoke test that compiles and runs something.

**T6. Hello world.** Write two small C programs in `src/`. The first prints
one line and returns 0. The second returns 7 from `main`: a separate file,
because the test plan expects exit code 0 from one and 7 from the other. To
catch typos before the toolchain exists, compile them with the normal `gcc`
in WSL (`gcc -Wall -Wextra -o /tmp/hello hello.c`, then run it and look at
`echo $?`). Then compile both for RV32IM and for RV64 and run them by hand
on QEMU and on Spike with pk.

**T7. The check script.** Write a script in `test/` that runs inside the
container and covers the test plan in section 8. It prints one line per test
case with the ID and PASS or FAIL, and exits non-zero if any case fails.
Example 4 has the patterns. For the simulator runs you need a second helper
that compares the exit code with an expected number and looks for a text in
the output. Put compiled files in a temporary folder, not in `src/`. Save
the output of a passing run in `test/`.

**T8. Publish.** Tag the image, push it, and make it public. Then pull it on
the second machine, with whatever tool that machine has, and run the check
script there. Record the image digest.

**T9. Write `docs/setup.md`.** Someone who has never seen this repo should be
able to follow it. Cover at least: what you need installed, how to pull and
start the image, how to mount the repo, how to rebuild the image from
scratch and how long that takes, the table of pinned versions, and the notes
per machine from T1.

### Things that went wrong, and why

These are the problems met while writing the Dockerfile in this repo. Each
one is worth understanding, since the same kinds of problem come back with
other tools.

| What you see | Why | What to do |
|---|---|---|
| The apt step hangs | `tzdata` asks for a time zone and nobody answers | `ARG DEBIAN_FRONTEND=noninteractive` |
| `git clone`: `unknown option 'tag'` | A tag is selected with `--branch` | `git clone --depth 1 --branch <tag>` |
| `--branch` refuses a commit hash | It takes only tags and branches. Spike and pk have no recent tags. | Fetch the commit by its full hash, or clone and then `git checkout <hash>` |
| The toolchain clone downloads many GB | `--recursive` fetches every submodule with full history | Leave it out. The top-level repo holds build scripts and pointers, and `make` fetches the sources it needs. |
| The build is killed partway | Too many parallel jobs for the memory | Fewer jobs, or more memory for WSL |
| `../configure: not found` | The build folder is not inside the source folder. `WORKDIR` with a relative path is relative to the current folder. | Use full paths, and build in `<source>/build` |
| The Spike stage waits for the toolchain | It copies from the toolchain stage, which it does not need. `$RISCV` in Spike's README is only the install prefix. | Give Spike its own prefix and no `COPY --from` |
| Spike's `configure` finds no compiler | Its README lists only the extra packages and assumes a compiler and git | Add `build-essential`, `git`, `ca-certificates` |
| pk's `configure`: no acceptable C compiler | `--host=riscv32-unknown-elf` makes it look for a compiler of that name, which does not exist | Keep `--host=riscv64-unknown-elf` and choose 32-bit with `--with-arch` |
| pk's `configure` cannot find the compiler in a later `RUN` | `export PATH=...` lasts for one `RUN` | Set `PATH` with `ENV` in that stage |
| `gcc --version` works, but compiling fails with `error while loading shared libraries` | The compiler proper, `cc1`, needs the math libraries | `libgmp10`, `libmpc3`, `libmpfr6`, `libzstd1` in the final stage |
| GDB: `libpython3.12.so.1.0` not found | GDB was built with Python support, because the builder's package list includes Python | `libpython3.12t64` in the final stage |
| `dpkg -S` finds nothing for a path printed by `ldd` | `/lib` is a link to `/usr/lib` | Search by file name |
| `spike` without a program returns exit code 1 | That is what Spike does when it only prints its usage text | Test the output, not the exit code |
| The toolchain stage is 22 GB | The sources and the build folder are in its layers | Remove them in the same `RUN` as `make`. Only the install folder goes to the final image in any case. |
| The Spike install is 1.8 GB | Its programs and libraries are built with debug information | Remove it with `strip` in the builder stage. That leaves under 100 MB. |
| Editing the `make` line reruns the two-hour build | The instruction changed, so its cache entry no longer matches | Get the line right with a short test before the long build |
| Files in the repo belong to root | The container ran as root | `--user "$(id -u):$(id -g)"` on the `docker run` line |

## 8. Test plan

Each row is one test case. "Both" in the last column means the case runs
once for RV32 and once for RV64, and both runs count. The 32-bit
configuration is RV32IM with ILP32. The 64-bit one is RV64IMAC with LP64
(see section 3.4).

| ID | What is checked | Pass when | Word size |
|---|---|---|---|
| TC-01 | GCC is on `PATH` and reports its version | Exit code 0. The version line and the pinned toolchain release are printed for the log. | n/a |
| TC-02 | Assembler, linker, `objdump`, `readelf`, `size` and GDB are on `PATH` | Each prints a version, exit code 0 | n/a |
| TC-03 | QEMU user mode is installed | The 32-bit and the 64-bit program each print a version | Both |
| TC-04 | QEMU system mode is installed | The 32-bit and the 64-bit program each print a version | Both |
| TC-05 | Spike is installed | Spike starts and prints its usage text. Run without a program it returns exit code 1, so the output is the test, not the exit code. | n/a |
| TC-06 | pk exists for each word size | The file is found, and its ELF header says RISC-V with the right class (ELF32 or ELF64) | Both |
| TC-07 | Multilib list | `-print-multi-lib` has the entries for both configurations | Both |
| TC-08 | GCC picks the right library set | `-print-multi-directory` with the flags names the matching folder | Both |
| TC-09 | Hello world compiles and links | Exit code 0, and the ELF header of the output has the right class and machine | Both |
| TC-10 | Hello world on QEMU user mode | The expected line is printed, exit code 0 | Both |
| TC-11 | Hello world on Spike with pk | The expected line is printed, exit code 0 | Both |
| TC-12 | Exit codes pass through | A program that returns 7 from `main` gives exit code 7 from QEMU and from Spike | Both |
| TC-13 | Works as a normal user | The whole script passes when the container runs with your own user ID and the repo mounted | n/a |
| TC-14 | No build leftovers | None of the source or build folders from the earlier stages exist in the final image | n/a |
| TC-15 | Pull on the second machine | The script passes on an image pulled from the registry, and the digest matches the one you pushed | n/a |

TC-13 and TC-15 are about how the script is started, not about a line inside
it. Say in `docs/setup.md` how you ran them.

TC-12 uses 7 and not 0 because 0 is also what you would get if the simulator
ignored the program's result and reported its own success.

The script in this repo is [`test/check_docker.sh`](test/check_docker.sh).
It reads all settings from the environment of the image. Run it from the top
folder of the repo:

```
docker run --rm -v "$PWD":/work compiler-study:dev bash p0_setup/e1_dockerfile/test/check_docker.sh
```

## 9. RV64 compare

Compile the same hello world for RV32IM and for the RV64 configuration, with
the same optimization level, and fill in the table. The values below are
from the image built on 2026-10-05, compiled without an optimization flag.

| | RV32IM | RV64 |
|---|---|---|
| `-march` and `-mabi` | `-march=rv32im -mabi=ilp32` | `-march=rv64imac -mabi=lp64` |
| Output of `-print-multi-directory` | `rv32im/ilp32` | `rv64imac/lp64` |
| ELF class and machine from `readelf -h` | ELF32, RISC-V | ELF64, RISC-V |
| `text`, `data`, `bss` from `size` | 48793, 1151, 37040 | 46361, 1215, 41224 |
| Simulator commands that ran it | `qemu-riscv32 hello32` and `spike --isa=$SPIKE32_ISA $PK32 hello32` | `qemu-riscv64 hello64` and `spike --isa=$SPIKE64_ISA $PK64 hello64` |
| `sizeof(long)` and `sizeof(void *)`, printed by [`src/sizeof.c`](src/sizeof.c) | 4, 4 | 8, 8 |

**What `text`, `data` and `bss` are.** A compiled program is divided into
three parts, and `riscv64-unknown-elf-size <file>` prints how many bytes
each takes.

| Part | What is in it | Example in C | Where it can live |
|---|---|---|---|
| `text` | The machine instructions, plus constants that never change | Your functions, the string `"Hello, world!"` | ROM or flash, since it is never written |
| `data` | Global and static variables that start with a value other than zero | `int counter = 5;` outside any function | RAM. The starting values are also stored in the file. |
| `bss` | Global and static variables that start at zero | `int buffer[1000];` outside any function | RAM. It takes no space in the file: the file records only its size, and the startup code fills it with zeros. |

Local variables are in none of the three. They live on the stack while their
function runs. Most of the `text` of hello world is not your code but
newlib: `printf` pulls in number formatting, buffering and more.

**How to look at `main`.** Disassemble the program and show the first lines
of `main`:

```
riscv64-unknown-elf-objdump -d hello32 | grep -A 12 '<main>:'
```

When a function starts, it reserves a block of memory on the stack for its
own use: a place to save registers it must restore, and room for its local
variables. That block is its stack frame. The register `sp` holds the
address of the top of the stack, and the stack grows towards lower
addresses, so a function reserves its frame with `addi sp,sp,-N`, where `N`
is the frame size in bytes. The next lines store registers into the frame,
typically `ra` (the return address) and `s0` (the frame pointer). Two facts
are needed for the questions: a saved register takes as many bytes as the
register is wide, and the calling convention requires `sp` to stay a
multiple of 16.

Then answer:

1. Which instructions appear in one and not in the other? Give two examples
   and say what the difference is for.

<details>
<summary>Answer</summary>

`ld` and `sd` appear only in the RV64 version. They load and store a 64-bit
doubleword, and RV64 needs them because its registers and pointers are 64
bits wide: saving `ra` takes 8 bytes there. They do not exist on RV32.

`lw` and `sw` load and store a 32-bit word. RV32 uses them for everything.
They exist on RV64 too, where they are used for 32-bit values such as an
`int`.

</details>

2. How does the stack frame of `main` differ in size, and why?

<details>
<summary>Answer</summary>

It has the same size on both, 16 bytes, because the stack pointer must stay
a multiple of 16. The frames are filled differently. On RV32 the two saved
registers take 4 bytes each, so 8 of the 16 bytes are used, and `ra` is
stored with `sw ra,12(sp)`. On RV64 they take 8 bytes each and fill the
frame, with `sd ra,8(sp)`.

</details>

3. The program is the same C. Why is the `text` size not the same?

<details>
<summary>Answer</summary>

Not because instructions are wider on RV64. A normal instruction is 32 bits
on both, and a compressed one is 16 bits on both. The reasons are:

- **Compressed instructions on one side only.** `rv64imac` may use the
  16-bit short forms and `rv32im` may not. This is the main reason the RV64
  `text` is the smaller one in the table above.
- **Different library code.** Most of `text` is newlib, and each side links
  its own copy, compiled separately for its flags.
- **64-bit arithmetic.** `printf` handles 64-bit numbers. RV64 does that in
  single instructions. RV32 needs several instructions or helper routines
  from `libgcc`.
- **Pointer size.** Tables of addresses are counted in `text`, and each
  entry is 4 bytes on RV32 and 8 on RV64. The same effect makes `data` and
  `bss` larger on RV64.
- **Sign extension.** RV64 sometimes needs an extra instruction to keep a
  32-bit `int` correct inside a 64-bit register.

To see the first effect alone, compile the RV32 side a second time with
`-march=rv32imac -mabi=ilp32`, which is also in the multilib list, and
compare the two RV32 numbers.

</details>

## 10. Study questions

These are for review. Come back to them later and answer without notes.

1. What do the three parts of `riscv64-unknown-elf` mean? What would change
   in your programs if the toolchain were `riscv64-unknown-linux-gnu`?
2. Explain multilib to someone who knows C but has never linked by hand.
3. GCC accepted `-march=rv32im` and produced an object file, but the link
   failed. Give one likely cause and the command you would use to check.
4. Why does deleting files in a later `RUN` not shrink the image?
5. You change one line in the Spike part of the Dockerfile. Which steps run
   again, and which come from the cache? What in the file arranges that?
6. What is the difference between `ARG` and `ENV`? Give one use of each from
   the Dockerfile.
7. What is the difference between QEMU user mode and QEMU system mode? Which
   one could run a program that has no C library and no system calls at all?
8. Why does Spike need pk for hello world, and why does QEMU user mode not?
9. What is the difference between a tag and a digest? Which one should
   `docs/setup.md` tell people to pull, and why?
10. A file created in the mounted repo from inside the container belongs to
    root on your laptop. Why, and what are two ways to avoid it?
11. `ldd` shows no missing library for a tool, and the tool still fails in
    the final image. Name two reasons this can happen.

## 11. Extensions (optional)

- **CI build.** Add a GitHub Actions workflow that builds and pushes the
  image when the Dockerfile changes. Check the job time limit against your
  build time first.
- **Cache mounts.** Read about `RUN --mount=type=cache` and decide whether it
  helps any step of your build.
- **Lint.** Run `docker build --check` or `hadolint` on the Dockerfile and
  decide for each warning whether you agree.
- **Custom multilib list.** Read about the multilib generator option in the
  toolchain README. Build only the combinations this course needs, add a
  plain `rv64im`, and compare build time and image size with the default
  list.
- **Apptainer.** Convert the published image to a `.sif` file on the server
  and add the commands to `docs/setup.md`.
- **Prebuilt comparison.** The toolchain project also publishes prebuilt
  archives. Compare their multilib list with yours.

## 12. Reflection

Fill this in when everything passes.

**What took the longest, and what would you do differently next time?**

<details>
<summary>Your answer</summary>

</details>

**Which build failure taught you the most? What was the cause?**

<details>
<summary>Your answer</summary>

</details>

**Final image size, build time, and the size of the largest stage. Is the
final size about what you expected from your plan in T2?**

<details>
<summary>Your answer</summary>

</details>

**What is still unclear? List the things you want to ask about.**

<details>
<summary>Your answer</summary>

</details>
