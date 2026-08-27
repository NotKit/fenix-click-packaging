/* Route B liblog.
 *
 * Off Android there is no liblog to link against.  ATL's ART build ships one,
 * but it needs a newer glibc than Gecko's bootstrap sysroot has, so linking it
 * directly fails on __isoc23_strtol.  Instead this forwards to whatever
 * __android_log_vprint is in the process at runtime -- which is ART's, once
 * ATL has loaded it -- and falls back to stderr.  It is the same trick ATL's
 * own api-impl-jni/util.c uses.
 */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

typedef int (*vprint_fn)(int prio, const char* tag, const char* fmt, va_list ap);

static const char* prio_name(int prio) {
  switch (prio) {
    case 2: return "V";
    case 3: return "D";
    case 4: return "I";
    case 5: return "W";
    case 6: return "E";
    case 7: return "F";
    default: return "?";
  }
}

static int fallback(int prio, const char* tag, const char* fmt, va_list ap) {
  fprintf(stderr, "%s/%s: ", prio_name(prio), tag ? tag : "");
  int n = vfprintf(stderr, fmt, ap);
  fputc('\n', stderr);
  return n;
}

int __android_log_vprint(int prio, const char* tag, const char* fmt,
                         va_list ap) {
  static vprint_fn real = NULL;
  static int looked_up = 0;
  if (!looked_up) {
    looked_up = 1;
    /* Our own definition is the one dlsym would find by name, so ask for the
     * next one in the lookup order. */
    real = (vprint_fn)dlsym(RTLD_NEXT, "__android_log_vprint");
  }
  if (real) {
    return real(prio, tag, fmt, ap);
  }
  return fallback(prio, tag, fmt, ap);
}

int __android_log_print(int prio, const char* tag, const char* fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int n = __android_log_vprint(prio, tag, fmt, ap);
  va_end(ap);
  return n;
}

int __android_log_write(int prio, const char* tag, const char* text) {
  return __android_log_print(prio, tag, "%s", text);
}

int __android_log_buf_write(int bufID, int prio, const char* tag,
                            const char* text) {
  (void)bufID;
  return __android_log_print(prio, tag, "%s", text);
}

int __android_log_buf_print(int bufID, int prio, const char* tag,
                            const char* fmt, ...) {
  (void)bufID;
  va_list ap;
  va_start(ap, fmt);
  int n = __android_log_vprint(prio, tag, fmt, ap);
  va_end(ap);
  return n;
}

void __android_log_assert(const char* cond, const char* tag, const char* fmt,
                          ...) {
  va_list ap;
  va_start(ap, fmt);
  if (fmt) {
    __android_log_vprint(7, tag, fmt, ap);
  } else {
    __android_log_print(7, tag, "assertion failed: %s", cond ? cond : "");
  }
  va_end(ap);
  abort();
}
