#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Check that the toolchain image does what the course needs.
# It follows the test plan in section 8 of the exercise sheet.
#
# Run it inside the image, from the top folder of the repo:
#
#   docker run --rm -v "$PWD":/work compiler-study:dev \
#       bash p0_setup/e1_dockerfile/test/check_docker.sh
#
# All settings (flags, multilib folders, pk files, Spike --isa values) come
# from the environment of the image, which is set in one place:
# util/container/Dockerfile. This script defines none of them itself.

# ---------------------------------------------------------------------------
# Settings from the image
# ---------------------------------------------------------------------------
missing=0
for name in CROSS_COMPILE PK32 PK64 \
            RV32_FLAGS RV32_MULTILIB SPIKE32_ISA \
            RV64_FLAGS RV64_MULTILIB SPIKE64_ISA; do
    if [ -z "${!name}" ]; then          # ${!name} is the value of the variable called $name
        echo "ERROR: $name is not set"
        missing=1
    fi
done
if [ "$missing" -ne 0 ]; then
    echo "Run this script inside the toolchain image, see the top of the file."
    exit 2
fi

GCC="${CROSS_COMPILE}gcc"
READELF="${CROSS_COMPILE}readelf"

# ---------------------------------------------------------------------------
# Files of this exercise
# ---------------------------------------------------------------------------
here=$(cd "$(dirname "$0")" && pwd)      # the folder this script is in
src="$here/../src"

HELLO_C="$src/hello.c"                   # prints one line, returns 0
EXIT7_C="$src/exit7.c"                   # returns 7
EXPECTED_LINE="Hello, world!"            # the exact line hello.c prints

tmp=$(mktemp -d)                         # compiled files go here, not in src/
trap 'rm -rf "$tmp"' EXIT                # remove it when the script ends

fails=0                                  # how many checks failed so far

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# check ID "description" command...
# Runs the command. PASS if its exit code is 0, FAIL otherwise.
check() {
    id="$1"
    desc="$2"
    shift 2                              # "$@" is now the command
    if "$@" > /dev/null 2>&1; then
        echo "$id PASS $desc"
    else
        echo "$id FAIL $desc"
        fails=$((fails + 1))
    fi
}

# check_run ID "description" EXPECTED_EXIT_CODE "EXPECTED_TEXT" command...
# Runs the command. PASS if the exit code matches and, when EXPECTED_TEXT is
# not empty, the output contains that text.
check_run() {
    id="$1"
    desc="$2"
    want_code="$3"
    want_text="$4"
    shift 4
    out=$("$@" 2>&1)
    code=$?
    ok=yes
    if [ "$code" -ne "$want_code" ]; then
        ok=no
    fi
    if [ -n "$want_text" ] && ! printf '%s\n' "$out" | grep -qF -- "$want_text"; then
        ok=no
    fi
    if [ "$ok" = yes ]; then
        echo "$id PASS $desc"
    else
        echo "$id FAIL $desc (exit code $code, wanted $want_code)"
        fails=$((fails + 1))
    fi
}

# info ID text...
# Prints a line for the log that is neither PASS nor FAIL.
info() {
    id="$1"
    shift
    echo "$id INFO $*"
}

# ---------------------------------------------------------------------------
# TC-01  GCC is on PATH and reports its version
# ---------------------------------------------------------------------------
check TC-01 "${GCC} runs" "$GCC" --version
info  TC-01 "$("$GCC" --version 2>&1 | head -n 1)"
info  TC-01 "toolchain release ${RISCV_GNU_TOOLCHAIN_TAG:-unknown}"

# ---------------------------------------------------------------------------
# TC-02  Assembler, linker, objdump, readelf and GDB are on PATH
# ---------------------------------------------------------------------------
for tool in as ld objdump readelf size gdb; do
    check "TC-02-$tool" "${CROSS_COMPILE}${tool} runs" \
        "${CROSS_COMPILE}${tool}" --version
done

# ---------------------------------------------------------------------------
# TC-03  QEMU user mode          TC-04  QEMU system mode
# ---------------------------------------------------------------------------
check TC-03-rv32 "qemu-riscv32 runs" qemu-riscv32 --version
check TC-03-rv64 "qemu-riscv64 runs" qemu-riscv64 --version
check TC-04-rv32 "qemu-system-riscv32 runs" qemu-system-riscv32 --version
check TC-04-rv64 "qemu-system-riscv64 runs" qemu-system-riscv64 --version
info  TC-03 "$(qemu-riscv32 --version 2>&1 | head -n 1)"

# ---------------------------------------------------------------------------
# TC-05  Spike is installed
# Spike without a program prints its usage text and returns exit code 1, so
# the exit code is not a good test here. The output is.
# ---------------------------------------------------------------------------
check TC-05 "spike starts and prints its usage text" \
    bash -c 'spike --help 2>&1 | grep -qi "usage"'
info  TC-05 "Spike commit ${SPIKE_COMMIT:-unknown}"

# ---------------------------------------------------------------------------
# TC-06  pk exists for each word size
# A missing file fails these too: readelf then prints no header.
# ---------------------------------------------------------------------------
check TC-06-rv32-class "pk for RV32 is an ELF32 file" \
    bash -c "$READELF -h '$PK32' | grep -q 'Class:.*ELF32'"
check TC-06-rv64-class "pk for RV64 is an ELF64 file" \
    bash -c "$READELF -h '$PK64' | grep -q 'Class:.*ELF64'"
check TC-06-rv32-machine "pk for RV32 is RISC-V code" \
    bash -c "$READELF -h '$PK32' | grep -q 'Machine:.*RISC-V'"
check TC-06-rv64-machine "pk for RV64 is RISC-V code" \
    bash -c "$READELF -h '$PK64' | grep -q 'Machine:.*RISC-V'"
info  TC-06 "pk commit ${PK_COMMIT:-unknown}"

# ---------------------------------------------------------------------------
# TC-07  Multilib list
# ---------------------------------------------------------------------------
check TC-07-rv32 "multilib list has $RV32_MULTILIB" \
    bash -c "$GCC -print-multi-lib | grep -q '^$RV32_MULTILIB;'"
check TC-07-rv64 "multilib list has $RV64_MULTILIB" \
    bash -c "$GCC -print-multi-lib | grep -q '^$RV64_MULTILIB;'"

# ---------------------------------------------------------------------------
# TC-08  GCC picks the right library set
# $RV32_FLAGS is used without quotes on purpose: it holds two flags.
# ---------------------------------------------------------------------------
check TC-08-rv32 "RV32 flags select $RV32_MULTILIB" \
    test "$($GCC $RV32_FLAGS -print-multi-directory 2>&1)" = "$RV32_MULTILIB"
check TC-08-rv64 "RV64 flags select $RV64_MULTILIB" \
    test "$($GCC $RV64_FLAGS -print-multi-directory 2>&1)" = "$RV64_MULTILIB"

# ---------------------------------------------------------------------------
# TC-09  Hello world compiles and links, and the ELF header is right
# ---------------------------------------------------------------------------
check TC-09-rv32-build "hello compiles for RV32" \
    $GCC $RV32_FLAGS -o "$tmp/hello32" "$HELLO_C"
check TC-09-rv64-build "hello compiles for RV64" \
    $GCC $RV64_FLAGS -o "$tmp/hello64" "$HELLO_C"
check TC-09-rv32-class "hello32 is ELF32" \
    bash -c "$READELF -h '$tmp/hello32' | grep -q 'Class:.*ELF32'"
check TC-09-rv64-class "hello64 is ELF64" \
    bash -c "$READELF -h '$tmp/hello64' | grep -q 'Class:.*ELF64'"
check TC-09-rv32-machine "hello32 is RISC-V" \
    bash -c "$READELF -h '$tmp/hello32' | grep -q 'Machine:.*RISC-V'"
check TC-09-rv64-machine "hello64 is RISC-V" \
    bash -c "$READELF -h '$tmp/hello64' | grep -q 'Machine:.*RISC-V'"

# ---------------------------------------------------------------------------
# TC-10  Hello world on QEMU user mode
# ---------------------------------------------------------------------------
check_run TC-10-rv32 "hello32 runs on qemu-riscv32" 0 "$EXPECTED_LINE" \
    qemu-riscv32 "$tmp/hello32"
check_run TC-10-rv64 "hello64 runs on qemu-riscv64" 0 "$EXPECTED_LINE" \
    qemu-riscv64 "$tmp/hello64"

# ---------------------------------------------------------------------------
# TC-11  Hello world on Spike with pk
# ---------------------------------------------------------------------------
check_run TC-11-rv32 "hello32 runs on Spike with pk" 0 "$EXPECTED_LINE" \
    spike --isa="$SPIKE32_ISA" "$PK32" "$tmp/hello32"
check_run TC-11-rv64 "hello64 runs on Spike with pk" 0 "$EXPECTED_LINE" \
    spike --isa="$SPIKE64_ISA" "$PK64" "$tmp/hello64"

# ---------------------------------------------------------------------------
# TC-12  Exit codes pass through the simulators
# A program that returns 7 proves the value comes from main. An exit code
# of 0 could also come from a simulator that ignores the program's result.
# ---------------------------------------------------------------------------
check TC-12-rv32-build "exit7 compiles for RV32" \
    $GCC $RV32_FLAGS -o "$tmp/exit7_32" "$EXIT7_C"
check TC-12-rv64-build "exit7 compiles for RV64" \
    $GCC $RV64_FLAGS -o "$tmp/exit7_64" "$EXIT7_C"
check_run TC-12-rv32-qemu "exit code 7 through qemu-riscv32" 7 "" \
    qemu-riscv32 "$tmp/exit7_32"
check_run TC-12-rv64-qemu "exit code 7 through qemu-riscv64" 7 "" \
    qemu-riscv64 "$tmp/exit7_64"
check_run TC-12-rv32-spike "exit code 7 through Spike (RV32)" 7 "" \
    spike --isa="$SPIKE32_ISA" "$PK32" "$tmp/exit7_32"
check_run TC-12-rv64-spike "exit code 7 through Spike (RV64)" 7 "" \
    spike --isa="$SPIKE64_ISA" "$PK64" "$tmp/exit7_64"

# ---------------------------------------------------------------------------
# TC-13  Works as a normal user
# Not a check line: it depends on how the container was started. Start it
# with --user "$(id -u):$(id -g)" and this line shows a number other than 0.
# ---------------------------------------------------------------------------
info TC-13 "this run used user id $(id -u) (0 means root)"

# ---------------------------------------------------------------------------
# TC-14  No build leftovers in the image
# The builder stages keep their sources under /src and remove them.
# ---------------------------------------------------------------------------
check TC-14 "no source or build folders in the image" test ! -e /src

# ---------------------------------------------------------------------------
# TC-15  Pull on the second machine
# Not a check line: run this whole script on the image pulled from the
# registry on the other machine, and compare the digest by hand.
# ---------------------------------------------------------------------------

echo "$fails check(s) failed"
if [ "$fails" -ne 0 ]; then
    exit 1
fi
exit 0
