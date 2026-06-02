/*
 * cxa_stub.c — Override libc++abi's __cxa_throw (which is __attribute__((noreturn)))
 * with a version that RETURNS NORMALLY.
 *
 * Why this exists: LLVM's LTO pass sees __cxa_throw as noreturn → concludes
 * all code after any potentially-throwing C++ call is unreachable → DCEs
 * the entire body of every C++ function that calls into std::. Our stub
 * makes __cxa_throw return, so LTO sees it as a normal function and
 * preserves post-call code.
 *
 * Compiled as C (not C++) to avoid clashing with the C++ declaration in
 * <cxxabi.h> which carries __attribute__((noreturn)). At link time, our
 * .o definition takes precedence over the libc++abi.a weak symbol.
 *
 * At runtime: if an exception IS actually thrown, control returns from
 * __cxa_throw to the caller with undefined state. For POV-Ray's VFE
 * under wasmi this is acceptable: real exceptions (bad_alloc on small
 * strings) don't fire, and error-path exceptions are handled via POVMS
 * error codes, not C++ EH.
 */

void __cxa_throw(void *thrown_exception, void *tinfo, void (*dest)(void *))
{
    (void)thrown_exception;
    (void)tinfo;
    (void)dest;
    /* Intentionally empty — the throw becomes a no-op. */
}

void __cxa_rethrow(void)
{
    /* Intentionally empty. */
}


/*
 * Override operator new / operator new[] so LTO doesn't see the
 * libc++ bitcode's noreturn __throw_bad_alloc path. Our version
 * just calls malloc and aborts on failure (abort IS noreturn but
 * that's fine — it only fires on real OOM, not on the normal path).
 *
 * Without this, pre-built libc++ .a bitcode retains the old noreturn
 * annotations from before our header patches, causing LTO to DCE
 * all code after any basic_string allocation.
 */
#include <stdlib.h>

void *__attribute__((used))
operator_new_impl(unsigned long n)
{
    void *p = malloc(n);
    if (!p) abort();
    return p;
}

/* C++ name-mangled operator new(size_t) = _Znwm on wasm32 */
void *_Znwm(unsigned long n) __attribute__((alias("operator_new_impl")));
/* operator new[](size_t) = _Znam */
void *_Znam(unsigned long n) __attribute__((alias("operator_new_impl")));
/* nothrow variants */
void *_ZnwmRKSt9nothrow_t(unsigned long n, const void *nt)
{
    (void)nt;
    return malloc(n);
}
void *_ZnamRKSt9nothrow_t(unsigned long n, const void *nt)
{
    (void)nt;
    return malloc(n);
}
