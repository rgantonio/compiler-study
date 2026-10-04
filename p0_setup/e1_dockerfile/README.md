# p0/e1: Write the Dockerfile

## 1. Header

| | |
|---|---|
| Part | 0, Setup |
| Section | e1 (first exercise of the part) |
| Expected time | About 90 minutes of your own work, best split over two or three sittings. On top of that, one to three hours of build time that you do not need to watch. |
| Prerequisites | A working Linux shell (WSL2 on the laptop). A GitHub account. No RISC-V or Docker knowledge is assumed. |
| You write | `util/container/Dockerfile`, `src/`, `test/`, `drawings/` in this folder, and `docs/setup.md` |

The build of the compiler is slow. Plan the work so that the long build runs
while you do something else, for example overnight or during a meeting.

## 2. What you are learning

After this exercise you can:

- say what each tool in the image is for, and which machine it runs on;
- explain what a cross-compiler is, and why one compiler binary can serve
  both RV32 and RV64 once it has multilib;
- write a multi-stage Dockerfile that builds tools from source and keeps the
  final image free of build leftovers;
- publish an image to a registry and pull it on a second machine;
- prove with a script that the image does what the course needs.

## 3. Theory

Read sections 3.1 to 3.4 before the questions in section 5. Sections 3.5 to
3.9 are for the Dockerfile work, and you can read them when you get there.

### 3.1 The tools in the image

| Tool | What it is | What you use it for in this course |
|---|---|---|
| GCC (`riscv64-unknown-elf-gcc`) | The C compiler. Turns C into RISC-V assembly, and drives the other steps. | Every exercise. |
| Binutils (`as`, `ld`, `objdump`, `readelf`, `size`, ...) | The assembler, the linker, and tools that inspect object files. | Parts 1 and 2: reading compiler output, linker scripts. |
| newlib | A small C library for systems without an operating system. Gives you `printf`, `malloc`, `memcpy`. | Linked into your programs. Part 2 looks inside it. |
| GDB (`riscv64-unknown-elf-gdb`) | The debugger. | Part 2: stepping from reset to `main`. |
| QEMU | A fast emulator. Runs RISC-V programs on your x86 machine. | The main simulator. |
| Spike | The reference simulator for the RISC-V instruction set. Slower than QEMU, but follows the specification closely and prints instruction traces. | The second simulator, to cross-check QEMU. |
| pk (proxy kernel) | A very small kernel that runs inside Spike. It loads your program and passes its system calls to the host. | Running a normal C program on Spike. |

The first four come from one repository, `riscv-gnu-toolchain`, which fetches
and builds GCC, Binutils, newlib and GDB together.

### 3.2 What a cross-compiler is

A normal (native) compiler makes programs for the machine it runs on. A
cross-compiler runs on one kind of machine and makes programs for another.
Yours runs on x86-64 and makes programs for RISC-V. You cannot run its output
directly on your laptop, which is why the image also holds simulators.

Build systems use three words for the machines involved:

| Word | Meaning | For your compiler |
|---|---|---|
| build | The machine where the tool is compiled | x86-64 Linux (inside the container) |
| host | The machine where the tool will run | x86-64 Linux |
| target | The machine the tool produces code for | RISC-V |

You will meet `--host` again when you build pk. pk is a program that runs on
RISC-V, so for pk the host is RISC-V, not x86. Keep this table next to you
when you read the pk README.

The name of the compiler tells you its target. `riscv64-unknown-elf` reads as
architecture, vendor, system. `elf` means there is no operating system: the
program is a plain ELF file and the C library is newlib. The other common
target, `riscv64-unknown-linux-gnu`, makes programs for RISC-V Linux with
glibc. This course uses the `elf` one, because part 2 is bare-metal.

### 3.3 `-march` and `-mabi`

Two flags tell GCC what kind of RISC-V code to make.

`-march` is the set of instructions the compiler may use. `rv32im` means the
32-bit base instructions (`rv32i`) plus multiply and divide (`m`).

`-mabi` is the calling convention and the size of the basic C types. `ilp32`
means `int`, `long` and pointers are all 32 bits, and floating-point values
are passed in integer registers. `lp64` means `long` and pointers are 64 bits.
A letter at the end (`ilp32f`, `lp64d`) means floating-point arguments travel
in floating-point registers, which only works if `-march` has those registers.

All object files and libraries in one program must use the same ABI.

### 3.4 What multilib is

The compiler can emit instructions for any `-march` you ask for. The problem
is at link time. Your program is linked with libraries that were compiled
earlier: newlib, the startup file, and `libgcc` (helper routines the compiler
calls, for example 64-bit division on a 32-bit machine). Those libraries must
match your `-march` and `-mabi`. A library full of 64-bit code cannot be
linked into a 32-bit program.

Multilib means the toolchain was built with several copies of these
libraries, one per combination of `-march` and `-mabi`. At link time GCC
picks the copy that fits your flags. Without multilib, the toolchain has one
copy, for one combination, and the name prefix `riscv64-` is the only thing
it can really link for.

Whether multilib is on, and which combinations are built, is decided when the
toolchain is configured. More combinations mean a longer build and a bigger
install.

Three commands show what a finished toolchain has:

| Command | Shows |
|---|---|
| `riscv64-unknown-elf-gcc -print-multi-lib` | Every library set that was built |
| `riscv64-unknown-elf-gcc -march=... -mabi=... -print-multi-directory` | Which set GCC picks for these flags |
| `riscv64-unknown-elf-gcc -march=... -mabi=... -print-libgcc-file-name` | The exact `libgcc.a` it would link |

### 3.5 The simulators

QEMU has two modes, and both are used in this course.

| Mode | Program name | What it simulates | Used in |
|---|---|---|---|
| User mode | `qemu-riscv32`, `qemu-riscv64` | Only the CPU. System calls from your program are handed to the Linux kernel of the host. | Part 1, and this exercise |
| System mode | `qemu-system-riscv32`, `qemu-system-riscv64` | A whole board: CPU, memory, UART, timer. | Part 2 |

Spike simulates a bare RISC-V processor and memory. There is no operating
system inside it, so a program that calls `printf` has nobody to give the
output to. pk fills that gap. Spike starts pk, pk loads your program, and
when your program makes a system call, pk forwards it through Spike to the
host. pk is a RISC-V program, so it is built with your cross-compiler, and a
32-bit program needs a 32-bit pk.

Spike simulates RV64 unless you tell it otherwise with `--isa`.

### 3.6 Images, layers and the build cache

A few words first.

- An **image** is a read-only file system plus some settings (environment
  variables, default command). It is what you build and publish.
- A **container** is a running copy of an image. It gets a thin writable
  layer on top, which is thrown away when the container is removed.
- A **Dockerfile** is the recipe for an image.
- A **layer** is the set of file changes made by one instruction. An image is
  a stack of layers.
- The **build context** is the folder you pass to `docker build`. Only files
  in it can be used by `COPY`. A `.dockerignore` file keeps things out of it.
- A **registry** is a server that stores images (Docker Hub, ghcr.io).

Two rules explain most of what you will see.

Layers only add. If one instruction creates a file and a later instruction
deletes it, the file is hidden in the final file system, but its bytes are
still stored in the earlier layer and are still downloaded by everyone who
pulls the image.

The cache is used top to bottom. Docker reuses a layer if the instruction and
its inputs did not change, and if every layer above it was reused too. Once
one instruction changes, everything below it runs again. So put slow steps
that rarely change near the top, and things you are still editing near the
bottom.

A multi-stage build has several `FROM` lines. Each one starts a new, empty
stage. A later stage can copy files out of an earlier one with
`COPY --from=<stage>`. Only the last stage becomes the image, so compilers
and source trees can stay behind in the earlier stages.

### 3.7 Docker commands you will use

| Command | What it does |
|---|---|
| `docker build -t NAME:TAG -f path/Dockerfile CONTEXT` | Build an image. `CONTEXT` is the folder sent to the builder. |
| `docker build --target STAGE ...` | Stop after one stage. Good for working on stages one at a time. |
| `docker build --build-arg KEY=VALUE ...` | Override an `ARG`. |
| `docker build --progress=plain ...` | Show the full output of each step, not the folded view. |
| `docker build --no-cache ...` | Ignore the cache. Rarely what you want with a two-hour step. |
| `docker images` | List local images and their sizes. |
| `docker history NAME:TAG` | List the layers of an image with the size of each. |
| `docker run --rm -it NAME:TAG bash` | Start a container with a shell. `--rm` removes it on exit. |
| `docker run --rm -v "$PWD":/work -w /work NAME:TAG CMD` | Run one command with the current folder mounted at `/work`. |
| `docker run --user "$(id -u):$(id -g)" ...` | Run as your own user, so files written to a mounted folder belong to you. |
| `docker ps -a` | List containers, including stopped ones. |
| `docker exec -it CONTAINER bash` | Open a second shell in a running container. |
| `docker inspect NAME:TAG` | Show settings of an image: environment, user, labels, digest. |
| `docker tag OLD NEW` | Give an image a second name, for example the registry name. |
| `docker login REGISTRY` | Log in before pushing. |
| `docker push NAME:TAG`, `docker pull NAME:TAG` | Upload and download. |
| `docker system df` | Show how much disk Docker uses. |
| `docker builder prune` | Delete the build cache. This throws away your long build. |
| `docker image rm NAME:TAG` | Delete one local image. |

When a build step fails, build the stage above it with `--target`, start a
shell in that image, and run the failing command by hand.

### 3.8 Registries and tags

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

### 3.9 Your two machines

**WSL2 on the laptop.** Docker runs either through Docker Desktop on Windows
with WSL integration turned on, or as Docker Engine installed inside the WSL
distribution. Keep the repo in the Linux file system (under your home
folder), not under `/mnt/c`, or file access gets slow. WSL2 gets only part
of the laptop's memory by default, and compiling GCC with many parallel jobs
can run out. If the build dies with a killed compiler process, lower the job
count or raise the limit in `.wslconfig`.

**The shared server.** You may not have Docker there. The same published
image works with the other common tools:

| Tool | Builds from a Dockerfile | Runs your published image | Who you are inside |
|---|---|---|---|
| Docker | Yes | Yes | Root, unless the image or `--user` says otherwise |
| Podman | Yes, same file and almost the same commands | Yes | In rootless mode: root inside, mapped to your own user outside |
| Apptainer | No | Yes, it converts the image to a `.sif` file | Always your own user. The image is read-only and your home folder is mounted. |

This has consequences for your Dockerfile. Do not depend on being root at
run time. Do not put tools in `/root`. Set `PATH` with `ENV` so every tool
finds it.

### 3.10 Pages to read

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

The examples build two small tools that have nothing to do with RISC-V:
`lz4` (a file compressor) and `htop` (a process viewer). Each builds in a
minute or two, so you can try things quickly. Build all three and compare them
before you start your own file.

```
cd p0_setup/e1_dockerfile/examples
docker build -t ex1 ex1_plain
docker build -t ex2 ex2_one_layer
docker build -t ex3 ex3_multi_stage
docker images
```

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

Somewhat an expected output looks like:

```bash
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

Note that the build is also 501 MB large.

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

Run `docker history ex2` and compare with example 1.

The price: the single `RUN` is all or nothing. Change one character and the
whole thing runs again. For a one-minute build that is fine. Think about what
it would mean for a two-hour build.

```bash
IMAGE          CREATED              CREATED BY                                      SIZE      COMMENT
6b97ebb2f60d   About a minute ago   CMD ["lz4" "--version"]                         0B        buildkit.dockerfile.v0
<missing>      About a minute ago   WORKDIR /work                                   0B        buildkit.dockerfile.v0
<missing>      About a minute ago   ENV PATH=/opt/lz4/bin:/usr/local/sbin:/usr/l…   0B        buildkit.dockerfile.v0
<missing>      About a minute ago   RUN |2 LZ4_VERSION=v1.10.0 DEBIAN_FRONTEND=n…   10.6MB    buildkit.dockerfile.v0
<missing>      About a minute ago   ARG DEBIAN_FRONTEND=noninteractive              0B        buildkit.dockerfile.v0
<missing>      About a minute ago   ARG LZ4_VERSION=v1.10.0                         0B        buildkit.dockerfile.v0
<missing>      2 weeks ago          /bin/sh -c #(nop)  CMD ["/bin/bash"]            0B        
<missing>      2 weeks ago          /bin/sh -c #(nop) ADD file:6c214fc3c3c22122c…   78.2MB    
<missing>      2 weeks ago          /bin/sh -c #(nop)  LABEL org.opencontainers.…   0B        
<missing>      2 weeks ago          /bin/sh -c #(nop)  ARG LAUNCHPAD_BUILD_ARCH     0B        
<missing>      2 weeks ago          /bin/sh -c #(nop)  ARG RELEASE                  0B
```

The docker image size is only 89 MB.

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

The `docker history ex3` shows:

```bash
IMAGE          CREATED         CREATED BY                                      SIZE      COMMENT
699440aa9022   5 minutes ago   CMD ["htop" "--version"]                        0B        buildkit.dockerfile.v0
<missing>      5 minutes ago   WORKDIR /work                                   0B        buildkit.dockerfile.v0
<missing>      5 minutes ago   USER ubuntu                                     0B        buildkit.dockerfile.v0
<missing>      5 minutes ago   RUN |1 DEBIAN_FRONTEND=noninteractive /bin/s…   0B        buildkit.dockerfile.v0
<missing>      5 minutes ago   ENV PATH=/opt/htop/bin:/usr/local/sbin:/usr/…   0B        buildkit.dockerfile.v0
<missing>      5 minutes ago   COPY /opt/htop /opt/htop # buildkit             1.78MB    buildkit.dockerfile.v0
<missing>      6 minutes ago   RUN |1 DEBIAN_FRONTEND=noninteractive /bin/s…   1.28MB    buildkit.dockerfile.v0
<missing>      6 minutes ago   ARG DEBIAN_FRONTEND=noninteractive              0B        buildkit.dockerfile.v0
<missing>      2 weeks ago     /bin/sh -c #(nop)  CMD ["/bin/bash"]            0B        
<missing>      2 weeks ago     /bin/sh -c #(nop) ADD file:6c214fc3c3c22122c…   78.2MB    
<missing>      2 weeks ago     /bin/sh -c #(nop)  LABEL org.opencontainers.…   0B        
<missing>      2 weeks ago     /bin/sh -c #(nop)  ARG LAUNCHPAD_BUILD_ARCH     0B        
<missing>      2 weeks ago     /bin/sh -c #(nop)  ARG RELEASE                  0B 
```

The size is like 81.2 MB.

Try these:

```
docker build --target builder -t ex3-builder ex3_multi_stage
docker run --rm ex3-builder ldd /opt/htop/bin/htop
docker run --rm ex3 id
```

`ldd` lists the shared libraries a program needs. That is how the
`libhwloc15` line in the final stage was found. Then remove that `apt-get`
block from the final stage, rebuild, and read the error.

Note that the size of `ex3-builder` is 427 MB. Slightly smaller than the original `ex1`.

### Measure

Fill in this table from `docker images` and `docker history` on your machine. Note that we have to download `ubuntu:24.04` via `docker pull ubuntu:24.04`.

| Image          | Size (MB) | Biggest layer and what is in it |
|----------------|-----------|---------------------------------|
| `ubuntu:24.04` |      78.2 | /bin/sh -c #(nop) ADD file:6c214fc3c3c22122c7eb68f7fb32783df308e60b1eaeb9baf7e4d0cc961d448d in /|
| `ex1`          |       501 | RUN |1 LZ4_VERSION=v1.10.0 /bin/sh -c apt-get install -y build-essential git ca-certificates # buildkit |
| `ex2`          |      88.8 | ADD file:6c214fc3c3c22122c7eb68f7fb32783df308e60b1eaeb9baf7e4d0cc961d448d in / |
| `ex3-builder`  |       427 | RUN |2 HTOP_VERSION=3.5.3 DEBIAN_FRONTEND=noninteractive /bin/sh -c apt-get update  && apt-get install -y --no-install-recommends         build-essential autoconf automake pkg-config         git ca-certificates libncurses-dev libhwloc-dev  && rm -rf /var/lib/apt/lists/* # buildkit                                |
| `ex3`          |      81.2 | /bin/sh -c #(nop) ADD file:6c214fc3c3c22122c7eb68f7fb32783df308e60b1eaeb9baf7e4d0cc961d448d in /|

## 5. Questions before coding

Answer these in your own words before you write the Dockerfile. Short answers
are fine.

**Q1.** Your laptop has an Intel CPU. Which machine does
`riscv64-unknown-elf-gcc` run on, and which machine does its output run on?
What happens if you type `./hello` in WSL after compiling with it?

<details>
<summary>Your answer</summary>

</details>

**Q2.** The compiler is called `riscv64-...`, and you will use it for RV32IM.
What has to be in the toolchain for that to work? If it is missing, at which
step do you expect the failure: compile, assemble or link? Why that step?

<details>
<summary>Your answer</summary>

</details>

**Q3.** Which `-mabi` goes with `-march=rv32im`? Why can it not be `ilp32d`?

<details>
<summary>Your answer</summary>

</details>

**Q4.** A Dockerfile has one `RUN` that clones 6 GB of sources and builds
them, and a later `RUN` that deletes the sources. How big is the image,
roughly, compared with one that never had the sources? Name two ways to fix
it, and say which one suits a two-hour build better.

<details>
<summary>Your answer</summary>

</details>

**Q5.** Your program calls `printf("hi\n")`. Follow the text from your
program to your terminal in two cases: under `qemu-riscv32`, and under Spike
with pk. Who handles the system call in each case?

<details>
<summary>Your answer</summary>

</details>

**Q6.** pk is built with `--host=riscv64-unknown-elf`. What does that tell
you about where pk runs? Which of your build stages must already be finished
before pk can be built? How many pk binaries do you need?

<details>
<summary>Your answer</summary>

</details>

**Q7.** Which registry will you publish to, and why? Write down the full
image name and the tag scheme you will use.

<details>
<summary>Your answer</summary>

</details>

**Q8.** On the shared server you might run the image with Apptainer, as your
own user, with a read-only image. Name two things a Dockerfile could do that
would break there.

<details>
<summary>Your answer</summary>

</details>

## 6. Tasks

The Dockerfile goes in `util/container/Dockerfile`. Everything else you write
for this exercise goes in this folder's `src/`, `test/` and `drawings/`, and
in `docs/setup.md`.

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

### Steps

**T1. Check your machines.** Make sure `docker build` works in WSL2 (run
example 1). Note how much free disk and memory WSL has. Read what the
toolchain README says about disk space. Log in to the shared server and find
out which container tool it has. Write down what you found. It goes into
`docs/setup.md` later.

**T2. Plan on paper.** Decide the stages, what each one installs, and what
the final stage copies from each. Decide the install prefix. Make a table of
the versions you will pin. This plan is the first half of the drawing task in
section 7, so do the drawing now.

**T3. The toolchain stage.** Write it and build only this stage with
`--target`. This is the long step. Before you start it, decide how many
parallel jobs your memory allows. When it is done, start a shell in the
stage and look at the multilib list.

Think about cache order before you start the long build. Anything you edit
above the toolchain step makes it run again.

**T4. Spike and pk.** Add them. Check with `ldd` what Spike needs at run
time, the way example 3 does for htop. Check what kind of file each pk is
with `file` or `readelf -h`.

**T5. The final stage.** Start from a clean base, install QEMU and the
run-time libraries, copy in the tools, set `PATH`, the user and the working
folder. Add a smoke test.

**T6. Hello world.** Write a small C program in `src/` that prints one line
and returns 0. Compile it for RV32IM and run it by hand on QEMU and on Spike
with pk. Then do the same for RV64.

**T7. The check script.** Write a script in `test/` that runs inside the
container and covers every row of the test plan in section 8. It prints one
line per test case with the ID and PASS or FAIL, and exits non-zero if any
case fails. Save its output from a passing run in `test/`.

**T8. Publish.** Tag the image, push it, and make it public. Then pull it on
the second machine, with whatever tool that machine has, and run the check
script there. Record the image digest.

**T9. Write `docs/setup.md`.** Someone who has never seen this repo should be
able to follow it. Cover at least: what you need installed, how to pull and
start the image, how to mount the repo, how to rebuild the image from
scratch and how long that takes, the table of pinned versions, and the notes
per machine from T1.

## 7. Drawing task

Make one drawing with two parts. Paper and a photo is fine. Save it in
`drawings/`.

**Part A: the build.** Draw each stage of your Dockerfile as a box. In each
box write what is installed or built there. Draw an arrow for every
`COPY --from`, labelled with the folder that is copied. Mark which box
becomes the published image, and write the size you measured next to each
stage.

**Part B: who runs where.** Draw the path of your hello world from source
file to output on the terminal, once for QEMU and once for Spike with pk.
For every program on the path (GCC, the linker, QEMU, Spike, pk, hello
itself) mark whether it is x86-64 code or RISC-V code, and mark where the
`write` system call ends up.

Do part A before T3 and correct it afterwards if the real file turned out
differently. Do part B after T6.

## 8. Test plan

You write the script. Each row is one test case. "Both" in the last column
means the case runs once for RV32 and once for RV64, and both runs count.
Use RV32IM with ILP32 as the 32-bit configuration and pick the 64-bit one
from your multilib list.

| ID | What is checked | Pass when | Word size |
|---|---|---|---|
| TC-01 | GCC is on `PATH` and reports its version | Exit code 0, and the version matches what you pinned | n/a |
| TC-02 | Assembler, linker, `objdump`, `readelf` and GDB are on `PATH` | Each prints a version, exit code 0 | n/a |
| TC-03 | QEMU user mode is installed | The 32-bit and the 64-bit program each print a version | Both |
| TC-04 | QEMU system mode is installed | The 32-bit and the 64-bit program each print a version | Both |
| TC-05 | Spike is installed | Spike starts and prints its usage text. Look at its exit code yourself before you decide what "pass" means here. | n/a |
| TC-06 | pk exists for each word size | The file is found, and its ELF header says RISC-V with the right class (ELF32 or ELF64) | Both |
| TC-07 | Multilib list | `-print-multi-lib` has an entry for `rv32im` with `ilp32`, and at least one RV64 entry | n/a |
| TC-08 | GCC picks the right library set | `-print-multi-directory` with your flags names the matching folder, not `.` for RV32 | Both |
| TC-09 | Hello world compiles and links | Exit code 0, and the ELF header of the output has the right class and machine | Both |
| TC-10 | Hello world on QEMU user mode | The expected line is printed, exit code 0 | Both |
| TC-11 | Hello world on Spike with pk | The expected line is printed, exit code 0 | Both |
| TC-12 | Exit codes pass through | A program that returns 7 from `main` gives exit code 7 from QEMU and from Spike | Both |
| TC-13 | Works as a normal user | The whole script passes when the container runs with your own user ID and the repo mounted | n/a |
| TC-14 | No build leftovers | None of the source or build folders from the earlier stages exist in the final image | n/a |
| TC-15 | Pull on the second machine | The script passes on an image pulled from the registry, and the digest matches the one you pushed | n/a |

TC-13 and TC-15 are about how the script is started, not about a line inside
it. Say in `docs/setup.md` how you ran them.

## 9. RV64 compare

Compile the same hello world for RV32IM and for your RV64 configuration, with
the same optimization level, and fill in the table.

| | RV32IM | RV64 |
|---|---|---|
| `-march` and `-mabi` you used | | |
| Output of `-print-multi-directory` | | |
| ELF class and machine from `readelf -h` | | |
| `text`, `data`, `bss` from `size` | | |
| Simulator commands that ran it | | |
| `sizeof(long)` and `sizeof(void *)`, printed by a small program | | |

Then disassemble `main` from both with `objdump -d` and answer:

1. Which instructions appear in one and not in the other? Give two examples
   and say what the difference is for.
2. How does the stack frame of `main` differ in size, and why?
3. The program is the same C. Why is the `text` size not the same?

<details>
<summary>Your answers</summary>

</details>

## 10. Study questions

I ask two or three of these when grading. Be ready to answer without notes.

1. What do the three parts of `riscv64-unknown-elf` mean? What would change
   in your programs if the toolchain were `riscv64-unknown-linux-gnu`?
2. Explain multilib to someone who knows C but has never linked by hand.
3. GCC accepted `-march=rv32im` and produced an object file, but the link
   failed. Give one likely cause and the command you would use to check.
4. Why does deleting files in a later `RUN` not shrink the image?
5. You change one line in the Spike part of your Dockerfile. Which steps run
   again, and which come from the cache? How did you arrange that?
6. What is the difference between `ARG` and `ENV`? Give one use of each from
   your file.
7. What is the difference between QEMU user mode and QEMU system mode? Which
   one could run a program that has no C library and no system calls at all?
8. Why does Spike need pk for hello world, and why does QEMU user mode not?
9. What is the difference between a tag and a digest? Which one should
   `docs/setup.md` tell people to pull, and why?
10. A file created in the mounted repo from inside the container belongs to
    root on your laptop. Why, and what are two ways to avoid it?

## 11. Extensions (optional)

- **CI build.** Add a GitHub Actions workflow that builds and pushes the
  image when the Dockerfile changes. Check the job time limit against your
  build time first.
- **Cache mounts.** Read about `RUN --mount=type=cache` and decide whether it
  helps any step of your build.
- **Lint.** Run `docker build --check` or `hadolint` on your Dockerfile and
  decide for each warning whether you agree.
- **Custom multilib list.** Read about the multilib generator option in the
  toolchain README. Build only the combinations this course needs and compare
  build time and image size with the default list.
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

## 13. Grading record

To hand in: push your branch and tell me the commit and the published image
name. I read the Dockerfile, the check script and its saved output, the
drawing, `docs/setup.md`, and your answers in sections 5, 9 and 12.

| Date | Commit | Result | Notes |
|---|---|---|---|
| | | | |
