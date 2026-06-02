/*
 * invoke_stubs.c — local implementations of emscripten's `invoke_*` helpers.
 *
 * When compiled with -fexceptions, emscripten emits calls to functions like
 * `invoke_iiii(fp, a, b, c)` that wrap a potentially-throwing indirect call.
 * The host (JS or wasmi harness) is expected to provide them: run the callee
 * through the function table, catch any thrown exception, save it via
 * `setThrew`, and return the callee's result.
 *
 * Typst's wasmi host does NOT provide these. Without them, loading the
 * module fails with "cannot find definition for import env::invoke_iiii".
 * We're compiled with `-fno-exceptions + -sDISABLE_EXCEPTION_CATCHING=1`,
 * so the wrapping layer is unnecessary — a direct indirect call suffices.
 *
 * In WebAssembly, a function pointer IS the index into
 * __indirect_function_table, so casting the integer `fp` to a typed
 * function pointer and calling it compiles to a single `call_indirect`.
 * No setjmp/longjmp, no setThrew, no special runtime — just the call.
 *
 * These need to be visible by name at link time so the linker resolves
 * them locally instead of leaving them as env:* imports for the host.
 */

#include <stdint.h>

#define INVOKE_ATTR __attribute__((used, visibility("default")))

/* ---- return-int variants --------------------------------------------- */

INVOKE_ATTR int invoke_i(int fp) {
    int (*f)(void) = (int (*)(void))(uintptr_t)fp;
    return f();
}

INVOKE_ATTR int invoke_ii(int fp, int a) {
    int (*f)(int) = (int (*)(int))(uintptr_t)fp;
    return f(a);
}

INVOKE_ATTR int invoke_iii(int fp, int a, int b) {
    int (*f)(int, int) = (int (*)(int, int))(uintptr_t)fp;
    return f(a, b);
}

INVOKE_ATTR int invoke_iiii(int fp, int a, int b, int c) {
    int (*f)(int, int, int) = (int (*)(int, int, int))(uintptr_t)fp;
    return f(a, b, c);
}

INVOKE_ATTR int invoke_iiiii(int fp, int a, int b, int c, int d) {
    int (*f)(int, int, int, int) = (int (*)(int, int, int, int))(uintptr_t)fp;
    return f(a, b, c, d);
}

INVOKE_ATTR int invoke_iiiiii(int fp, int a, int b, int c, int d, int e) {
    int (*f)(int, int, int, int, int) =
        (int (*)(int, int, int, int, int))(uintptr_t)fp;
    return f(a, b, c, d, e);
}

INVOKE_ATTR int invoke_iiiiiii(int fp, int a, int b, int c, int d, int e, int g) {
    int (*f)(int, int, int, int, int, int) =
        (int (*)(int, int, int, int, int, int))(uintptr_t)fp;
    return f(a, b, c, d, e, g);
}

INVOKE_ATTR int invoke_iiiiiiii(int fp, int a, int b, int c, int d, int e,
                                 int g, int h) {
    int (*f)(int, int, int, int, int, int, int) =
        (int (*)(int, int, int, int, int, int, int))(uintptr_t)fp;
    return f(a, b, c, d, e, g, h);
}

INVOKE_ATTR int invoke_iiiiiiiii(int fp, int a, int b, int c, int d, int e,
                                  int g, int h, int i) {
    int (*f)(int, int, int, int, int, int, int, int) =
        (int (*)(int, int, int, int, int, int, int, int))(uintptr_t)fp;
    return f(a, b, c, d, e, g, h, i);
}

/* ---- return-void variants -------------------------------------------- */

INVOKE_ATTR void invoke_v(int fp) {
    void (*f)(void) = (void (*)(void))(uintptr_t)fp;
    f();
}

INVOKE_ATTR void invoke_vi(int fp, int a) {
    void (*f)(int) = (void (*)(int))(uintptr_t)fp;
    f(a);
}

INVOKE_ATTR void invoke_vii(int fp, int a, int b) {
    void (*f)(int, int) = (void (*)(int, int))(uintptr_t)fp;
    f(a, b);
}

INVOKE_ATTR void invoke_viii(int fp, int a, int b, int c) {
    void (*f)(int, int, int) = (void (*)(int, int, int))(uintptr_t)fp;
    f(a, b, c);
}

INVOKE_ATTR void invoke_viiii(int fp, int a, int b, int c, int d) {
    void (*f)(int, int, int, int) = (void (*)(int, int, int, int))(uintptr_t)fp;
    f(a, b, c, d);
}

INVOKE_ATTR void invoke_viiiii(int fp, int a, int b, int c, int d, int e) {
    void (*f)(int, int, int, int, int) =
        (void (*)(int, int, int, int, int))(uintptr_t)fp;
    f(a, b, c, d, e);
}

INVOKE_ATTR void invoke_viiiiii(int fp, int a, int b, int c, int d, int e, int g) {
    void (*f)(int, int, int, int, int, int) =
        (void (*)(int, int, int, int, int, int))(uintptr_t)fp;
    f(a, b, c, d, e, g);
}

INVOKE_ATTR void invoke_viiiiiii(int fp, int a, int b, int c, int d, int e,
                                  int g, int h) {
    void (*f)(int, int, int, int, int, int, int) =
        (void (*)(int, int, int, int, int, int, int))(uintptr_t)fp;
    f(a, b, c, d, e, g, h);
}

INVOKE_ATTR void invoke_viiiiiiii(int fp, int a, int b, int c, int d, int e,
                                   int g, int h, int i) {
    void (*f)(int, int, int, int, int, int, int, int) =
        (void (*)(int, int, int, int, int, int, int, int))(uintptr_t)fp;
    f(a, b, c, d, e, g, h, i);
}

INVOKE_ATTR void invoke_viiiiiiiii(int fp, int a, int b, int c, int d, int e,
                                    int g, int h, int i, int j) {
    void (*f)(int, int, int, int, int, int, int, int, int) =
        (void (*)(int, int, int, int, int, int, int, int, int))(uintptr_t)fp;
    f(a, b, c, d, e, g, h, i, j);
}

INVOKE_ATTR void invoke_viiiiiiiiii(int fp, int a, int b, int c, int d, int e,
                                     int g, int h, int i, int j, int k) {
    void (*f)(int, int, int, int, int, int, int, int, int, int) =
        (void (*)(int, int, int, int, int, int, int, int, int, int))(uintptr_t)fp;
    f(a, b, c, d, e, g, h, i, j, k);
}

INVOKE_ATTR void invoke_viiiiiiiiiii(int fp, int a, int b, int c, int d, int e,
                                      int g, int h, int i, int j, int k, int l) {
    void (*f)(int, int, int, int, int, int, int, int, int, int, int) =
        (void (*)(int, int, int, int, int, int, int, int, int, int, int))(uintptr_t)fp;
    f(a, b, c, d, e, g, h, i, j, k, l);
}

/* ---- mixed float/double variants ------------------------------------- */

INVOKE_ATTR float invoke_fi(int fp, int a) {
    float (*f)(int) = (float (*)(int))(uintptr_t)fp;
    return f(a);
}

INVOKE_ATTR void invoke_viid(int fp, int a, int b, double c) {
    void (*f)(int, int, double) = (void (*)(int, int, double))(uintptr_t)fp;
    f(a, b, c);
}

INVOKE_ATTR float invoke_fiii(int fp, int a, int b, int c) {
    float (*f)(int, int, int) = (float (*)(int, int, int))(uintptr_t)fp;
    return f(a, b, c);
}

INVOKE_ATTR int invoke_iififi(int fp, int a, float b, int c, float d, int e) {
    int (*f)(int, float, int, float, int) =
        (int (*)(int, float, int, float, int))(uintptr_t)fp;
    return f(a, b, c, d, e);
}
