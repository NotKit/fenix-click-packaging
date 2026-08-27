/* Put libmozglue.so into the dynamic loader's global scope.
 *
 * A JNI library is dlopened RTLD_LOCAL, so when GeckoLoader.loadGeckoLibs
 * then dlopens libxul, libxul's 227 weak-undefined allocator symbols
 * (operator new via cxxalloc.h, moz_xmalloc, the jemalloc_* family) have
 * nothing to bind to and resolve to 0.  The first global constructor that
 * allocates - protobuf's - then calls address 0.
 *
 * glibc's dlopen promotes an already-loaded object from local to global when
 * asked with RTLD_GLOBAL, and RTLD_NOLOAD keeps it from loading anything new,
 * so one self-directed dlopen is the whole fix.  Linked into libmozglue.so so
 * it works whoever does the loading; no LD_PRELOAD, no change to libxul.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

static void atl_mozglue_go_global(void);

__attribute__((constructor(101))) static void atl_mozglue_go_global(void) {
  Dl_info di;
  if (!dladdr((void *)atl_mozglue_go_global, &di) || !di.dli_fname) {
    fprintf(stderr, "[mozglue-selfglobal] dladdr failed, not promoting\n");
    return;
  }
  void *h = dlopen(di.dli_fname, RTLD_NOLOAD | RTLD_GLOBAL | RTLD_LAZY);
  if (getenv("ATL_MOZGLUE_VERBOSE")) {
    fprintf(stderr, "[mozglue-selfglobal] %s -> %s\n", di.dli_fname,
            h ? "global" : dlerror());
    fflush(stderr);
  }
}
