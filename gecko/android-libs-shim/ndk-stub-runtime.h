/* Route-B NDK stub runtime: shared between regenerate.sh's generated
 * ndk-stubs.c and the hand-written ndk-stub-runtime.c.
 *
 * A stub records itself and then either aborts (default) or returns zero
 * (ATL_NDK_STUB_SOFT), so one run can walk past several stubs and enumerate
 * more of the startup path instead of reporting exactly one symbol per run.
 */
#ifndef ATL_NDK_STUB_RUNTIME_H
#define ATL_NDK_STUB_RUNTIME_H

struct atl_ndk_stub {
  const char *name;
  unsigned long calls;
};

/* Defined by the generated ndk-stubs.c. */
extern struct atl_ndk_stub atl_ndk_stub_table[];
extern const unsigned atl_ndk_stub_count;

/* Records the call; aborts unless this symbol is soft. */
void atl_ndk_stub_hit(struct atl_ndk_stub *slot, void *ret_addr);

/* The stubs are all declared void(void) so that libxul needs no relink, so
 * soft mode's "return 0" has to be written by hand into the return registers:
 * integer and SSE both, because the real prototypes return pointers, ints,
 * floats and doubles and the stub does not know which.
 *
 * It has to be a tail call into asm, not inline asm in the stub: a stub that
 * calls the runtime gets a `pop %rax` epilogue, which would undo the zeroing.
 * Tail-calling means the epilogue runs *before* the registers are set.
 */
void atl_ndk_stub_zero_tail(void) __attribute__((visibility("hidden")));

#if (defined(__x86_64__) || defined(__aarch64__)) && \
    defined(__has_attribute) && __has_attribute(musttail)
#define ATL_NDK_STUB_TAIL_ZERO() \
  __attribute__((musttail)) return atl_ndk_stub_zero_tail()
#else
/* No way to guarantee the return registers here; soft mode returns garbage. */
#define ATL_NDK_STUB_TAIL_ZERO() atl_ndk_stub_zero_tail()
#endif

#define ATL_NDK_STUB_BODY(idx)                                           \
  atl_ndk_stub_hit(&atl_ndk_stub_table[idx], __builtin_return_address(0)); \
  ATL_NDK_STUB_TAIL_ZERO()

#endif /* ATL_NDK_STUB_RUNTIME_H */
