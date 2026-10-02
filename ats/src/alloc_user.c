/* Counting allocator behind ATS_MEMALLOC_USER. The simulator reads the count
   before and after the frame loop and requires them to be equal. */
#include <stdlib.h>
static long calls = 0;
static long frees = 0;
long icarus_alloc_calls(void) { return calls; }
long icarus_free_calls(void) { return frees; }
void *atsruntime_malloc_user(size_t n) { calls++; return malloc(n); }
void atsruntime_mfree_user(void *p) { frees++; free(p); }
