# SPDX-License-Identifier: Apache-2.0
#
# Worked example 2: the same lz4 build as example 1, but download, build,
# install and clean up all happen in one RUN, so one layer.
# Files that are created and deleted inside the same RUN never reach the image.
#
# Build:  docker build -t ex2 .
# Run:    docker run --rm ex2

FROM ubuntu:24.04

ARG LZ4_VERSION=v1.10.0

# Stops apt from asking questions during the build. ARG, not ENV, so it
# is not set in the finished image.
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        build-essential git ca-certificates \
 # Shallow clone of one tag: no history, much less to download.
 && git clone --depth 1 --branch ${LZ4_VERSION} \
        https://github.com/lz4/lz4.git /tmp/lz4 \
 && make -C /tmp/lz4 -j"$(nproc)" \
 && make -C /tmp/lz4 install PREFIX=/opt/lz4 \
 # Clean up in the same RUN: sources, build tools, apt's package lists.
 && rm -rf /tmp/lz4 \
 && apt-get purge -y build-essential git \
 && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/lz4/bin:${PATH}"

WORKDIR /work
CMD ["lz4", "--version"]
