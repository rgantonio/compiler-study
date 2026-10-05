#!/usr/bin/env bash
# Example: check that the normal (x86) build tools on this machine work.
# Run it with:  bash check_host.sh

fails=0     # how many checks failed so far

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

# 1. A tool is installed and runs.
check EX-01 "gcc is installed"  gcc --version
check EX-02 "make is installed" make --version

# 2. The output of a command contains a certain text.
#    "bash -c" lets us give a whole pipeline as one command.
check EX-03 "gcc reports an x86-64 target" \
    bash -c 'gcc -dumpmachine | grep -q x86_64'

# 3. Compile a program, run it, and compare its exit code with a number.
tmp=$(mktemp -d)                 # a new empty folder under /tmp
echo 'int main(void) { return 7; }' > "$tmp/seven.c"

check EX-04 "seven.c compiles" gcc -o "$tmp/seven" "$tmp/seven.c"

"$tmp/seven"                     # run it
code=$?                          # $? is the exit code of the last command
check EX-05 "seven returns 7 (got $code)" test "$code" -eq 7

rm -rf "$tmp"

# Summary, and an exit code for whoever called this script.
echo "$fails check(s) failed"
if [ "$fails" -ne 0 ]; then
    exit 1
fi

