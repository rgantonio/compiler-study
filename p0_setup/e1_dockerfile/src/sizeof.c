// Simple printing of sizeof(long) and sizeof(void*)
#include <stdio.h>

int main() {
    printf("sizeof(long) = %zu\n", sizeof(long));
    printf("sizeof(void*) = %zu\n", sizeof(void*));
    return 0;
}