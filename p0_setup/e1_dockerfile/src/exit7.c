// SPDX-License-Identifier: Apache-2.0
//
// Returns 7 from main. Used to check that an exit code travels from the
// program through the simulator to the shell.

#include <stdio.h>

int main(void) {
    printf("Exiting with code 7\n");
    return 7;
}
