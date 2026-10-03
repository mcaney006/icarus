/* The operating-system boundary: read a whole file into a caller-supplied
   buffer of fixed capacity (byte count, -1 if unreadable, -2 if the file does
   not fit), and a monotonic clock used only by the benchmark. Everything after
   these calls is checked ATS. */
#include <stdio.h>
#include <time.h>
long icarus_now_ns(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (long)t.tv_sec * 1000000000L + (long)t.tv_nsec;
}
long icarus_read_file(const char *path, char *buf, long cap) {
  FILE *f = fopen(path, "rb");
  if (!f) return -1;
  long n = (long)fread(buf, 1, (size_t)cap, f);
  int more = fgetc(f);
  fclose(f);
  return more != EOF ? -2 : n;
}
