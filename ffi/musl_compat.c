/*
 * Compatibility stub for static linking with musl.
 *
 * GCC 14's libgcc_eh.a references _dl_find_object, a glibc-only symbol
 * used for fast unwinder table lookup. When linking statically against
 * musl (which doesn't provide this symbol), we supply a stub that
 * returns "not found", causing libgcc_eh to fall back to its slow
 * dl_iterate_phdr-based path. This is safe — it only affects exception
 * unwinding performance, not correctness.
 *
 * On glibc systems the real _dl_find_object from libc takes precedence
 * over this weak definition.
 */

int _dl_find_object(void *address, void *result) __attribute__((weak));
int _dl_find_object(void *address, void *result) {
    (void)address;
    (void)result;
    return -1;
}
