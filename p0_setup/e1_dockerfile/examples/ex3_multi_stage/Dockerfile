# SPDX-License-Identifier: Apache-2.0
#
# Worked example 3: a multi-stage build.
# The tool is htop, a process viewer. It uses autotools (configure + make).
# It is built here with hwloc support, so it needs the hwloc library both
# to build and to run.
#
# Stage "builder" has the compilers and the source tree.
# Stage "runtime" starts again from a clean base and copies in only the
# installed files. Nothing else from "builder" reaches the final image.
#
# Build everything:       docker build -t ex3 .
# Build one stage only:   docker build --target builder -t ex3-builder .
# Run:                    docker run --rm ex3

# ---------------------------------------------------------------- builder
FROM ubuntu:24.04 AS builder

ARG HTOP_VERSION=3.5.3
ARG DEBIAN_FRONTEND=noninteractive

# Build dependencies. Note the "-dev" packages: they hold the headers
# that the compiler needs. This layer changes rarely, so it comes first
# and stays in the build cache.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        build-essential autoconf automake pkg-config \
        git ca-certificates libncurses-dev libhwloc-dev \
 && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch ${HTOP_VERSION} \
        https://github.com/htop-dev/htop.git /src/htop

WORKDIR /src/htop

# Install under one prefix, so the next stage has one folder to copy.
RUN ./autogen.sh \
 && ./configure --prefix=/opt/htop --enable-hwloc \
 && make -j"$(nproc)" \
 && make install

# ---------------------------------------------------------------- runtime
FROM ubuntu:24.04 AS runtime

ARG DEBIAN_FRONTEND=noninteractive

# Run-time dependencies only: the shared library, not the "-dev" package.
# Find them by running `ldd /opt/htop/bin/htop` in the builder stage.
# The ncurses library is already part of the base image; hwloc is not.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libhwloc15 \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/htop /opt/htop

ENV PATH="/opt/htop/bin:${PATH}"

# Smoke test: if a shared library is missing, the build fails here
# instead of the first time someone runs the image.
RUN htop --version

# The ubuntu:24.04 image ships a normal user called "ubuntu" (UID 1000).
# Everything after this line, and every container, runs as that user.
USER ubuntu
WORKDIR /work

CMD ["htop", "--version"]
