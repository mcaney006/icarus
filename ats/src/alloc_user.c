#include <stdlib.h>

static long allocations = 0;

long icarus_alloc_calls(void) { return allocations; }

void *atsruntime_malloc_user(size_t size) {
  void *block = malloc(size);
  if (block == NULL && size != 0) abort();
  allocations++;
  return block;
}

void atsruntime_mfree_user(void *block) { free(block); }
