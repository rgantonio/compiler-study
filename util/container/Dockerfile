# SPDX-License-Identifier: Apache-2.0
# Author: rgantonio
# Git: rgantonio@github.com

# RISCV builder
FROM ubuntu:24.04 AS riscv-builder

# Installing packages first
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
&& apt-get install -y \
autoconf automake autotools-dev curl \
python3 python3-pip python3-tomli libmpc-dev \
libmpfr-dev libgmp-dev gawk build-essential bison \
flex texinfo gperf libtool patchutils bc zlib1g-dev \
libexpat-dev meson ninja-build git cmake libglib2.0-dev \
expect device-tree-compiler libslirp-dev libzstd-dev libncurses-dev

# RISCV GNU Installation
ARG RISCV_GNU_VER=2026.08.27

RUN git clone --depth 1 --branch $RISCV_GNU_VER https://github.com/riscv-collab/riscv-gnu-toolchain /riscv_src
WORKDIR /riscv_src/build
RUN ../configure --prefix=/tools/riscv --enable-multilib
RUN make -j8

# Spike builder
FROM ubuntu:24.04 AS spike-builder


# Installing packages first
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
&& apt-get install -y \
build-essential git ca-certificates \
device-tree-compiler libboost-regex-dev libboost-system-dev

# SPIKE Version
ARG SPIKE_COMMIT=609dbe0b9994154833039209fa37151e7c05e9d4

RUN git clone https://github.com/riscv-software-src/riscv-isa-sim /spike_src \
 && git -C /spike_src checkout ${SPIKE_COMMIT}

WORKDIR /spike_src/build

RUN ../configure --prefix=/tools/spike
RUN make -j8 && make install -j8

# pk builder
FROM riscv-builder AS pk-builder

ENV PATH="/tools/riscv/bin:$PATH"

# PK Version
ARG PK_COMMIT=9c61d29846d8521d9487a57739330f9682d5b542

RUN git clone https://github.com/riscv-software-src/riscv-pk /pk_src \
 && git -C /pk_src checkout ${PK_COMMIT}

WORKDIR /pk_src/build64 

RUN ../configure --prefix=/tools/pk --host=riscv64-unknown-elf \
 && make -j8 && make install -j8

WORKDIR /pk_src/build32

RUN ../configure --prefix=/tools/pk --host=riscv64-unknown-elf --with-arch=rv32imac_zicsr_zifencei \
 && make -j8 && make install -j8

# Final stage
FROM ubuntu:24.04 AS final

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends qemu-user qemu-system-misc \
 libexpat1 libgmp10 libmpc3 libmpfr6 libzstd1 libpython3.12t64 \
 device-tree-compiler make \
 && rm -rf /var/lib/apt/lists/*


COPY --from=spike-builder /tools/spike /tools/spike
COPY --from=riscv-builder /tools/riscv /tools/riscv
COPY --from=pk-builder /tools/pk /tools/pk

ENV PATH="/tools/riscv/bin:/tools/spike/bin:$PATH"
ENV PK64=/tools/pk/riscv64-unknown-elf/bin/pk
ENV PK32=/tools/pk/riscv32-unknown-elf/bin/pk