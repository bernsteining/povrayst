/**
 * povray_plugin — Typst plugin for POV-Ray.
 */
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
// The build uses `-fvisibility=hidden` to give LTO maximum DCE freedom.
// Emscripten's own EMSCRIPTEN_KEEPALIVE is just `__attribute__((used))`
// — it keeps the symbol alive but doesn't force external visibility,
// so under hidden-by-default our wasm exports (`render`, `version`)
// would vanish. Override with both attributes so the host can bind them.
#undef EMSCRIPTEN_KEEPALIVE
#define EMSCRIPTEN_KEEPALIVE __attribute__((used, visibility("default")))
#else
#define EMSCRIPTEN_KEEPALIVE __attribute__((visibility("default")))
#endif

#include "base/version.h"
#include "vfe.h"
#include "vfeplatform.h"
using namespace vfe;
using namespace vfePlatform;

extern "C" {
    __attribute__((import_module("typst_env")))
    __attribute__((import_name("wasm_minimal_protocol_send_result_to_host")))
    void wasm_minimal_protocol_send_result_to_host(const char *ptr, int len);

    __attribute__((import_module("typst_env")))
    __attribute__((import_name("wasm_minimal_protocol_write_args_to_buffer")))
    void wasm_minimal_protocol_write_args_to_buffer(char *ptr);
}

static inline void send_str(const char *s) {
    wasm_minimal_protocol_send_result_to_host(s, std::strlen(s));
}

// With BOOST_NO_EXCEPTIONS, boost calls this instead of throw.
#include <exception>
namespace boost {
    void throw_exception(const std::exception&) {}
    void throw_exception(const std::exception&, const char*, const char*, int) {}
}

// Global scene buffer — set before render, read by the parser
// (via POVRAY_WASM_MEM_INPUT patch in parser_tokenizer.cpp).
// NOT extern "C" — both files are C++ so regular linkage works.
const unsigned char *povray_wasm_scene_buf = nullptr;
size_t povray_wasm_scene_size = 0;

// Re-entry guard for PumpMainThread (see patches/0001's pump heredoc).
int povray_wasm_pump_recursion = 0;

// Read in the failure-path error message: a unique tag per SetFailed call
// site (set by a re-injection in vfe.cpp), and the raw text of any parser
// fatal error captured from FatalError.
int povray_wasm_setfailed_site = 0;
std::string povray_wasm_parser_error_msg;
std::string povray_wasm_parser_error_file;
int povray_wasm_parser_error_line = 0;
int povray_wasm_parser_error_column = 0;

// Set true by FatalError. Read by Parser::Get_Token to force EOF on any
// tokenization that happens AFTER an error has been recorded — without
// this the parser can spin in nested loops that re-call Get_Token (because
// our -fno-exceptions build turned the unwinding throws into no-ops).
bool povray_wasm_parse_aborted = false;

// OpenLocalFile counters used in the failure-path error message to
// distinguish "render produced no PNG bytes" from "render never opened
// any image-output file at all".
extern "C" {
    int povray_wasm_openfile_write_count = 0;
    int povray_wasm_openfile_read_count = 0;
}

// Output capture: PNG bytes written by POV-Ray go into this growable buffer.
// Patched OStream + OpenLocalFile in fileinputoutput.cpp / platformbase.cpp
// route writes here when in WASM build.
//
// Shared sentinel byte: both platformbase.cpp (OpenLocalFile) and
// fileinputoutput.cpp (OStream::write/seekg/~OStream/flush) reference
// THIS SAME address so that the pointer comparison succeeds across
// translation units. Without this shared symbol, each TU would have
// its own static and the comparison would always fail.
extern "C" {
    char povray_wasm_output_sentinel_byte = 0;

    unsigned char *povray_wasm_output_buf = nullptr;
    size_t povray_wasm_output_size = 0;
    size_t povray_wasm_output_cap = 0;
    static long povray_wasm_output_cursor = 0;

    void povray_wasm_output_reset(void) {
        if (povray_wasm_output_buf) std::free(povray_wasm_output_buf);
        povray_wasm_output_buf = nullptr;
        povray_wasm_output_size = 0;
        povray_wasm_output_cap = 0;
        povray_wasm_output_cursor = 0;
    }

    void povray_wasm_output_write(const void *data, size_t n) {
        size_t needed = (size_t)povray_wasm_output_cursor + n;
        if (needed > povray_wasm_output_cap) {
            size_t new_cap = povray_wasm_output_cap ? povray_wasm_output_cap * 2 : 65536;
            while (new_cap < needed) new_cap *= 2;
            unsigned char *new_buf = (unsigned char *)std::realloc(povray_wasm_output_buf, new_cap);
            if (!new_buf) return; // out of memory
            povray_wasm_output_buf = new_buf;
            povray_wasm_output_cap = new_cap;
        }
        std::memcpy(povray_wasm_output_buf + povray_wasm_output_cursor, data, n);
        povray_wasm_output_cursor += n;
        if ((size_t)povray_wasm_output_cursor > povray_wasm_output_size)
            povray_wasm_output_size = povray_wasm_output_cursor;
    }

    int povray_wasm_output_seek(long pos, int whence) {
        long new_pos;
        switch (whence) {
            case 0: new_pos = pos; break;                                     // SEEK_SET
            case 1: new_pos = povray_wasm_output_cursor + pos; break;         // SEEK_CUR
            case 2: new_pos = (long)povray_wasm_output_size + pos; break;     // SEEK_END
            default: return -1;
        }
        if (new_pos < 0) return -1;
        povray_wasm_output_cursor = new_pos;
        return 0;
    }
}

// Declare PumpMainThread at global scope with C++ linkage so the symbol
// matches povray.cpp's definition (_Z14PumpMainThreadv mangled).
void PumpMainThread(void);

extern "C" EMSCRIPTEN_KEEPALIVE
int version() {
    send_str("POV-Ray " POV_RAY_FULL_VERSION " (Typst wasm plugin)");
    return 0;
}

// Parse newline-separated POV-Ray command strings (INI-style
// `Key=value` or command-line-style `+A0.1`) in place, handing each
// non-empty line to `AddCommand`. Null-terminates each line.
static void add_commands_from_buffer(vfeRenderOptions &opts,
                                     char *text, int len) {
    char *line = text;
    char *end = text + len;
    for (char *p = text; p < end; p++) {
        if (*p == '\n' || *p == '\r') {
            *p = '\0';
            if (*line) opts.AddCommand(line);
            line = p + 1;
        }
    }
    if (line < end && *line) opts.AddCommand(line);
}

// Emscripten reactor modules (--no-entry) export _initialize but don't
// set a wasm start section. Typst's instantiate_and_start only calls the
// start function — since there isn't one, _initialize never runs and
// C++ static constructors are skipped. Call __wasm_call_ctors (which is
// what _initialize delegates to) on first render to ensure ctors have run.
extern "C" void __wasm_call_ctors(void);
static bool _ctors_done = false;

// Multi-render support: each render() call tears down the transient
// state built up by the previous render (POV_FrontendAddress in
// particular — see MainThreadShutdown in povray.cpp) so that the next
// InitDirect re-registers cleanly. POVMS's inter-context reply loop
// also relies on POVMS_Sys_Timer() being coherent — our WASI-stub
// environment makes time() unreliable, so the timer macro is pinned
// to 0 (patches/0001-emscripten-source-fixes.patch.sh).
void MainThreadShutdown(void);

extern "C" EMSCRIPTEN_KEEPALIVE
int render(int scene_len, int options_len) {
    if (!_ctors_done) { __wasm_call_ctors(); _ctors_done = true; }

    // Fresh render: discard any captured bytes from a previous call.
    povray_wasm_output_reset();
    povray_wasm_parse_aborted = false;
    povray_wasm_parser_error_msg.clear();
    povray_wasm_parser_error_file.clear();
    povray_wasm_parser_error_line = 0;
    povray_wasm_parser_error_column = 0;
    povray_wasm_setfailed_site = 0;

    // Read scene + options from Typst args. +1 byte so we can null-
    // terminate the options segment and tokenize it in place.
    // Typst protocol: return 0 = success (bytes are PNG),
    //                  return 1 = error (bytes are UTF-8 message).
    //                  Any other code = "plugin did not respect the protocol".
    char *buf = (char *)std::malloc(scene_len + options_len + 1);
    if (!buf) { send_str("out of memory"); return 1; }
    wasm_minimal_protocol_write_args_to_buffer(buf);
    buf[scene_len + options_len] = '\0';

    // Scene at buf[0..scene_len], options at buf[scene_len..+options_len].
    povray_wasm_scene_buf = (const unsigned char *)buf;
    povray_wasm_scene_size = scene_len;

    auto *s = new vfeUnixSession(0);
    int err = s->InitDirect();
    if (err != 0) {
        char m[64]; std::snprintf(m, sizeof(m), "InitDirect failed (%d)", err);
        send_str(m); std::free(buf); return 1;
    }

    vfeRenderOptions opts;
    opts.AddCommand("+FN");
    opts.AddCommand("-D");
    opts.SetThreadCount(1);
    add_commands_from_buffer(opts, buf + scene_len, options_len);

    int setErr = s->SetOptions(opts);
    if (setErr != vfeNoError) {
        char m[64]; std::snprintf(m, sizeof(m), "SetOptions failed (%d)", setErr);
        send_str(m); std::free(buf); return 1;
    }

    int startErr = s->StartRender();
    if (startErr != vfeNoError) {
        char m[64]; std::snprintf(m, sizeof(m), "StartRender failed (%d)", startErr);
        send_str(m); std::free(buf); return 1;
    }

    // Drive the cooperative message loop until the session reports a
    // terminal state (Succeeded / Failed). The 100 M bound is a safety
    // net; a successful render typically finishes in a few thousand
    // iterations at most.
    int iterations = 0;
    for (iterations = 0; iterations < 100000000; iterations++) {
        PumpMainThread();
        s->RunIterationBody();
        if (s->Failed() || s->Succeeded()) break;
    }

    char msg[1024];
    int state = s->GetBackendState();
    if (s->Succeeded()) {
        if (povray_wasm_output_buf && povray_wasm_output_size > 0) {
            wasm_minimal_protocol_send_result_to_host(
                (const char *)povray_wasm_output_buf,
                (int)povray_wasm_output_size);
            std::free(buf);
            MainThreadShutdown();
            return 0;
        }
        // Render ticked over to Succeeded but no PNG bytes reached the
        // capture buffer — almost always means `OStream` → sentinel
        // routing regressed. Report something the caller can quote.
        std::snprintf(msg, sizeof(msg),
            "render succeeded but no output captured (size=%zu, "
            "openfile w=%d r=%d)",
            povray_wasm_output_size,
            povray_wasm_openfile_write_count,
            povray_wasm_openfile_read_count);
        send_str(msg);
        std::free(buf);
        MainThreadShutdown();
        return 1;
    }

    // Failure / exhaustion path — surface as much diagnostic text as fits.
    if (!povray_wasm_parser_error_msg.empty()) {
        // Strip POV-Ray's "Parse Error: " prefix — already implied by context.
        const char* m = povray_wasm_parser_error_msg.c_str();
        if (std::strncmp(m, "Parse Error: ", 13) == 0) m += 13;

        // Extract the offending line from the scene buffer for a gcc-style
        // caret display.
        char src_line[160] = "";
        char caret[160]    = "";
        int src_len = 0;
        if (povray_wasm_parser_error_line > 0 && buf) {
            int target = povray_wasm_parser_error_line, cur = 1, i = 0;
            while (cur < target && i < scene_len) {
                if (buf[i++] == '\n') ++cur;
            }
            int j = 0;
            while (i < scene_len && j < (int)sizeof(src_line) - 1
                   && buf[i] != '\n')
                src_line[j++] = buf[i++];
            src_line[j] = '\0';
            src_len = j;

            int col = povray_wasm_parser_error_column - 1;
            if (col < 0) col = 0;
            if (col > (int)sizeof(caret) - 2) col = (int)sizeof(caret) - 2;
            for (int k = 0; k < col && k < src_len; ++k)
                caret[k] = (src_line[k] == '\t') ? '\t' : ' ';
            caret[col] = '^';
            caret[col + 1] = '\0';
        }

        std::snprintf(msg, sizeof(msg),
            "%.80s:%d:%d: %.300s\n  %d | %.140s\n    | %.140s",
            povray_wasm_parser_error_file.empty()
                ? "<scene>" : povray_wasm_parser_error_file.c_str(),
            povray_wasm_parser_error_line,
            povray_wasm_parser_error_column,
            m,
            povray_wasm_parser_error_line,
            src_line,
            caret);
    } else {
        // Non-parse failure (render aborted, exhaustion, etc.) — fall back
        // to internal state for debugging.
        std::snprintf(msg, sizeof(msg),
            "render aborted (state=%d iter=%d failed=%d site=%d)",
            state, iterations, (int)s->Failed(),
            povray_wasm_setfailed_site);
    }
    send_str(msg);
    std::free(buf);
    MainThreadShutdown();
    return 1;
}
