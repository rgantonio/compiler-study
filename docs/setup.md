# Setup

How to get the toolchain image of this course, start it, and rebuild it. The
image holds every tool the exercises use, so nothing else has to be
installed.

The short version, for a machine that already has Docker and git:

```
git clone https://github.com/rgantonio/compiler-study
cd compiler-study
docker pull ghcr.io/rgantonio/compiler-study:v1
docker run --rm -it --user "$(id -u):$(id -g)" -v "$PWD":/work ghcr.io/rgantonio/compiler-study:v1
```

The rest of this page explains each line and covers the cases where it does
not work as written.

## 1. What you need

| What | Notes |
|---|---|
| An x86-64 machine with Linux, or Windows with WSL2 | The image is built for x86-64 only. |
| Docker | Docker Engine, or Docker Desktop with WSL integration. Section 6 has the commands for Podman and Apptainer. |
| git | To clone this repo. The exercises and the check script are in the repo, not in the image. |
| About 1.5 GB of free disk | The image takes 1.13 GB once it is unpacked. |

You do not need a GitHub account or a login. The image is public.

## 2. Pull the image

```
docker pull ghcr.io/rgantonio/compiler-study:v1
```

`ghcr.io` is the GitHub Container Registry, `rgantonio/compiler-study` is
the image, and `v1` is the tag. Tags of this image are version numbers. A
tag is pushed once and never changed, so `v1` is the same image today and
next year. There is no `latest` tag, so the tag cannot be left out.

To be sure you have the published image, compare its digest with the one in
the version history in section 8. A digest is a checksum of the image as the
registry stores it.

```
docker inspect --format '{{index .RepoDigests 0}}' ghcr.io/rgantonio/compiler-study:v1
```

## 3. Start the image with the repo mounted

Run this from the top folder of the repo:

```
docker run --rm -it --user "$(id -u):$(id -g)" -v "$PWD":/work ghcr.io/rgantonio/compiler-study:v1
```

| Part | What it does |
|---|---|
| `--rm` | Removes the container when you leave it. Your files are in the repo, not in the container, so nothing is lost. |
| `-it` | Gives you an interactive shell. |
| `--user "$(id -u):$(id -g)"` | Runs the container as your own user and group. Without it you are root inside, and files you create in the repo belong to root outside. |
| `-v "$PWD":/work` | Mounts the current folder, the repo, at `/work` in the container. `/work` is also the folder the shell starts in. |

You get a `bash` prompt in `/work` with the cross tools, QEMU and Spike on
`PATH`. Type `exit` to leave. The variables the image sets, such as
`RV32_FLAGS` and `PK32`, are listed in the [README](../README.md).

With `--user` the prompt shows `I have no name!`, because your user number
has no name inside the image. That is harmless.

To check that the image works on your machine, run the check script. It
prints one line per test case and should end with `0 check(s) failed`.

```
docker run --rm --user "$(id -u):$(id -g)" -v "$PWD":/work ghcr.io/rgantonio/compiler-study:v1 \
    bash p0_setup/e1_dockerfile/test/check_docker.sh
```

## 4. Rebuild the image from scratch

You only need this to change the image or to see how it is made. The recipe
is [util/container/Dockerfile](../util/container/Dockerfile), and
[p0/e1](../p0_setup/e1_dockerfile/README.md) explains how it was written.

Build one stage at a time, from the top folder of the repo:

```
docker build --target spike     -t compiler-study:spike     -f util/container/Dockerfile util/container
docker build --target toolchain -t compiler-study:toolchain -f util/container/Dockerfile util/container
docker build --target final     -t compiler-study:dev       -f util/container/Dockerfile util/container
```

| Stage | Time | Notes |
|---|---|---|
| `spike` | Minutes | |
| `toolchain` | About 1 hour with 10 jobs, measured on the laptop in section 6. Longer with fewer jobs. | Needs about 20 GB of free disk while it builds. |
| `final` | Minutes | Also builds the `pk` stage, and ends with a smoke test. |

Things to know before the long build:

- **Jobs and memory.** The Dockerfile runs `make` with 10 parallel jobs.
  Compiling GCC needs about 2 GB of memory per job, so the default needs
  about 20 GB. On a smaller machine add `--build-arg JOBS=<n>` to all three
  commands, for example `JOBS=4` with 8 GB. Too many jobs for the memory
  gets the build killed partway.
- **Choose the value once.** Changing `JOBS` makes the build steps run
  again.
- **Keep a log.** Add `--progress=plain` and `2>&1 | tee build.log` to the
  toolchain command. The log shows how long each step took.
- **The cache.** Docker keeps each finished step, so a second build of an
  unchanged Dockerfile takes seconds. `docker builder prune` and
  `docker system prune` delete that cache, and the next build then takes the
  full time again.

The result is a local image called `compiler-study:dev`. Use that name in
place of `ghcr.io/rgantonio/compiler-study:v1` in the commands of section 3.

## 5. Pinned versions

These are the versions in `v1`. They are set with `ARG` at the top of the
Dockerfile, and this table is a copy for reading.

| What | Pinned to |
|---|---|
| Base image | `ubuntu:24.04` |
| RISC-V GNU toolchain (GCC, binutils, newlib, GDB) | Release `2026.08.27` of `riscv-collab/riscv-gnu-toolchain` |
| Spike | Commit `609dbe0b9994154833039209fa37151e7c05e9d4` of `riscv-software-src/riscv-isa-sim` |
| pk | Commit `9c61d29846d8521d9487a57739330f9682d5b542` of `riscv-software-src/riscv-pk` |
| QEMU | The apt packages `qemu-user` and `qemu-system-misc` of Ubuntu 24.04 (QEMU 8.2) |

Inside the image, `env | grep -E 'TAG|COMMIT'` prints what it was built
from, and `${CROSS_COMPILE}gcc --version` prints the GCC version.

## 6. Notes per machine

### Laptop: Windows with WSL2

- **Memory.** WSL2 gets half of the laptop's memory by default. That is
  enough to pull and run the image. For the rebuild in section 4 it may not
  be: check with `free -h`. To raise it, create
  `C:\Users\<your-name>\.wslconfig` on the Windows side:

  ```
  [wsl2]
  memory=20GB
  ```

  Then run `wsl --shutdown` in PowerShell and start WSL again. Set the value
  to what your laptop can spare, and choose `JOBS` to match, at about 2 GB
  per job. The image was built on this laptop with 10 jobs after the memory
  was raised.
- **The docker group.** To run `docker` without `sudo`, add your user to
  the `docker` group with `sudo usermod -aG docker $USER`, then restart WSL.
  Anyone in that group can in effect become root on the machine. On your
  own laptop that is fine.
- **Where the repo is.** Keep it in the Linux file system, under
  `/home/...`. Under `/mnt/c/...` file access is slow.
- **Line endings.** A file downloaded on the Windows side and copied into
  WSL can have Windows line endings, and `git apply` or `bash` then fail on
  it. `sed -i 's/\r$//' <file>` removes them. Files in the repo are kept
  with Linux line endings by `.gitattributes`.

### Shared server

- **Tool.** Docker 28.3.2, on x86-64. The commands in sections 2 and 3 work
  there unchanged.
- **The docker group.** The account must be in the `docker` group. If it is
  not, `docker` answers
  `permission denied while trying to connect to the Docker daemon socket`,
  and an administrator has to add you. Do not expect `sudo` on a shared
  machine.
- **Keep `--user`.** Other people use the server, and files owned by root
  in your home folder are hard to remove without `sudo`.
- **No build there.** The image is pulled, not rebuilt.

### Other container tools

The image was checked with Docker only. These are the matching commands for
the two other common tools, not yet tested with `v1`.

| Tool | Pull | Run the check script |
|---|---|---|
| Podman | `podman pull ghcr.io/rgantonio/compiler-study:v1` | `podman run --rm -v "$PWD":/work ghcr.io/rgantonio/compiler-study:v1 bash p0_setup/e1_dockerfile/test/check_docker.sh` |
| Apptainer | `apptainer pull compiler-study_v1.sif docker://ghcr.io/rgantonio/compiler-study:v1` | `apptainer exec --bind "$PWD":/work --pwd /work compiler-study_v1.sif bash p0_setup/e1_dockerfile/test/check_docker.sh` |

Rootless Podman needs no `--user`: root inside the container is your own
user outside. Apptainer always runs as your own user with a read-only
image. The image was checked under those two conditions with Docker, see
section 7.

## 7. How the image was checked

The check script is
[p0_setup/e1_dockerfile/test/check_docker.sh](../p0_setup/e1_dockerfile/test/check_docker.sh).
It follows the test plan in section 8 of the
[p0/e1 sheet](../p0_setup/e1_dockerfile/README.md). Two test cases of that
plan are about how the script is started, and this is how they were run for
`v1` on 2026-10-06.

| Test case | Where | How | Result |
|---|---|---|---|
| TC-13, works as a normal user | Laptop, WSL2 | The check command in section 3, on the local build | User ID 1000, 0 checks failed |
| TC-13, with a read-only image | Laptop, WSL2 | The same, with `--read-only --tmpfs /tmp:exec` added | 0 checks failed |
| TC-15, pull on the second machine | Shared server, Docker 28.3.2 | Fresh clone, `docker pull`, then the check command in section 3 | 0 checks failed, and the digest matches the pushed one |

## 8. Version history

| Tag | Date | Repo commit | Digest | Changes |
|---|---|---|---|---|
| `v1` | 2026-10-06 | `8d23fa6` | `sha256:48089cd722f1286cadb02c738725df2d79a966faf895387091899e4039ce587c` | First published version. Versions as in section 5. |

Rules:

- A tag is pushed once. A change to the image gets the next number.
- The README and this page name the exact tag that the exercises use.
- The repo commit is the one the image was built from, so each version can
  be traced back to its Dockerfile.

### Publishing a new version

1. Commit the Dockerfile change, rebuild (section 4), and run the check
   script on `compiler-study:dev` as in section 7.
2. Create a GitHub personal access token (classic) with the scope
   `write:packages`, at
   `https://github.com/settings/tokens/new?scopes=write:packages`. Log in
   with `docker login ghcr.io -u rgantonio` and paste the token as the
   password.
3. Tag and push, with the next number in place of `N`:

   ```
   docker tag compiler-study:dev ghcr.io/rgantonio/compiler-study:vN
   docker push ghcr.io/rgantonio/compiler-study:vN
   ```

   The last line of the push shows the digest.
4. Run `docker logout ghcr.io`, so the token does not stay on the machine.
5. Pull the new tag on the second machine, run the check script, and
   compare the digest.
6. Add a row to the table above, and update the tag in the README, in
   sections 2 and 3 of this page, and in section 5 if a pinned version
   changed.

The package is already public and linked to this repo. Both settings belong
to the package, so new tags get them too.
