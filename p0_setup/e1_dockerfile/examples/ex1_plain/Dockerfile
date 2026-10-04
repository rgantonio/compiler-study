# SPDX-License-Identifier: Apache-2.0
#
# Worked example 1: build one small tool from source, one step per line.
# The tool is lz4, a file compressor. It builds with plain `make`.
#
# This file works, but the image is bigger than it needs to be.
# Example 2 fixes that. Read the sheet before copying habits from here.
#
# Build:  docker build -t ex1 .
# Run:    docker run --rm ex1

FROM ubuntu:24.04

# A build-time variable. Override it with: --build-arg LZ4_VERSION=v1.9.4
ARG LZ4_VERSION=v1.10.0

# Each RUN line below becomes one layer of the image.
RUN apt-get update
RUN apt-get install -y build-essential git ca-certificates

RUN git clone https://github.com/lz4/lz4.git /tmp/lz4
WORKDIR /tmp/lz4
RUN git checkout ${LZ4_VERSION}

RUN make -j"$(nproc)"
RUN make install PREFIX=/opt/lz4

# This removes the source tree from the final file system, but the layers
# above still hold it. The image does not get smaller.
WORKDIR /
RUN rm -rf /tmp/lz4

# ENV values stay set in every container started from the image.
ENV PATH="/opt/lz4/bin:${PATH}"

WORKDIR /work
CMD ["lz4", "--version"]
