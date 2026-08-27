/* Route-B NDK stub runtime.
 *
 * Every symbol in ndk-gap.txt is an NDK entry point nothing on this system
 * defines.  Pass 3 made them abort, which reports exactly one symbol per run.
 * This records the call instead -- to stderr and to an append-only log file --
 * so a single run enumerates the startup path.
 *
 * Environment:
 *   ATL_NDK_STUB_LOG=<path>   append-only trace file.  Default
 *                             ATL_NDK_STUB_DEFAULT_LOG (set at build time).
 *                             "-" or "" disables the file; stderr always gets
 *                             the lines.
 *   ATL_NDK_STUB_SOFT=1       return zero from every stub and keep going.
 *                             A comma-separated list instead of "1" makes only
 *                             the matching symbols soft ("AFont_,ATrace_").
 *   ATL_NDK_STUB_ABORT_ON=... comma-separated prefixes that abort even in soft
 *                             mode -- for the stubs where returning 0 is a lie.
 *   ATL_NDK_STUB_VERBOSE=1    log every call, not just the first per symbol.
 *   ATL_NDK_STUB_BACKTRACE=1  also dump up to 16 frames per logged call.
 *
 * Everything on the logging path is write(2) to a fd: the stubs can be reached
 * before main, from a library constructor, from any thread, and after exit.
 */
#define _GNU_SOURCE
#include <execinfo.h>
#include <fcntl.h>
#include <sched.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

#include "ndk-stub-runtime.h"

#ifndef ATL_NDK_STUB_DEFAULT_LOG
#define ATL_NDK_STUB_DEFAULT_LOG "/tmp/atl-ndk-stub-trace.log"
#endif

/* The soft-mode return value.  Tail-called from every stub, so the stub's own
 * epilogue has already run and nothing clobbers these afterwards. */
#if defined(__x86_64__)
__asm__(".text\n\t"
        ".globl atl_ndk_stub_zero_tail\n\t"
        ".hidden atl_ndk_stub_zero_tail\n\t"
        ".type atl_ndk_stub_zero_tail,@function\n"
        "atl_ndk_stub_zero_tail:\n\t"
        "xorq %rax, %rax\n\t"
        "xorq %rdx, %rdx\n\t"
        "pxor %xmm0, %xmm0\n\t"
        "pxor %xmm1, %xmm1\n\t"
        "ret\n\t"
        ".size atl_ndk_stub_zero_tail,.-atl_ndk_stub_zero_tail");
#elif defined(__aarch64__)
__asm__(".text\n\t"
        ".globl atl_ndk_stub_zero_tail\n\t"
        ".hidden atl_ndk_stub_zero_tail\n\t"
        ".type atl_ndk_stub_zero_tail,%function\n"
        "atl_ndk_stub_zero_tail:\n\t"
        "mov x0, xzr\n\t"
        "mov x1, xzr\n\t"
        "fmov d0, xzr\n\t"
        "fmov d1, xzr\n\t"
        "ret\n\t"
        ".size atl_ndk_stub_zero_tail,.-atl_ndk_stub_zero_tail");
#else
void atl_ndk_stub_zero_tail(void) { }
#endif

static int log_fd = -1;
static int soft_all;
static const char *soft_list;
static const char *abort_list;
static int verbose;
static int want_backtrace;

/* 0 = untouched, 1 = a thread is initialising, 2 = ready. */
static int init_state;

static void emit(const char *buf, unsigned len) {
  if (len == 0) return;
  /* Short writes on a pipe are possible; loop, but never block forever on
   * an error. */
  unsigned off = 0;
  while (off < len) {
    ssize_t n = write(2, buf + off, len - off);
    if (n <= 0) break;
    off += (unsigned)n;
  }
  if (log_fd >= 0) {
    off = 0;
    while (off < len) {
      ssize_t n = write(log_fd, buf + off, len - off);
      if (n <= 0) break;
      off += (unsigned)n;
    }
  }
}

static unsigned put_str(char *dst, unsigned cap, unsigned at, const char *s) {
  while (*s && at + 1 < cap) dst[at++] = *s++;
  return at;
}

static unsigned put_hex(char *dst, unsigned cap, unsigned at, unsigned long v) {
  static const char digits[] = "0123456789abcdef";
  char tmp[16];
  int n = 0;
  if (v == 0) tmp[n++] = '0';
  while (v && n < 16) {
    tmp[n++] = digits[v & 0xf];
    v >>= 4;
  }
  while (n-- > 0 && at + 1 < cap) dst[at++] = tmp[n];
  return at;
}

static unsigned put_dec(char *dst, unsigned cap, unsigned at, unsigned long v) {
  char tmp[24];
  int n = 0;
  if (v == 0) tmp[n++] = '0';
  while (v && n < 24) {
    tmp[n++] = (char)('0' + (v % 10));
    v /= 10;
  }
  while (n-- > 0 && at + 1 < cap) dst[at++] = tmp[n];
  return at;
}

/* Comma-separated prefix match.  "AFont_,ATrace_beginSection" matches every
 * AFont_* and that one ATrace entry point. */
static int list_matches(const char *list, const char *name) {
  if (!list || !*list) return 0;
  while (*list) {
    const char *end = strchr(list, ',');
    size_t len = end ? (size_t)(end - list) : strlen(list);
    if (len && strncmp(list, name, len) == 0) return 1;
    if (!end) break;
    list = end + 1;
  }
  return 0;
}

static void do_init(void) {
  const char *path = getenv("ATL_NDK_STUB_LOG");
  const char *s;

  if (!path) path = ATL_NDK_STUB_DEFAULT_LOG;
  if (*path && strcmp(path, "-") != 0)
    log_fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);

  s = getenv("ATL_NDK_STUB_SOFT");
  if (s && *s) {
    if (strcmp(s, "1") == 0 || strcmp(s, "all") == 0)
      soft_all = 1;
    else
      soft_list = s;
  }
  abort_list = getenv("ATL_NDK_STUB_ABORT_ON");
  s = getenv("ATL_NDK_STUB_VERBOSE");
  verbose = s && *s && strcmp(s, "0") != 0;
  s = getenv("ATL_NDK_STUB_BACKTRACE");
  want_backtrace = s && *s && strcmp(s, "0") != 0;

  {
    char buf[256];
    unsigned n = 0;
    n = put_str(buf, sizeof buf, n, "ATL-NDK-STUB start pid=");
    n = put_dec(buf, sizeof buf, n, (unsigned long)getpid());
    n = put_str(buf, sizeof buf, n, " mode=");
    n = put_str(buf, sizeof buf, n, soft_all ? "soft" : (soft_list ? "soft-list" : "hard"));
    n = put_str(buf, sizeof buf, n, " stubs=");
    n = put_dec(buf, sizeof buf, n, atl_ndk_stub_count);
    n = put_str(buf, sizeof buf, n, "\n");
    emit(buf, n);
  }
}

static void ensure_init(void) {
  int expected = 0;
  if (__atomic_load_n(&init_state, __ATOMIC_ACQUIRE) == 2) return;
  if (__atomic_compare_exchange_n(&init_state, &expected, 1, 0,
                                  __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
    do_init();
    __atomic_store_n(&init_state, 2, __ATOMIC_RELEASE);
    return;
  }
  while (__atomic_load_n(&init_state, __ATOMIC_ACQUIRE) != 2) sched_yield();
}

__attribute__((constructor(101))) static void atl_ndk_ctor(void) {
  ensure_init();
}

void atl_ndk_stub_hit(struct atl_ndk_stub *slot, void *ret_addr) {
  unsigned long calls;
  int soft;

  ensure_init();
  calls = __atomic_add_fetch(&slot->calls, 1, __ATOMIC_RELAXED);
  soft = soft_all || list_matches(soft_list, slot->name);
  if (list_matches(abort_list, slot->name)) soft = 0;

  if (calls == 1 || verbose) {
    char buf[320];
    unsigned n = 0;
    n = put_str(buf, sizeof buf, n, "ATL-NDK-STUB ");
    n = put_str(buf, sizeof buf, n, slot->name);
    n = put_str(buf, sizeof buf, n, " ret=0x");
    n = put_hex(buf, sizeof buf, n, (unsigned long)ret_addr);
    n = put_str(buf, sizeof buf, n, " tid=");
    n = put_dec(buf, sizeof buf, n, (unsigned long)syscall(SYS_gettid));
    n = put_str(buf, sizeof buf, n, " calls=");
    n = put_dec(buf, sizeof buf, n, calls);
    n = put_str(buf, sizeof buf, n, soft ? " soft\n" : " ABORT\n");
    emit(buf, n);

    if (want_backtrace) {
      void *frames[16];
      int depth = backtrace(frames, 16);
      /* backtrace_symbols_fd writes with write(2) and allocates nothing. */
      backtrace_symbols_fd(frames, depth, 2);
      if (log_fd >= 0) backtrace_symbols_fd(frames, depth, log_fd);
    }
  }

  if (!soft) abort();
}

/* One line per symbol that was reached, so a run that ends in a crash
 * elsewhere still leaves a usable census in the log. */
__attribute__((destructor)) static void atl_ndk_dtor(void) {
  unsigned i;
  unsigned long reached = 0;
  char buf[320];
  unsigned n;

  if (__atomic_load_n(&init_state, __ATOMIC_ACQUIRE) != 2) return;
  for (i = 0; i < atl_ndk_stub_count; i++) {
    unsigned long calls = __atomic_load_n(&atl_ndk_stub_table[i].calls,
                                          __ATOMIC_RELAXED);
    if (!calls) continue;
    reached++;
    n = 0;
    n = put_str(buf, sizeof buf, n, "ATL-NDK-STUB-SUMMARY ");
    n = put_str(buf, sizeof buf, n, atl_ndk_stub_table[i].name);
    n = put_str(buf, sizeof buf, n, " calls=");
    n = put_dec(buf, sizeof buf, n, calls);
    n = put_str(buf, sizeof buf, n, "\n");
    emit(buf, n);
  }
  n = 0;
  n = put_str(buf, sizeof buf, n, "ATL-NDK-STUB-SUMMARY total reached=");
  n = put_dec(buf, sizeof buf, n, reached);
  n = put_str(buf, sizeof buf, n, " of ");
  n = put_dec(buf, sizeof buf, n, atl_ndk_stub_count);
  n = put_str(buf, sizeof buf, n, " pid=");
  n = put_dec(buf, sizeof buf, n, (unsigned long)getpid());
  n = put_str(buf, sizeof buf, n, "\n");
  emit(buf, n);
}
