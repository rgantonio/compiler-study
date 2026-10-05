#!/usr/bin/env bash
# Run it with:  bash check_docker.sh

fails=0                                  # how many checks failed so far
here=$(cd "$(dirname "$0")" && pwd)      # the folder this script is in
src="$here/../src"

HELLO_C="$src/hello.c"                   # prints one line, returns 0
EXIT7_C="$src/exit7.c"                   # returns 7
EXPECTED_LINE="Hello, world!"            # the exact line hello.c prints

RV32_FLAGS="-march=rv32im -mabi=ilp32"
RV64_FLAGS="-march=rv64imac -mabi=lp64"
RV32_DIR="rv32im/ilp32"                  # multilib folder for RV32_FLAGS
RV64_DIR="rv64imac/lp64"                 # multilib folder for RV64_FLAGS
SPIKE32_ISA="rv32imac"                   # must cover pk32 and the program

GCC=riscv64-unknown-elf-gcc
READELF=riscv64-unknown-elf-readelf

tmp=$(mktemp -d)                         # compiled files go here, not in src/

# check ID "description" command...
# Runs the command. Prints PASS if its exit code is 0, FAIL otherwise.
check() {
    id="$1"
    desc="$2"
    shift 2                      # drop the first two arguments; "$@" is now the command
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


# 1. A tool is installed and runs.
check TC-01 "riscv64-unknown-elf-gcc is installed" riscv64-unknown-elf-gcc --version

# 2. Checking RISCV tools
check TC-02-assembler "riscv64-unknown-elf-as is installed" riscv64-unknown-elf-as --version
check TC-02-linker "riscv64-unknown-elf-ld is installed" riscv64-unknown-elf-ld --version
check TC-02-objdump "riscv64-unknown-elf-objdump is installed" riscv64-unknown-elf-objdump --version
check TC-02-readelf "riscv64-unknown-elf-readelf is installed" riscv64-unknown-elf-readelf --version
check TC-02-gdb "riscv64-unknown-elf-gdb is installed" riscv64-unknown-elf-gdb --version

# 3. Checking Qemu
check TC-03-qemu-riscv32 "qemu-riscv32 is installed" qemu-riscv32 --version
check TC-03-qemu-riscv64 "qemu-riscv64 is installed" qemu-riscv64 --version

# 4. Checking Qemu System mode
check TC-04-qemu-system-riscv32 "qemu-system-riscv32 is installed" qemu-system-riscv32 --version
check TC-04-qemu-system-riscv64 "qemu-system-riscv64 is installed" qemu-system-riscv64 --version

# 5. Checking Spike
check TC-05 "spike is installed and starts" \
    bash -c 'spike --help 2>&1 | grep -qi "usage"'

# 6. Checking pk ELF files
check TC-06-rv32 "pk for RV32 is an ELF32 file" \
    bash -c 'riscv64-unknown-elf-readelf -h "$PK32" | grep -q "Class:.*ELF32"'

check TC-06-rv64 "pk for RV64 is an ELF64 file" \
    bash -c 'riscv64-unknown-elf-readelf -h "$PK64" | grep -q "Class:.*ELF64"'


# 7. Multilib list
check TC-07-rv32 "multilib list has rv32im/ilp32" \
    bash -c "$GCC -print-multi-lib | grep -q '^rv32im/ilp32;'"
check TC-07-rv64 "multilib list has an RV64 entry" \
    bash -c "$GCC -print-multi-lib | grep -q '^rv64'"

# 8. GCC picks the right library set
check TC-08-rv32 "RV32 flags select $RV32_DIR" \
    test "$($GCC $RV32_FLAGS -print-multi-directory)" = "$RV32_DIR"
check TC-08-rv64 "RV64 flags select $RV64_DIR" \
    test "$($GCC $RV64_FLAGS -print-multi-directory)" = "$RV64_DIR"

# 9. Hello world compiles and links, and the ELF header is right
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

# 10. Hello world on QEMU user mode
check_run TC-10-rv32 "hello32 runs on qemu-riscv32" 0 "$EXPECTED_LINE" \
    qemu-riscv32 "$tmp/hello32"
check_run TC-10-rv64 "hello64 runs on qemu-riscv64" 0 "$EXPECTED_LINE" \
    qemu-riscv64 "$tmp/hello64"

# 11. Hello world on Spike with pk
check_run TC-11-rv32 "hello32 runs on Spike with pk" 0 "$EXPECTED_LINE" \
    spike --isa="$SPIKE32_ISA" "$PK32" "$tmp/hello32"
check_run TC-11-rv64 "hello64 runs on Spike with pk" 0 "$EXPECTED_LINE" \
    spike "$PK64" "$tmp/hello64"

# 12. Exit codes pass through the simulators
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
    spike "$PK64" "$tmp/exit7_64"

# 13. Not a test line: it depends on how the container was started.
echo "TC-13 INFO this run used user id $(id -u) (0 means root)"

# 14. No build leftovers in the image
check TC-14-riscv "no toolchain source folder" test ! -e /riscv_src
check TC-14-spike "no Spike source folder"     test ! -e /spike_src
check TC-14-pk    "no pk source folder"        test ! -e /pk_src

# 15. Not a test line: run this whole script on the image pulled on the
#     second machine and compare the digest by hand.

rm -rf "$tmp"

# Summary, and an exit code for whoever called this script.
echo "$fails check(s) failed"
if [ "$fails" -ne 0 ]; then
    exit 1
else
    exit 0
fi