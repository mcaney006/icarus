#include <stdio.h>
#include <time.h>

long icarus_now_ns(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return (long)now.tv_sec * 1000000000L + (long)now.tv_nsec;
}

long icarus_read_file(const char *path, char *buffer, long capacity) {
  FILE *file = fopen(path, "rb");
  if (file == NULL) return -1;
  long size = (long)fread(buffer, 1, (size_t)capacity, file);
  int overflow = fgetc(file) != EOF;
  int failed = ferror(file);
  fclose(file);
  return failed ? -1 : overflow ? -2 : size;
}
