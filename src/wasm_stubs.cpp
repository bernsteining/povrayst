/*
 * wasm_stubs.cpp — Platform stubs for POV-Ray WASM plugin.
 *
 * Provides implementations for platform-dependent functions that
 * are either stubbed or need WASM-specific behavior:
 *   - pov_base::Delay: pumps the message loop instead of sleeping
 *   - pov_base::Timer: no-op timer (clock_time_get is stubbed)
 */

#include <cstddef>

// Forward-declare PumpMainThread (defined in povray.cpp, global scope)
extern void PumpMainThread(void);

// __resumeException: called when exception unwinding can't find a handler.
// Must NOT return (would cause infinite EH loop). Call abort() instead.
extern "C" void __resumeException(void *) {
    __builtin_trap();
}

// ---- pthread_cond_timedwait override for single-threaded WASM ---------------
// Emscripten's libc already stubs most pthread functions as no-ops. But
// pthread_cond_timedwait checks clock_gettime in a loop — and our WASI
// clock stub always returns 0, so the timeout never fires and timedwait
// spins forever. Override just this one function to return immediately
// (0 = "signalled, not timed-out" so callers don't enter timeout paths).
//
// We also override pthread_cond_wait which blocks unconditionally — in
// single-threaded WASM no other thread will ever signal, so just return.
#include <pthread.h>
#include <errno.h>
extern "C" {
    int __wrap_pthread_cond_timedwait(pthread_cond_t*, pthread_mutex_t*,
                                      const struct timespec*) { return 0; }
    int __wrap_pthread_cond_wait(pthread_cond_t*, pthread_mutex_t*) { return 0; }
}

namespace pov_base {

// Delay: called by Task::Cooperate() when paused. In single-threaded
// WASM, just no-op — pumping here would create recursion with the POVMS_Send
// wait loop (which already pumps PumpMainThread). The cooperative model
// is driven by the outer render loop, not by Delay.
void Delay(unsigned int msec)
{
    (void)msec;
}

// Timer stubs — WASI clock_time_get is stubbed, so timers always read 0.
class Timer {
public:
    Timer() {}
    ~Timer() {}
    void Reset() {}
    double ElapsedRealTime() const { return 0.0; }
    double ElapsedThreadCPUTime() const { return 0.0; }
    bool HasValidThreadCPUTime() const { return false; }
};

} // namespace pov_base
