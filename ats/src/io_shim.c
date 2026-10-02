/* The one operating-system boundary: read a whole file into a caller-supplied
   buffer of fixed capacity. Returns the byte count, -1 if unreadable, -2 if the
   file does not fit. Everything after this call is checked ATS. */
#include <stdio.h>
long icarus_read_file(const char *path, char *buf, long cap) {
  FILE *f = fopen(path, "rb");
  if (!f) return -1;
  long n = (long)fread(buf, 1, (size_t)cap, f);
  int more = fgetc(f);
  fclose(f);
  return more != EOF ? -2 : n;
}
