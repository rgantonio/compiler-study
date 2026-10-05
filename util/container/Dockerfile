# SPDX-License-Identifier: Apache-2.0
# Author: rgantonio
#
# Toolchain image for the compiler-study course.
#
# What is in the final image:
#   - RISC-V GNU toolchain (GCC, binutils, newlib, GDB), built from source
#     with multilib, in /tools/riscv
#   - Spike, built from source, in /tools/spike
#   - pk, built from source for RV32 and RV64, in /tools/pk
#   - QEMU user mode and system mode, from apt
#
# Stages:
#   toolchain   builds the cross-compiler            (the long one)
#   spike       builds Spike                         (independent)
#   pk          builds pk with the cross-compiler    (starts from toolchain)
#   final       clean base + QEMU + the three install folders
#
# Build one stage at a time, from the top folder of the repo:
#   docker build --target spike     -t compiler-study:spike     -f util/container/Dockerfile util/container
#   docker build --target toolchain -t compiler-study:toolchain -f util/container/Dockerfile util/container
#   docker build --target final     -t compiler-study:dev       -f util/container/Dockerfile util/container
#
# The quick guide is in the README.md at the top of the repo.

# ---------------------------------------------------------------------------
# Settings. This is the one place where versions and build options are set.
# Override any of them with: --build-arg NAME=value
# ---------------------------------------------------------------------------
ARG BASE_IMAGE=ubuntu:24.04

# Pinned sources. The toolchain has dated release tags. Spike and pk have no
# recent tags, so they are pinned by commit (both from 2026-10-05).
ARG RISCV_GNU_TOOLCHAIN_TAG=2026.08.27
ARG SPIKE_COMMIT=609dbe0b9994154833039209fa37151e7c05e9d4
ARG PK_COMMIT=9c61d29846d8521d9487a57739330f9682d5b542

# Parallel jobs for make. Compiling GCC needs about 2 GB of memory per job,
# so choose this from your memory, not from your core count. Changing the
# value makes the build steps run again, so choose once per machine.
ARG JOBS=4

# Architecture of the 32-bit pk. It must be a combination that exists in the
# multilib list. The 64-bit pk uses pk's default (RV64GC).
ARG PK32_ARCH=rv32imac_zicsr_zifencei


# ---------------------------------------------------------------------------
# Stage: toolchain
# RISC-V GNU toolchain, newlib variant, with multilib. Installs to
# /tools/riscv. Takes one to three hours.
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS toolchain

# Stops apt from asking questions (the time zone, for one). ARG, not ENV, so
# it is not set in the finished image.
ARG DEBIAN_FRONTEND=noninteractive

# The package list from the toolchain README, one per line, in alphabetical
# order.
RUN apt-get update \
 && apt-get install -y \
        autoconf \
        automake \
        autotools-dev \
        bc \
        bison \
        build-essential \
        cmake \
        curl \
        device-tree-compiler \
        expect \
        flex \
        gawk \
        git \
        gperf \
        libexpat-dev \
        libglib2.0-dev \
        libgmp-dev \
        libmpc-dev \
        libmpfr-dev \
        libncurses-dev \
        libslirp-dev \
        libtool \
        libzstd-dev \
        meson \
        ninja-build \
        patchutils \
        python3 \
        python3-pip \
        python3-tomli \
        texinfo \
        zlib1g-dev \
 && rm -rf /var/lib/apt/lists/*

# Declared here, just before first use: an ARG is part of the cache key of
# every RUN below it.
ARG RISCV_GNU_TOOLCHAIN_TAG
ARG JOBS

# Clone, configure, build, install and clean up in one RUN. The top-level
# clone is small; the GCC, binutils, newlib and GDB sources are fetched by
# make. Removing the source folder in the same RUN keeps many GB out of
# this layer. In this repo, make also installs into the prefix.
RUN git clone --depth 1 --branch ${RISCV_GNU_TOOLCHAIN_TAG} \
        https://github.com/riscv-collab/riscv-gnu-toolchain \
        /src/riscv-gnu-toolchain \
 && mkdir /src/riscv-gnu-toolchain/build \
 && cd /src/riscv-gnu-toolchain/build \
 && ../configure --prefix=/tools/riscv --enable-multilib \
 && make -j${JOBS} \
 && cd / \
 && rm -rf /src

ENV PATH="/tools/riscv/bin:${PATH}"

# Fail here, not two stages later, if multilib did not give what the course
# needs.
RUN riscv64-unknown-elf-gcc -print-multi-lib | grep -q '^rv32im/ilp32;' \
 && riscv64-unknown-elf-gcc -print-multi-lib | grep -q '^rv64imac/lp64;'

# The x86 programs of the toolchain (the compiler proper, the linker, GDB)
# are built with debug information, which makes them several times larger.
# Remove it. The RISC-V libraries are left as they are. This is its own RUN,
# after the long one, and it cannot fail the build.
RUN find /tools/riscv/bin /tools/riscv/libexec /tools/riscv/riscv64-unknown-elf/bin \
        -type f -exec strip --strip-unneeded {} + 2>/dev/null || true


# ---------------------------------------------------------------------------
# Stage: spike
# Spike is an x86 program built with the normal compiler. It does not need
# the RISC-V toolchain. Installs to /tools/spike. Takes minutes.
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS spike

ARG DEBIAN_FRONTEND=noninteractive

# A compiler, git, and the three packages from Spike's README.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        device-tree-compiler \
        git \
        libboost-regex-dev \
        libboost-system-dev \
 && rm -rf /var/lib/apt/lists/*

ARG SPIKE_COMMIT
ARG JOBS

# git clone --branch takes only tags and branches, so a commit is fetched
# by its full hash. Spike is built with debug information, which makes the
# install about 1.8 GB. Removing it with strip leaves under 100 MB.
RUN git init /src/spike \
 && cd /src/spike \
 && git remote add origin https://github.com/riscv-software-src/riscv-isa-sim \
 && git fetch --depth 1 origin ${SPIKE_COMMIT} \
 && git checkout FETCH_HEAD \
 && mkdir build \
 && cd build \
 && ../configure --prefix=/tools/spike \
 && make -j${JOBS} \
 && make install \
 && { find /tools/spike -type f \( -name '*.so' -o -name '*.a' -o -path '*/bin/*' \) \
        -exec strip --strip-debug {} + 2>/dev/null || true; } \
 && cd / \
 && rm -rf /src


# ---------------------------------------------------------------------------
# Stage: pk
# pk is RISC-V code, so it is built with the cross-compiler from the
# toolchain stage, once per word size. Installs to /tools/pk. Takes minutes.
# ---------------------------------------------------------------------------
FROM toolchain AS pk

ARG PK_COMMIT
ARG PK32_ARCH
ARG JOBS

# --host is the name prefix of the compiler that configure looks for. It is
# the same for both builds. The word size is chosen with --with-arch.
RUN git init /src/pk \
 && cd /src/pk \
 && git remote add origin https://github.com/riscv-software-src/riscv-pk \
 && git fetch --depth 1 origin ${PK_COMMIT} \
 && git checkout FETCH_HEAD \
 && mkdir build64 \
 && cd build64 \
 && ../configure --prefix=/tools/pk --host=riscv64-unknown-elf \
 && make -j${JOBS} \
 && make install \
 && mkdir ../build32 \
 && cd ../build32 \
 && ../configure --prefix=/tools/pk --host=riscv64-unknown-elf \
        --with-arch=${PK32_ARCH} \
 && make -j${JOBS} \
 && make install \
 && cd / \
 && rm -rf /src


# ---------------------------------------------------------------------------
# Stage: final
# The published image: a clean base, QEMU from apt, the run-time libraries
# the tools need, and the three install folders. No compilers for x86, no
# sources, no build folders.
# ---------------------------------------------------------------------------
FROM ${BASE_IMAGE} AS final

ARG DEBIAN_FRONTEND=noninteractive

# Why each package is here:
#   device-tree-compiler   Spike starts the dtc program at run time
#   libexpat1              GDB
#   libgmp10 libmpc3 libmpfr6 libzstd1
#                          the compiler proper (cc1) and GDB
#   libpython3.12t64       GDB is built with Python support
#   make                   the course Makefile runs in this container
#   qemu-system-misc       qemu-system-riscv32, qemu-system-riscv64
#   qemu-user              qemu-riscv32, qemu-riscv64
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        device-tree-compiler \
        libexpat1 \
        libgmp10 \
        libmpc3 \
        libmpfr6 \
        libpython3.12t64 \
        libzstd1 \
        make \
        qemu-system-misc \
        qemu-user \
 && rm -rf /var/lib/apt/lists/*

COPY --from=toolchain /tools/riscv /tools/riscv
COPY --from=spike     /tools/spike /tools/spike
COPY --from=pk        /tools/pk    /tools/pk

# ---------------------------------------------------------------------------
# Environment of the image. Scripts and Makefiles in the repo read these
# and do not define their own copies.
# ---------------------------------------------------------------------------
ARG RISCV_GNU_TOOLCHAIN_TAG
ARG SPIKE_COMMIT
ARG PK_COMMIT

# What the image was built from.
ENV RISCV_GNU_TOOLCHAIN_TAG=${RISCV_GNU_TOOLCHAIN_TAG} \
    SPIKE_COMMIT=${SPIKE_COMMIT} \
    PK_COMMIT=${PK_COMMIT}

# Tools on PATH, and the name prefix of the cross tools.
ENV PATH="/tools/riscv/bin:/tools/spike/bin:${PATH}" \
    CROSS_COMPILE=riscv64-unknown-elf-

# pk is RISC-V code and is handed to Spike as a file, so it is not on PATH.
ENV PK32=/tools/pk/riscv32-unknown-elf/bin/pk \
    PK64=/tools/pk/riscv64-unknown-elf/bin/pk

# The two configurations of the course: compiler flags, the multilib folder
# those flags select, and the --isa value for Spike. SPIKE32_ISA must cover
# the 32-bit pk and the program; rv64gc is what the 64-bit pk is built for.
ENV RV32_FLAGS="-march=rv32im -mabi=ilp32" \
    RV32_MULTILIB=rv32im/ilp32 \
    SPIKE32_ISA=rv32imac \
    RV64_FLAGS="-march=rv64imac -mabi=lp64" \
    RV64_MULTILIB=rv64imac/lp64 \
    SPIKE64_ISA=rv64gc

# Smoke test. A missing run-time library fails the build here and not in
# the middle of an exercise. It compiles a program, because gcc --version
# works even when the compiler proper cannot start.
RUN set -eu \
 && cd /tmp \
 && printf 'int main(void) { return 0; }\n' > smoke.c \
 && ${CROSS_COMPILE}gcc ${RV32_FLAGS} -o smoke32 smoke.c \
 && ${CROSS_COMPILE}gcc ${RV64_FLAGS} -o smoke64 smoke.c \
 && qemu-riscv32 smoke32 \
 && qemu-riscv64 smoke64 \
 && spike --isa=${SPIKE32_ISA} ${PK32} smoke32 \
 && spike --isa=${SPIKE64_ISA} ${PK64} smoke64 \
 && ${CROSS_COMPILE}gdb --version > /dev/null \
 && qemu-system-riscv32 --version > /dev/null \
 && qemu-system-riscv64 --version > /dev/null \
 && rm -f smoke.c smoke32 smoke64

LABEL org.opencontainers.image.source="https://github.com/rgantonio/compiler-study" \
      org.opencontainers.image.description="RISC-V GNU toolchain (multilib), QEMU, Spike and pk for the compiler-study course" \
      org.opencontainers.image.licenses="Apache-2.0"

# The repo is mounted here: docker run -v "$PWD":/work ...
WORKDIR /work

CMD ["bash"]
