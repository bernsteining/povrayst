# Implementation notes

Build instructions and a tour of the patches that make POV-Ray run
under wasmi. For end-user docs, see [`README.md`](README.md).

## Repository layout

```
povray/
├── Makefile                    Incremental build (fetch → patch → configure → compile → link → stub → opt)
├── patches/
│   ├── 0001-emscripten-source-fixes.patch.sh   ~1 800 lines of source patches (see below)
│   └── 0004-configure-cross-compile-fixes.patch.sh
├── scripts/
│   ├── build-deps.sh           Build zlib + libpng + boost to install/
│   ├── strip-pthread.sh        Remove -pthread from config.status post-configure
│   └── ...
├── src/
│   ├── povray_plugin.cpp       Plugin entry: version(), render(), output capture buffer
│   ├── wasm_stubs.cpp          pov_base::Delay (no-op) + Timer stubs
│   ├── cxa_stub.c              Non-noreturn __cxa_throw so LTO doesn't DCE post-throw code
│   ├── invoke_stubs.c          Local invoke_* shims (call_indirect) so Typst doesn't need env::invoke_*
│   └── vfs.c                   Minimal VFS helpers
├── include/
│   ├── no_exceptions.h         Empty — -include'd to suppress POV-Ray's EH macros
│   └── boost-thread-stub/      Single-threaded shim for boost::thread
├── pkg/
│   ├── povray.typ              Typst wrapper: render(), expand-includes(), option builder
│   ├── povray.wasm             The built artefact (~2 MB)
│   └── typst.toml              Package manifest
├── harness/
│   └── src/main.rs             wasmi 1.0.9 host — loads WASM, wires typst_env, invoke_*, runs exports
└── test/
    ├── documentation.typ       Cover, API reference, scene gallery, implementation notes
    └── examples/               .pov scenes + pre-rendered PNGs
```

## Building

### Requirements

| tool | version | notes |
|------|---------|-------|
| Emscripten (emcc/em++) | ≥ 3.1 | `emsdk install latest` |
| wasm-opt (Binaryen) | ≥ 116 | comes with emsdk or `apt install binaryen` |
| wasi-stub | ≥ 0.3 | `cargo install wasi-stub` |
| autoconf, automake, libtool | any | for POV-Ray's autotools |
| Python 3 | ≥ 3.8 | patch scripts use Python for brace-matching throw/try/catch stripping |
| Rust + cargo | stable | for the wasmi harness |
| Typst | ≥ 0.14.2 | for compiling `.typ` tests |

### One-shot build

```bash
git clone --recurse-submodules <this-repo>
cd povray

# If emsdk isn't on $PATH, point the Makefile at its env script:
export EMSDK_ENV=~/.local/share/emsdk/emsdk_env.sh

make -j$(nproc) wasm
# → pkg/povray.wasm (~2 MB)
```

This runs the full pipeline:

1. **deps** — build zlib, libpng, boost (thread/system/date_time/chrono) with emcc into `install/`
2. **fetch** — `git submodule update --init` checks out POV-Ray at the pinned commit
3. **patch** — run the idempotent shell-script patches
4. **prebuild** — `unix/prebuild.sh` → generates `configure`
5. **configure** — `emconfigure ./configure` with cross-compile cache overrides
6. **compile** — `emmake make` (incremental—only recompiles changed `.o`s)
7. **plugin** — compile `src/povray_plugin.cpp` + stubs
8. **link** — `em++` links everything into a standalone WASM
9. **wasi-stub** — stubs `wasi_snapshot_preview1` + leftover `env::*` imports
10. **wasm-opt** — aggressive whole-program optimisation (`-O3`, SIMD, bulk-memory, sign-ext, converge)

Editing `src/povray_plugin.cpp` only rebuilds the plugin `.o` + relinks (~seconds). Editing a POV-Ray source file triggers an incremental `emmake` of affected objects + relink.

### Testing with the harness

```bash
make harness   # builds harness/target/release/povray-harness
./harness/target/release/povray-harness pkg/povray.wasm --func version
./harness/target/release/povray-harness pkg/povray.wasm \
  --func render \
  --arg 'camera{location <0,2,-5> look_at 0} light_source{<4,6,-4> rgb 1.2} sphere{0,1 pigment{rgb <1,0.4,0.15>}}' \
  --arg 'Width=800
Height=600
Antialias=on
Antialias_Threshold=0.1' \
  --fuel 100000000000 \
  > output.png
```

### Installing locally for Typst

```bash
make install
# → copies pkg/* to ~/.local/share/typst/packages/local/povrayst/0.1.0/
```

## How it works — the hacks

POV-Ray was never designed for single-threaded, filesystem-less,
exception-free WebAssembly. Getting it there required five categories
of patches, all in
[`patches/0001-emscripten-source-fixes.patch.sh`](patches/0001-emscripten-source-fixes.patch.sh)
(~1 800 lines).

### 1. Exception elimination

POV-Ray and boost use `throw`/`try`/`catch` pervasively. Emscripten's
EH mechanism generates `invoke_*` indirect calls through a JS-provided
function table that doesn't exist under wasmi. We disable exceptions
entirely:

- **Compile flags**: `-fno-exceptions -sDISABLE_EXCEPTION_CATCHING=1`
- **Python brace-matcher**: walks ~75 `.cpp`/`.h` files, removes
  `try { ... } catch(...) { ... }` blocks (keeping the try body,
  discarding catch handlers), replaces `throw X;` with `(void)0;`
- **`throw()` specs → `noexcept`**: 10 occurrences in `pov_err.h`
  and `vfe.h`
- **`boost::throw_exception`**: stubbed in `povray_plugin.cpp` (boost
  calls this instead of `throw` under `BOOST_NO_EXCEPTIONS`)
- **`__cxa_throw` stub** (`src/cxa_stub.c`): a non-`noreturn`
  definition so LTO doesn't DCE code after potentially-throwing
  call sites
- **`invoke_*` shims** (`src/invoke_stubs.c`): local `call_indirect`
  implementations for every `invoke_*` signature emscripten emits, so
  the WASM module is self-contained—Typst's host provides only
  `typst_env::*`, not `env::invoke_*`

### 2. Single-threaded cooperative scheduling

POV-Ray uses `boost::thread` for separate parser, render, and control
threads. In WASM these don't exist. We:

- **Stub `boost::thread`** via `include/boost-thread-stub/` — a
  drop-in header tree where `thread::thread(f)` just stores `f` but
  never spawns
- **Patch `Scene::ParserControlThread` /
  `View::RenderControlThread`** to `return;` immediately (they
  normally `while(!stopRequested)` forever)
- **Patch `Scene::StartParser` / `View::StartRender`** to drain their
  task queues synchronously after dispatching the Done message:
  `while (parserTasks.Process()) {}`
- **`PumpMainThread()`** — one-shot message pump exposed from
  `povray.cpp`: calls `POVMS_ProcessMessages` once, with a re-entry
  guard to break the `POVMS_Send → PumpMainThread → handler →
  POVMS_Send` recursion cycle
- **`pov_base::Delay`** — no-op (pumping from Delay causes the same
  recursion)

The plugin's render loop is then just:

```cpp
for (int i = 0; i < 100000000; i++) {
    PumpMainThread();
    session->RunIterationBody();
    if (session->Failed() || session->Succeeded()) break;
}
```

### 3. `-fno-fast-math` override

POV-Ray's `configure.ac` unconditionally adds `-ffast-math`. This
tells the compiler infinities don't exist—but POV-Ray uses `HUGE_VAL`
(= +∞) as a sentinel for "value not set" in camera fields. With
`-ffast-math`, `New.Angle != HUGE_VAL` evaluates to `true` even when
`New.Angle` *is* `HUGE_VAL`, triggering spurious "viewing angle ≥ 180°"
errors on every scene with an explicit camera.

**Fix**: append `-fno-fast-math -fno-finite-math-only` to both
`CXXFLAGS` and `CFLAGS` so they override autotools' earlier
`-ffast-math`. Also removed `--fast-math` from `wasm-opt` flags.

### 4. Output capture (sentinel FILE*)

There's no filesystem. POV-Ray writes PNGs through `OStream`, which
wraps a `FILE*` from `PlatformBase::OpenLocalFile`. We patch:

- **`vfePlatformBase::OpenLocalFile`** (in `vfe/vfe.cpp`) — for write
  mode opening `.png`/`.bmp`/`.tga`/`.ppm`/`.jpg`/`.hdr`, returns a
  **shared sentinel pointer** (`&povray_wasm_output_sentinel_byte`)
  instead of calling `fopen`
- **`OStream::write`** — checks `f == sentinel`, routes to
  `povray_wasm_output_write()` (growable `realloc` buffer)
- **`OStream::seekg`** — checks sentinel, routes to
  `povray_wasm_output_seek()`
- **`OStream::flush`** / **`~OStream`** — check sentinel, no-op
  (don't `fflush`/`fclose` the fake pointer)

The sentinel byte is defined once in `povray_plugin.cpp` with
`extern "C"` linkage and referenced from three translation units
(`fileinputoutput.cpp`, `platformbase.cpp`, `vfe.cpp`). Pointer
comparison across TUs only works because it's the same global symbol.

After a successful render, the plugin sends the captured buffer to
Typst via `wasm_minimal_protocol_send_result_to_host`.

### 5. Miscellaneous platform fixes

- **`syspovconfig.h`**: add `__EMSCRIPTEN__` branch before the generic
  `__unix__` one (otherwise: hard `#error`)
- **`configbase.h`**: specialize `std::char_traits<unsigned short>` for
  libc++ (POV-Ray's `UCS2String = basic_string<unsigned short>` has no
  traits specialization under libc++)
- **`trace.cpp`**: `std::auto_ptr` → `std::unique_ptr` (removed in C++17)
- **`povms.c`**: skip `thread == GetCurrentThread()` assertion
  (`pthread_self` returns inconsistent values in single-threaded WASM);
  inject `PumpMainThread()` into the `POVMS_Send` wait loop
- **`parser_tokenizer.cpp`**: read scene from
  `povray_wasm_scene_buf` (a global `unsigned char*`) instead of
  `fopen`-ing the input file
- **`configure` cross-compile fixes**: `ax_check_lib` and
  `boost_thread` usability macros fail under
  `--host=wasm32-unknown-emscripten`; patched to set the success
  variables correctly
- **`-pthread` stripping**: post-configure removal of `-pthread` /
  `-lpthread` from `config.status` + `Makefile` regeneration, so
  clang doesn't emit `atomic.rmw.*` ops that wasmi rejects

## POV-Ray version

The submodule tracks **`master`** (`c3ce13e5`, Dec 2025) — 98
commits ahead of `release/v3.8.0` with parser crash fixes and
platform improvements. Patches support both branches via fallbacks
for text anchors that changed (`boost::thread` → `std::thread`,
`UCS2toASCIIString` → `UCS2toSysString`, `IMemTextStream` →
`IMemStream`, `boost::condition_variable` → `std::condition_variable`,
etc.).

The master switch required three additional fixes beyond the text
anchors:
1. **`std::thread` inline stubs** — master uses `std::thread` instead
   of `boost::thread` for all workers; our boost stub doesn't intercept
   those, so each `new std::thread(callable)` call is replaced with an
   inline `callable(); ptr = nullptr;` block.
2. **`std::condition_variable` waits** — `wait_for` / `wait` spin
   forever because our clock stub returns 0; the exact wait expressions
   are replaced with no-ops.
3. **`vfeUnixSession` constructor** — skips `UnixOptionsProcessor` and
   `Filesystem::SetTempFilePath` under `#ifndef POVRAY_WASM` (both
   require a real filesystem).
4. **`m_DisplayCreator` fix** — the throw-stripper occasionally
   comments out the `m_DisplayCreator = boost::bind(...)` assignment;
   the patch re-inserts it before `Reset()`.
