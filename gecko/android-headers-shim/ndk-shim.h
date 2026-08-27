/* Route B: make the NDK headers usable on a glibc target.
 *
 * The android and media NDK headers hide most of their declarations
 * behind `#if __ANDROID_API__ >= N` and tag them with __INTRODUCED_IN(), both
 * of which come from bionic's <sys/cdefs.h>.  glibc has neither, so without
 * this prologue every NDK entry point is invisible and every call site fails
 * with "use of undeclared identifier".
 *
 * Defining these here rather than on the compiler command line keeps them
 * scoped to the shim headers: third-party code that tests __ANDROID_API__ for
 * its own reasons (abseil, angle, breakpad, skia) still sees it undefined.
 *
 * The wrappers also restore default visibility around the real headers.  Gecko
 * builds with -fvisibility=hidden and normally undoes that for system headers
 * through dist/system_wrappers, which these bypass; without it every NDK entry
 * point is declared hidden and cannot be resolved from a shared library.
 */

#ifndef ATL_NDK_SHIM_H
#define ATL_NDK_SHIM_H

/* Several NDK headers use the fixed-width types without including them. */
#include <stdint.h>
#include <sys/types.h>

#define ATL_NDK_VISIBILITY_PUSH _Pragma("GCC visibility push(default)")
#define ATL_NDK_VISIBILITY_POP _Pragma("GCC visibility pop")

/* API level the ATL android-headers tree was taken from. */
#ifndef __ANDROID_API__
#  define __ANDROID_API__ 30
#endif

#ifndef __ANDROID_API_FUTURE__
#  define __ANDROID_API_FUTURE__ 10000
#endif

#ifndef __ANDROID_API_G__
#  define __ANDROID_API_G__ 9
#endif
#ifndef __ANDROID_API_I__
#  define __ANDROID_API_I__ 14
#endif
#ifndef __ANDROID_API_J__
#  define __ANDROID_API_J__ 16
#endif
#ifndef __ANDROID_API_J_MR1__
#  define __ANDROID_API_J_MR1__ 17
#endif
#ifndef __ANDROID_API_J_MR2__
#  define __ANDROID_API_J_MR2__ 18
#endif
#ifndef __ANDROID_API_K__
#  define __ANDROID_API_K__ 19
#endif
#ifndef __ANDROID_API_L__
#  define __ANDROID_API_L__ 21
#endif
#ifndef __ANDROID_API_L_MR1__
#  define __ANDROID_API_L_MR1__ 22
#endif
#ifndef __ANDROID_API_M__
#  define __ANDROID_API_M__ 23
#endif
#ifndef __ANDROID_API_N__
#  define __ANDROID_API_N__ 24
#endif
#ifndef __ANDROID_API_N_MR1__
#  define __ANDROID_API_N_MR1__ 25
#endif
#ifndef __ANDROID_API_O__
#  define __ANDROID_API_O__ 26
#endif
#ifndef __ANDROID_API_O_MR1__
#  define __ANDROID_API_O_MR1__ 27
#endif
#ifndef __ANDROID_API_P__
#  define __ANDROID_API_P__ 28
#endif
#ifndef __ANDROID_API_Q__
#  define __ANDROID_API_Q__ 29
#endif
#ifndef __ANDROID_API_R__
#  define __ANDROID_API_R__ 30
#endif
#ifndef __ANDROID_API_S__
#  define __ANDROID_API_S__ 31
#endif
#ifndef __ANDROID_API_S_V2__
#  define __ANDROID_API_S_V2__ 32
#endif
#ifndef __ANDROID_API_T__
#  define __ANDROID_API_T__ 33
#endif
#ifndef __ANDROID_API_U__
#  define __ANDROID_API_U__ 34
#endif
#ifndef __ANDROID_API_V__
#  define __ANDROID_API_V__ 35
#endif

/* Availability attributes: meaningless without an android target triple. */
#ifndef __INTRODUCED_IN
#  define __INTRODUCED_IN(api_level)
#endif
#ifndef __INTRODUCED_IN_NO_GUARD_FOR_NDK
#  define __INTRODUCED_IN_NO_GUARD_FOR_NDK(api_level)
#endif
#ifndef __INTRODUCED_IN_32
#  define __INTRODUCED_IN_32(api_level)
#endif
#ifndef __INTRODUCED_IN_64
#  define __INTRODUCED_IN_64(api_level)
#endif
#ifndef __DEPRECATED_IN
#  define __DEPRECATED_IN(api_level)
#endif
#ifndef __REMOVED_IN
#  define __REMOVED_IN(api_level)
#endif
#ifndef __VERSIONER_NO_GUARD
#  define __VERSIONER_NO_GUARD
#endif
#ifndef __VERSIONER_FORTIFY_INLINE
#  define __VERSIONER_FORTIFY_INLINE
#endif

/* Nullability keywords are clang-only spellings; glibc headers never use them
 * but the NDK ones do, and they are accepted by clang regardless of target. */

#endif /* ATL_NDK_SHIM_H */
