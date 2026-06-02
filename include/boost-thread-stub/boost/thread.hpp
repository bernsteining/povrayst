// boost::thread stub for single-threaded wasm.
//
// Included by POV-Ray (and its deps) in place of the real boost::thread
// library. Semantics:
//   * boost::thread(F)        -> runs F synchronously in the ctor
//   * boost::thread::join()   -> no-op (the callable has already returned)
//   * boost::mutex            -> no-op (only one thread)
//   * boost::condition_variable::wait -> returns immediately
//
// This lets POV-Ray compile and link without the -pthread target feature
// flag, which is what generates the atomic ops that wasmi rejects.
//
// WARNING: POV-Ray's renderer was designed for truly-concurrent threads.
// If a code path dispatches work to a worker thread and then waits on
// a condition the worker is supposed to signal, this stub will deadlock:
// the worker already finished during the thread ctor, so the signal has
// already fired. Whether POV-Ray hits such a pattern is the topic of
// any remaining runtime patches (patches/0002+). For now this is
// enough to produce a loadable wasm for the smoke test.

#ifndef POVRAY_BOOST_THREAD_STUB_HPP
#define POVRAY_BOOST_THREAD_STUB_HPP

#include <cstddef>
#include <utility>
#include <chrono>
// Real boost/thread.hpp transitively pulls in a lot of stdlib headers.
// POV-Ray files rely on that — if we don't mirror it, sites that use
// std::map / std::set / std::ostringstream fail to find the full
// template definition.
#include <sstream>
#include <map>
#include <set>
#include <memory>
#include <string>
#include <boost/function.hpp>

namespace boost {

// ---- mutex primitives ---------------------------------------------------

struct defer_lock_t {};
struct try_to_lock_t {};
struct adopt_lock_t {};
inline defer_lock_t defer_lock = defer_lock_t();

class mutex {
public:
    mutex() = default;
    mutex(const mutex&) = delete;
    mutex& operator=(const mutex&) = delete;
    void lock()     {}
    void unlock()   {}
    bool try_lock() { return true; }

    // boost::mutex::scoped_lock is just a unique_lock<mutex>.
    class scoped_lock {
    public:
        explicit scoped_lock(mutex&)          {}
        scoped_lock(mutex&, defer_lock_t)     {}
        scoped_lock(mutex&, adopt_lock_t)     {}
        ~scoped_lock()                        = default;
        scoped_lock(const scoped_lock&)       = delete;
        scoped_lock& operator=(const scoped_lock&) = delete;
        void lock()     {}
        void unlock()   {}
        bool owns_lock() const { return true; }
    };

    class scoped_try_lock : public scoped_lock {
    public:
        using scoped_lock::scoped_lock;
    };
};

class recursive_mutex {
public:
    recursive_mutex() = default;
    recursive_mutex(const recursive_mutex&) = delete;
    recursive_mutex& operator=(const recursive_mutex&) = delete;
    void lock()     {}
    void unlock()   {}
    bool try_lock() { return true; }

    class scoped_lock {
    public:
        explicit scoped_lock(recursive_mutex&) {}
        ~scoped_lock() = default;
    };
};

template <class M>
class lock_guard {
public:
    explicit lock_guard(M&) {}
    ~lock_guard() = default;
    lock_guard(const lock_guard&) = delete;
};

template <class M>
class unique_lock {
public:
    unique_lock() = default;
    explicit unique_lock(M&) {}
    unique_lock(M&, defer_lock_t) {}
    unique_lock(M&, adopt_lock_t) {}
    ~unique_lock() = default;
    unique_lock(const unique_lock&) = delete;
    unique_lock(unique_lock&&) = default;
    void lock()     {}
    void unlock()   {}
    bool owns_lock() const { return true; }
};

// ---- condition variable -------------------------------------------------

class condition_variable {
public:
    condition_variable() = default;
    condition_variable(const condition_variable&) = delete;

    // Wait variants — single-threaded, so return immediately. Callers
    // typically loop (`while (!predicate) cv.wait(lk);`) which in a
    // single-threaded world means the predicate is whatever it is right
    // now.
    template <class Lock>
    void wait(Lock&) {}

    template <class Lock, class Pred>
    void wait(Lock&, Pred) {}

    template <class Lock, class Rep, class Period>
    bool timed_wait(Lock&, const std::chrono::duration<Rep, Period>&) { return true; }

    template <class Lock, class TimePoint>
    bool timed_wait(Lock&, const TimePoint&) { return true; }

    void notify_one() {}
    void notify_all() {}
};

// Legacy alias boost historically exposed.
using condition = condition_variable;

// ---- xtime (deprecated but referenced) ---------------------------------

struct xtime {
    long sec;
    long nsec;
};

enum xtime_clock_types { TIME_UTC_ = 1 };

inline int xtime_get(xtime* xt, int) {
    if (xt) { xt->sec = 0; xt->nsec = 0; }
    return TIME_UTC_;
}

// ---- thread -------------------------------------------------------------

class thread {
public:
    struct attributes {
        attributes() = default;
        void set_stack_size(std::size_t) {}
    };

    thread() = default;
    thread(const thread&) = delete;
    thread& operator=(const thread&) = delete;
    thread(thread&&) = default;

    // Core constructors: run the callable synchronously. The "thread"
    // is already done by the time the ctor returns.
    // __attribute__((noinline)) prevents LTO from inlining the callable
    // and then DCE-ing its body via noreturn throw paths.
    // volatile counter forces LTO to preserve the ctor call.
    static inline volatile int _thread_count = 0;

    template <class F>
    explicit thread(F&& f) { _thread_count++; f(); }

    template <class F>
    thread(const attributes&, F&& f) { _thread_count++; f(); }

    template <class F>
    thread(F&& f, std::size_t /*stacksize*/) { _thread_count++; f(); }

    ~thread() = default;

    void join()   {}
    void detach() {}
    bool joinable() const { return false; }

    void interrupt() {}
    bool interruption_requested() const { return false; }

    // Static helpers.
    static void yield() {}
    static void sleep(const xtime&) {}
};

// ---- thread_group -------------------------------------------------------
// POV-Ray's create_thread semantics: run F, return a pointer the caller
// will eventually delete. We run F inline (single-threaded), allocate a
// dummy `thread` so the returned pointer is non-null and delete-safe,
// and let the caller own the lifetime. No bookkeeping container needed.

class thread_group {
public:
    thread_group() = default;
    thread_group(const thread_group&) = delete;

    template <class F>
    thread* create_thread(F&& f) {
        f();
        return new thread();  // caller deletes
    }

    void add_thread(thread*)    {}
    void remove_thread(thread*) {}
    void join_all()             {}
};

// ---- this_thread --------------------------------------------------------

namespace this_thread {
    inline void yield() {}

    template <class Rep, class Period>
    inline void sleep_for(const std::chrono::duration<Rep, Period>&) {}

    inline void sleep(const xtime&) {}

    // Some POV-Ray sites pass posix_time durations; accept anything.
    template <class T>
    inline void sleep(const T&) {}
} // namespace this_thread

// ---- lock factories (boost::lock, boost::try_lock) ---------------------

template <class L1, class L2>
inline void lock(L1&, L2&) {}

template <class L1, class L2>
inline int try_lock(L1&, L2&) { return -1; }

} // namespace boost

#endif // POVRAY_BOOST_THREAD_STUB_HPP
