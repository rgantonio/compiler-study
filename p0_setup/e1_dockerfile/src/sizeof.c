// SPDX-License-Identifier: Apache-2.0
//
// Prints the size of long and of a pointer. Used in section 9 of the sheet
// to compare RV32 (ILP32) with RV64 (LP64).

#include <stdio.h>

int main(void) {
    printf("sizeof(long) = %zu\n", sizeof(long));
    printf("sizeof(void*) = %zu\n", sizeof(void *));
    return 0;
}
