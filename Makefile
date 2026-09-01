# POV-Ray -> WASM plugin for Typst (host build, incremental).
#
# Requirements on PATH:
#   emcc / em++ / emconfigure / emmake   (emsdk)
#   wasm-opt                              (binaryen)
#   wasi-stub                             (cargo install wasi-stub)
#   git, make, autoconf, automake, libtool, pkg-config
#
# Optional: set EMSDK_ENV to a path to `emsdk_env.sh` if emcc isn't on PATH.
#
# Incremental pipeline (each stage emits a stamp file; make rebuilds only
# the downstream of whatever changed):
#
#   scripts/build-deps.sh      ─► install/.deps-built          (deps)
#   (git)                      ─► povray-src/.git              (fetch)
#   patches/*.patch            ─► povray-src/.patched          (patch)
#   povray-src/.patched        ─► povray-src/configure         (prebuild)
#   povray-src/configure + deps─► povray-src/config.status     (configure)
#   povray-src/**.c{pp}        ─► povray-src/.compiled         (compile, emmake-incremental)
#   src/povray_plugin.cpp      ─► build/povray_plugin.o        (plugin compile)
#   plugin.o + compile stamp   ─► pkg/povray.wasm              (link + wasi-stub + wasm-opt)
#
# What this buys you:
#   - editing src/povray_plugin.cpp  -> only re-compiles plugin.o + relinks + post-processes (~seconds)
#   - editing a POV-Ray source file  -> emmake rebuilds affected .o, relinks
#   - adding a patch                 -> re-patch + re-configure + re-compile + re-link
#   - nothing changed                -> `make` is a no-op (fast mtime check)

SHELL           = /bin/bash
JOBS           ?= $(shell nproc)

POVRAY_DIR      = povray-src
# POV-Ray is a git submodule. The pinned commit lives in .gitmodules
# (currently release/v3.8.0 @ ca897313). To test against master:
#   cd povray-src && git checkout origin/master && cd ..
# then `make distclean && make wasm` and verify patches still apply.

PREFIX          = $(CURDIR)/install
BUILD_DIR       = $(CURDIR)/build
OUT             = pkg/povray.wasm

EMSDK_ENV      ?=
EMSDK_LOAD      = if [ -n "$(EMSDK_ENV)" ] && [ -f "$(EMSDK_ENV)" ]; then source "$(EMSDK_ENV)" >/dev/null; fi

# Optimization profile for the ray-tracer itself. Ray tracing is
# compute-bound number-crunching, so we favor execution speed over
# artifact size:
#   -O3           aggressive loop unrolling, inlining, vectorization
#   -flto         link-time optimization across every .o in POV-Ray
#                 + our plugin + boost + libpng + zlib. Emscripten's
#                 LTO links .o at the LLVM-IR level which lets it
#                 inline across library boundaries and drop dead code
#                 that plain -O3 can't reach.
#   -ffast-math   allow reassociation, no-signed-zero, etc. POV-Ray
#                 does a lot of vector math where these are safe.
#   -fno-math-errno          don't bother setting errno on libm calls
#   -fno-threadsafe-statics  drop atomic guards on local static init
#                            (safe in single-threaded wasmi, keeps us
#                            out of the exception-refcount atomics path)
# -flto is critical for correct operation: without it, emscripten's
# invoke_* stubs use indirect calls through the function table which
# isn't populated (uninitialized element trap). With LTO, invoke_*
# gets inlined away. To prevent LTO from DCE-ing post-throw code,
# we provide a non-noreturn __cxa_throw in src/cxa_stub.c.
# Selective LTO: -flto on POV-Ray sources for cross-TU inlining of
# template-heavy code (Vector3d, shared_ptr, etc.). Plugin + cxa_stub
# + the four VFE_NOLTO_OBJS are still compiled without -flto so their
# bodies survive DCE; LTO sees them as real .o leaves. _initialize
# populates the indirect function table so invoke_* trampolines work.
OPT             = -O3 -flto -fno-math-errno \
                  -fno-strict-aliasing -fno-threadsafe-statics -DNDEBUG \
                  -ffile-prefix-map=$(CURDIR)=povrayst

# Typst's wasmi supports the SIMD128 proposal. -msimd128 turns it on;
# -msseN/-mssseN enable Emscripten's header shims that map SSE
# intrinsics (used throughout POV-Ray vector math, and in libpng/zlib
# filter loops) onto wasm SIMD.
SIMD_FLAGS      = -msimd128 -msse -msse2 -msse3 -mssse3 -msse4.1 -msse4.2

# wasm-opt post-processing.
#
#   --enable-simd            preserve SIMD128 ops (we emit -msimd128)
#   --enable-bulk-memory     memory.copy / memory.fill (from memcpy LTO)
#   --enable-sign-ext        i32.extend8_s / i16_s (clang emits these)
#   --enable-nontrapping-float-to-int
#   --enable-mutable-globals / multivalue / threads
#     -> wasm proposals Typst's wasmi accepts.
#   --fast-math --closed-world --directize --inline-functions-with-loops
#     -> aggressive whole-program optimizations; fine for a standalone
#        plugin with a fixed import surface.
#   --converge                 keep iterating passes until fixed point.
#
# NOT included: --traps-never-happen. It lets wasm-opt DCE code after
# any potentially-trapping op, which eats legitimate calls to our
# typst_env imports whenever they happen to sit after a malloc/vector
# allocation. Saves <10K of binary and causes silent data loss. Skip.
#
# --enable-threads: atomics come in from libc++abi's exception-refcount
# code even with a single-threaded build. Typst's wasmi executes them
# as regular loads/stores, so we convince wasm-opt not to reject them.
WASM_OPT_FLAGS  = -O3 --gufa --enable-simd --enable-bulk-memory --enable-sign-ext \
                  --enable-nontrapping-float-to-int --enable-mutable-globals \
                  --enable-multivalue --enable-threads \
                  --disable-relaxed-simd \
                  --inline-functions-with-loops \
                  --converge

# Slimmed boost link list. Notes:
#   system    — needed for boost::system::error_code references.
#   date_time — used by parser_strings.cpp (SDL datetime() builtin) and
#               base/image/metadata.cpp (PNG metadata timestamp).
#   thread    — boost/thread.hpp is replaced wholesale by our header stub
#               (see build-deps.sh comment); the .a is inert. Dropped.
#   chrono    — POV-Ray uses std::chrono exclusively; boost::chrono is
#               unreferenced. Dropped.
BOOST_LIBS      = -lboost_system -lboost_date_time

# Local thread-stub header tree. Takes precedence over $(PREFIX)/include
# so that #include <boost/thread.hpp> resolves to our single-threaded
# shim instead of the real boost::thread headers (which require -pthread
# and emit atomic ops that wasmi rejects).
THREAD_STUB_INC = $(CURDIR)/include/boost-thread-stub

# Autoconf cache-variable overrides that short-circuit link tests
# against libraries we just built. Each check normally tries to link
# a tiny test program, which fails under emscripten due to K&R-style
# `char exit();` vs. wasi-libc's typed `exit(i32)`. We assert success
# explicitly.
CONFIGURE_CACHE_OVERRIDES = \
    ax_cv_boost_thread=yes \
    ac_cv_lib_boost_thread_exit=yes \
    ac_cv_lib_boost_system_exit=yes \
    ac_cv_lib_boost_date_time_exit=yes \
    ac_cv_lib_boost_chrono_exit=yes

# ---- Stamp files (real file targets) -------------------------------------

DEPS_STAMP      = $(PREFIX)/.deps-built
FETCH_STAMP     = $(POVRAY_DIR)/.git
PATCH_STAMP     = $(POVRAY_DIR)/.patched
PREBUILD_STAMP  = $(POVRAY_DIR)/configure
CONFIGURE_STAMP = $(POVRAY_DIR)/config.status
COMPILE_STAMP   = $(POVRAY_DIR)/.compiled
PLUGIN_OBJ      = $(BUILD_DIR)/povray_plugin.o

# All POV-Ray source files become prereqs of the compile stage, so that
# editing any of them triggers emmake. Evaluated lazily: the first run
# (before fetch) sees an empty tree, which is fine because the compile
# stamp depends on $(CONFIGURE_STAMP) which pulls in fetch.
POVRAY_SOURCES = $(shell find $(POVRAY_DIR)/source $(POVRAY_DIR)/vfe $(POVRAY_DIR)/unix \
                         \( -name '*.cpp' -o -name '*.cc' -o -name '*.c' \
                            -o -name '*.h' -o -name '*.hpp' \) 2>/dev/null)

# Exclude object files whose contents are unreachable under the WASM
# plugin path. LTO already drops them at link time, but keeping them out
# of the link entirely is cleaner, shaves compile time, and eliminates
# their static constructors from `__wasm_call_ctors`.
POVRAY_DEAD_OBJS = \
    $(POVRAY_DIR)/vfe/unix/unixconsole.o \
    $(POVRAY_DIR)/vfe/unix/unixoptions.o \
    $(POVRAY_DIR)/unix/disp_text.o \
    $(POVRAY_DIR)/unix/disp_sdl.o \
    $(POVRAY_DIR)/source/base/image/bmp.o \
    $(POVRAY_DIR)/source/base/image/gif.o \
    $(POVRAY_DIR)/source/base/image/gifdecod.o \
    $(POVRAY_DIR)/source/base/image/hdr.o \
    $(POVRAY_DIR)/source/base/image/iff.o \
    $(POVRAY_DIR)/source/base/image/jpeg.o \
    $(POVRAY_DIR)/source/base/image/openexr.o \
    $(POVRAY_DIR)/source/base/image/ppm.o \
    $(POVRAY_DIR)/source/base/image/targa.o \
    $(POVRAY_DIR)/source/base/image/tiff.o \
    $(POVRAY_DIR)/source/core/shape/truetype.o \
    $(POVRAY_DIR)/source/base/font/timrom.o \
    $(POVRAY_DIR)/source/base/font/cyrvetic.o \
    $(POVRAY_DIR)/source/base/font/crystal.o \
    $(POVRAY_DIR)/source/base/font/povlogo.o \
    $(POVRAY_DIR)/source/base/animation/animation.o \
    $(POVRAY_DIR)/source/base/animation/moov.o \
    $(POVRAY_DIR)/source/backend/control/benchmark.o \
    $(POVRAY_DIR)/source/backend/control/benchmark_ini.o \
    $(POVRAY_DIR)/source/backend/control/benchmark_pov.o

POVRAY_OBJECTS = $(filter-out $(POVRAY_DEAD_OBJS), \
                   $(shell find $(POVRAY_DIR)/source $(POVRAY_DIR)/vfe $(POVRAY_DIR)/unix \
                           -name '*.o' 2>/dev/null))

# Patch artifacts: shell scripts that apply changes (patches/*.patch.sh)
# and a static unified diff (patches/*.patch) consumed by 0001's wrapper.
# Both run in the PREBUILD stage (after ./configure is generated). Both
# are listed as deps of $(PREBUILD_STAMP) so editing either re-triggers.
PATCH_SCRIPTS  = $(wildcard patches/*.patch.sh)
PATCH_FILES    = $(wildcard patches/*.patch)

# Stop make's built-in `%: %.sh` implicit rule (which catenates the .sh
# into a target file) from clobbering our static .patch artifacts.
$(PATCH_FILES): ;

PLUGIN_INCLUDES = -I$(POVRAY_DIR)/source \
                  -I$(POVRAY_DIR)/source/base \
                  -I$(POVRAY_DIR)/source/core \
                  -I$(POVRAY_DIR)/source/backend \
                  -I$(POVRAY_DIR)/source/frontend \
                  -I$(POVRAY_DIR)/source/parser \
                  -I$(POVRAY_DIR)/vfe \
                  -I$(POVRAY_DIR)/vfe/unix \
                  -I$(POVRAY_DIR)/unix \
                  -I$(POVRAY_DIR)/unix/povconfig \
                  -I$(POVRAY_DIR)/platform/unix \
                  -I$(THREAD_STUB_INC) \
                  -I$(PREFIX)/include \
                  -DHAVE_CONFIG_H -I$(POVRAY_DIR) \
                  -include $(CURDIR)/include/no_exceptions.h

# ---- Phony aliases -------------------------------------------------------

.PHONY: all help deps fetch patch prebuild configure compile wasm dev \
        smoke install clean distclean harness harness-run harness-render

all: wasm

help:
	@echo "Build targets:"
	@echo "  make deps         - build zlib, libpng, boost into $(PREFIX) (once)"
	@echo "  make smoke        - plugin-glue-only wasm (no POV-Ray linkage)"
	@echo "  make wasm         - full incremental build (default)"
	@echo "  make dev          - -O0 build into build/dev/"
	@echo "  make install      - copy pkg/* into ~/.local/share/typst/packages/local/povrayst/0.1.1"
	@echo ""
	@echo "Debugging:"
	@echo "  make harness      - build the wasmi-based Rust harness (harness/)"
	@echo "  make harness-run  - harness pkg/povray.wasm version()"
	@echo "  make harness-render SCENE=scene.pov - harness render() on SCENE"
	@echo ""
	@echo "Housekeeping:"
	@echo "  make clean        - remove plugin + harness build artifacts"
	@echo "  make distclean    - also remove POV-Ray source tree + deps"

deps:       $(DEPS_STAMP)
fetch:      $(FETCH_STAMP)
patch:      $(PATCH_STAMP)
prebuild:   $(PREBUILD_STAMP)
configure:  $(CONFIGURE_STAMP)
compile:    $(COMPILE_STAMP)
wasm:       $(OUT)

# ---- Stage 1: dependencies (zlib + libpng + boost, built into PREFIX) ----

$(DEPS_STAMP): scripts/build-deps.sh
	@chmod +x scripts/build-deps.sh
	$(EMSDK_LOAD); ./scripts/build-deps.sh "$(PREFIX)"
	@mkdir -p $(dir $@) && touch $@

# ---- Stage 2: fetch POV-Ray source (git submodule) ----------------------
# povray-src/ is a submodule pointing at github.com/POV-Ray/povray.
# `git submodule update --init` checks out the commit recorded in the
# parent repo (currently release/v3.8.0). A full clone (~150 MB) happens
# on first init; subsequent inits are a no-op.

$(FETCH_STAMP):
	@echo ">> initializing POV-Ray submodule"
	git submodule update --init $(POVRAY_DIR)

# ---- Stage 3: patch marker ----------------------------------------------
# Currently no git-apply patches; shell scripts run in PREBUILD below.
# Stage exists so existing stamp dependencies keep working.

$(PATCH_STAMP): $(FETCH_STAMP)
	@touch $@

# ---- Stage 4: prebuild.sh + shell patches -------------------------------
# prebuild.sh generates ./configure from configure.ac. Our shell-script
# patches then massage the source tree (and the generated configure).
# Each script takes $(POVRAY_DIR) as its single argument and is
# expected to be idempotent.

$(PREBUILD_STAMP): $(PATCH_STAMP) $(PATCH_SCRIPTS) $(PATCH_FILES)
	cd $(POVRAY_DIR)/unix && ./prebuild.sh
	@for s in $(PATCH_SCRIPTS); do \
		chmod +x "$$s"; \
		"$$s" "$(POVRAY_DIR)"; \
	done

# ---- Stage 5: autotools configure ---------------------------------------

$(CONFIGURE_STAMP): $(PREBUILD_STAMP) $(DEPS_STAMP)
	cd $(POVRAY_DIR); \
	$(EMSDK_LOAD); \
	PTHREAD_CFLAGS="" \
	PTHREAD_LIBS="" \
	PTHREAD_CC="$$(which emcc)" \
	ax_pthread_ok=no \
	emconfigure ./configure \
		COMPILED_BY="typst-wasm-plugin <https://typst.app>" \
		NON_REDISTRIBUTABLE_BUILD=yes \
		--build=x86_64-pc-linux-gnu \
		--host=wasm32-unknown-emscripten \
		cross_compiling=yes \
		--disable-shared --enable-static \
		--disable-io-restrictions \
		--without-libsdl --without-libtiff --without-openexr --without-libjpeg --without-libpng --without-zlib \
		--with-boost=$(PREFIX) \
		--with-boost-thread=boost_thread \
		CXXFLAGS="$(OPT) $(SIMD_FLAGS) -ffast-math -fno-finite-math-only -fno-signed-zeros -fno-exceptions -sDISABLE_EXCEPTION_CATCHING=1 -frtti -ffunction-sections -fdata-sections -fvisibility=hidden -fvisibility-inlines-hidden -DPOVRAY_WASM=1 -DPOV_UINT16=char16_t -DPOVMSUCS2=char16_t -DBOOST_NO_EXCEPTIONS -I$(THREAD_STUB_INC) -I$(PREFIX)/include -include $(CURDIR)/include/no_exceptions.h" \
		CFLAGS="$(OPT) $(SIMD_FLAGS) -ffast-math -fno-finite-math-only -fno-signed-zeros -fno-exceptions -sDISABLE_EXCEPTION_CATCHING=1 -ffunction-sections -fdata-sections -fvisibility=hidden -DPOVRAY_WASM=1 -DPOV_UINT16=char16_t -DPOVMSUCS2=char16_t -I$(THREAD_STUB_INC) -I$(PREFIX)/include -include $(CURDIR)/include/no_exceptions.h" \
		LDFLAGS="-fno-exceptions -L$(PREFIX)/lib" \
		$(CONFIGURE_CACHE_OVERRIDES)
	@# Strip -pthread / -lpthread from config.status and regenerate
	@# all Makefiles. See scripts/strip-pthread.sh for the rationale.
	@echo ">> stripping -pthread from config.status + regenerating Makefiles"
	@chmod +x scripts/strip-pthread.sh
	@./scripts/strip-pthread.sh $(POVRAY_DIR)

# ---- Stage 6: compile POV-Ray (emmake is incremental internally) --------
# We depend on every .cpp/.h in the tree so that editing a POV-Ray file
# retriggers this stage. The stamp is only touched if emmake actually
# produced a new .o — that way, if nothing compiled, $(OUT) is not re-linked.

$(COMPILE_STAMP): $(CONFIGURE_STAMP) $(POVRAY_SOURCES)
	cd $(POVRAY_DIR); \
	$(EMSDK_LOAD); \
	emmake make -j$(JOBS) || true
	@# Only update the stamp if an .o is newer than it (or stamp is missing).
	@if [ ! -f $@ ] || find $(POVRAY_DIR)/source $(POVRAY_DIR)/vfe $(POVRAY_DIR)/unix \
	        -name '*.o' -newer $@ 2>/dev/null | grep -q .; then \
	    touch $@; \
	    echo ">> POV-Ray objects updated"; \
	else \
	    echo ">> POV-Ray objects unchanged"; \
	fi

# ---- Stage 7: compile the plugin glue -----------------------------------
# Compiled separately so that editing src/povray_plugin.cpp doesn't
# re-trigger emmake or the configure stage.

# Depends on $(CONFIGURE_STAMP) so the POV-Ray source tree and the
# autoconf-generated config.h exist before the plugin compile can look
# up POV-Ray headers. Without this, parallel `make -j` races the plugin
# compile against fetch/patch/configure and the header chain can't
# resolve.
# Plugin TU is compiled with -fno-exceptions. This is critical:
# emscripten's EH mechanism uses invoke_* indirect calls through the
# __indirect_function_table, which only the JS runtime populates.
# Under wasmi (no JS), indirect calls trap on uninitialized table
# entries. LTO normally inlines away the invoke_* calls, but then it
# also DCEs code after throw-capable ops (basic_string::operator+=
# etc.), eating our send_result calls.
# With -fno-exceptions, no EH paths are generated for this TU at all
# — operator+= just aborts on failure (which never happens for small
# strings), and send_result calls are preserved.
CXA_STUB_OBJ    = $(BUILD_DIR)/cxa_stub.o
WASM_STUBS_OBJ   = $(BUILD_DIR)/wasm_stubs.o
VFS_OBJ          = $(BUILD_DIR)/vfs.o
INVOKE_STUBS_OBJ = $(BUILD_DIR)/invoke_stubs.o

# Plugin compiled WITHOUT -flto so LTO can't DCE its call chain.
# With _initialize running, the indirect function table is properly
# populated — invoke_* stubs work via table dispatch.
$(PLUGIN_OBJ): src/povray_plugin.cpp $(CONFIGURE_STAMP) | $(BUILD_DIR)
	$(EMSDK_LOAD); \
	em++ -O3 $(SIMD_FLAGS) -fno-exceptions -frtti \
		-ffunction-sections -fdata-sections \
		-fvisibility=hidden -fvisibility-inlines-hidden \
		-DPOVRAY_WASM=1 -DPOV_UINT16=char16_t -DPOVMSUCS2=char16_t -DBOOST_NO_EXCEPTIONS \
		$(PLUGIN_INCLUDES) \
		-c $< -o $@

# Compiled WITHOUT -flto so it's a real .o (not LTO bitcode). The
# linker resolves __cxa_throw from this .o BEFORE seeing the noreturn
# version in libc++abi. This ensures LTO sees our non-noreturn
# definition and doesn't DCE post-throw code.
$(CXA_STUB_OBJ): src/cxa_stub.c | $(BUILD_DIR)
	$(EMSDK_LOAD); \
	emcc -O3 -c $< -o $@

$(WASM_STUBS_OBJ): src/wasm_stubs.cpp | $(BUILD_DIR)
	$(EMSDK_LOAD); \
	em++ -O3 -DPOVRAY_WASM=1 -c $< -o $@

# Local invoke_* implementations that compile to `call_indirect` — so the
# linker resolves the symbols here instead of leaving them as env:*
# imports that the host must provide. Typst's wasmi host only provides
# `typst_env::*`; without this file, loading fails with
# "cannot find definition for import env::invoke_iiii".
$(INVOKE_STUBS_OBJ): src/invoke_stubs.c | $(BUILD_DIR)
	$(EMSDK_LOAD); \
	emcc -O3 -fno-exceptions -c $< -o $@

# In-memory VFS: overrides fopen/fread/fclose so POV-Ray can read scenes
# from wasm linear memory and capture rendered PNG output.
$(VFS_OBJ): src/vfs.c | $(BUILD_DIR)
	$(EMSDK_LOAD); \
	emcc -O3 -c $< -o $@

# ---- Stage 8: link + post-process ---------------------------------------

# Recompile critical VFE .o files WITHOUT -flto so their bodies survive.
# With -fexceptions but no LTO, invoke_* stubs are preserved but just
# return 0 (wasi-stub), making exceptions silent no-ops.
VFE_NOLTO_OBJS = $(BUILD_DIR)/vfesession_nolto.o $(BUILD_DIR)/vfe_nolto.o \
                 $(BUILD_DIR)/vfecontrol_nolto.o $(BUILD_DIR)/povray_nolto.o

$(BUILD_DIR)/vfesession_nolto.o: $(COMPILE_STAMP) | $(BUILD_DIR)
	$(EMSDK_LOAD); em++ -O3 $(SIMD_FLAGS) -fno-exceptions -frtti \
		-ffunction-sections -fdata-sections \
		-fvisibility=hidden -fvisibility-inlines-hidden \
		-DPOVRAY_WASM=1 -DPOV_UINT16=char16_t -DPOVMSUCS2=char16_t \
		-sDISABLE_EXCEPTION_CATCHING=1 \
		$(PLUGIN_INCLUDES) -c $(POVRAY_DIR)/vfe/vfesession.cpp -o $@

$(BUILD_DIR)/vfe_nolto.o: $(COMPILE_STAMP) | $(BUILD_DIR)
	$(EMSDK_LOAD); em++ -O3 $(SIMD_FLAGS) -fno-exceptions -frtti \
		-ffunction-sections -fdata-sections \
		-fvisibility=hidden -fvisibility-inlines-hidden \
		-DPOVRAY_WASM=1 -DPOV_UINT16=char16_t -DPOVMSUCS2=char16_t \
		-sDISABLE_EXCEPTION_CATCHING=1 \
		$(PLUGIN_INCLUDES) -c $(POVRAY_DIR)/vfe/vfe.cpp -o $@

$(BUILD_DIR)/vfecontrol_nolto.o: $(COMPILE_STAMP) | $(BUILD_DIR)
	$(EMSDK_LOAD); em++ -O3 $(SIMD_FLAGS) -fno-exceptions -frtti \
		-ffunction-sections -fdata-sections \
		-fvisibility=hidden -fvisibility-inlines-hidden \
		-DPOVRAY_WASM=1 -DPOV_UINT16=char16_t -DPOVMSUCS2=char16_t \
		-sDISABLE_EXCEPTION_CATCHING=1 \
		$(PLUGIN_INCLUDES) -c $(POVRAY_DIR)/vfe/vfecontrol.cpp -o $@

$(BUILD_DIR)/povray_nolto.o: $(COMPILE_STAMP) | $(BUILD_DIR)
	$(EMSDK_LOAD); em++ -O3 $(SIMD_FLAGS) -fno-exceptions -frtti \
		-ffunction-sections -fdata-sections \
		-fvisibility=hidden -fvisibility-inlines-hidden \
		-DPOVRAY_WASM=1 -DPOV_UINT16=char16_t -DPOVMSUCS2=char16_t \
		-sDISABLE_EXCEPTION_CATCHING=1 \
		$(PLUGIN_INCLUDES) -c $(POVRAY_DIR)/source/backend/povray.cpp -o $@

$(OUT): $(PLUGIN_OBJ) $(CXA_STUB_OBJ) $(WASM_STUBS_OBJ) $(INVOKE_STUBS_OBJ) $(VFE_NOLTO_OBJS) $(COMPILE_STAMP) pkg/typst.toml pkg/povray.typ | pkg
	$(EMSDK_LOAD); \
	em++ $(OPT) $(SIMD_FLAGS) -fno-exceptions -frtti \
		-sSTANDALONE_WASM=1 \
		-sERROR_ON_UNDEFINED_SYMBOLS=0 \
		-sALLOW_MEMORY_GROWTH=1 \
		-sINITIAL_MEMORY=16MB \
		-sENVIRONMENT=shell \
		-sDISABLE_EXCEPTION_CATCHING=1 \
		-sEXPORT_KEEPALIVE=1 \
		-sSTACK_SIZE=8388608 \
		-Wl,--wrap=pthread_cond_timedwait \
		-Wl,--wrap=pthread_cond_wait \
		-Wl,--gc-sections \
		--no-entry \
		$(PLUGIN_OBJ) $(WASM_STUBS_OBJ) $(INVOKE_STUBS_OBJ) \
		$(POVRAY_OBJECTS) \
		-L$(PREFIX)/lib $(BOOST_LIBS) \
		-o $@
	@echo ">> stubbing WASI imports"
	@# Stub all env::* that Typst's host doesn't provide. The list
	@# covers: WASI shims, EH runtime, Timer/Delay, Filesystem ops.
	wasi-stub $@ -o $@ --stub-module wasi_snapshot_preview1 \
		--stub-function env:__syscall_getcwd,env:__syscall_unlinkat,env:_emscripten_system,env:_emscripten_throw_longjmp,env:emscripten_notify_memory_growth,env:__cxa_find_matching_catch_2,env:__cxa_find_matching_catch_3,env:__cxa_find_matching_catch_4,env:__cxa_find_matching_catch_5,env:__cxa_find_matching_catch_6,env:__cxa_find_matching_catch_7,env:__cxa_begin_catch,env:__cxa_end_catch,env:llvm_eh_typeid_for,env:__cxa_uncaught_exceptions,env:_ZN8pov_base5DelayEj,env:_ZN8pov_base5TimerC1Ev,env:_ZN8pov_base5TimerD1Ev,env:_ZNK8pov_base5Timer15ElapsedRealTimeEv,env:_ZNK8pov_base5Timer21HasValidThreadCPUTimeEv,env:_ZNK8pov_base5Timer20ElapsedThreadCPUTimeEv,env:_ZN8pov_base5Timer5ResetEv,env:__cxa_throw,env:__cxa_rethrow,env:_ZN8pov_base10Filesystem10DeleteFileERKNSt3__212basic_stringIDsNS1_11char_traitsIDsEENS1_9allocatorIDsEEEE,env:_ZN8pov_base10Filesystem9LargeFileC1Ev,env:_ZN8pov_base10Filesystem9LargeFile8CreateRWERKNSt3__212basic_stringIDsNS2_11char_traitsIDsEENS2_9allocatorIDsEEEE,env:_ZN8pov_base10Filesystem9LargeFile4SeekEx,env:_ZN8pov_base10Filesystem9LargeFile5WriteEPKvm,env:_ZN8pov_base10Filesystem9LargeFile5CloseEv,env:_ZN8pov_base10Filesystem9LargeFileD1Ev,env:_ZN8pov_base10Filesystem9LargeFile4ReadEPvm,env:_ZN8pov_base10Filesystem13TemporaryFile11SuggestNameEv \
		-r 0
	@echo ">> wasm-opt"
	wasm-opt $(WASM_OPT_FLAGS) $@ -o $@
	@ls -lh $@

# ---- Smoke build: plugin glue only, no POV-Ray --------------------------
# Builds a self-contained pkg/povray.wasm that only uses src/povray_plugin.cpp.
# version() returns its placeholder string, render() returns the "not yet
# wired up" error. Useful to validate toolchain and Typst plugin ABI
# before committing to the full POV-Ray port.

smoke: | pkg
	$(EMSDK_LOAD); \
	em++ $(OPT) $(SIMD_FLAGS) -fno-exceptions -fno-rtti \
		-sSTANDALONE_WASM=1 \
		-sERROR_ON_UNDEFINED_SYMBOLS=0 \
		-sALLOW_MEMORY_GROWTH=1 \
		-sENVIRONMENT=shell \
		-sEXPORT_KEEPALIVE=1 \
		--no-entry \
		src/povray_plugin.cpp \
		-o $(OUT)
	wasi-stub $(OUT) -o $(OUT) --stub-module env,wasi_snapshot_preview1 -r 0
	wasm-opt $(WASM_OPT_FLAGS) $(OUT) -o $(OUT)
	@ls -lh $(OUT)

# ---- Directories --------------------------------------------------------

$(BUILD_DIR) pkg:
	@mkdir -p $@

# ---- Dev build (separate build dir so -Os / -O0 don't collide) ----------
# Dev uses a sibling build tree for the plugin object; POV-Ray objects
# are shared (switching POV-Ray's own opt level requires `make distclean`).

dev: OPT = -O0
dev: WASM_OPT_FLAGS = -O0 --enable-simd --enable-bulk-memory
dev: BUILD_DIR = $(CURDIR)/build/dev
dev: wasm

# ---- Wasmi harness (Rust) -----------------------------------------------
# Loads pkg/povray.wasm under wasmi (the same interpreter Typst uses),
# wires up the typst_env imports, and exposes the exports as CLI calls.
# Indispensable for diagnosing runtime hangs (fuel-limited execution,
# per-instruction tracing) that aren't observable from inside Typst.

HARNESS_BIN = harness/target/release/povray-harness

harness: $(HARNESS_BIN)
$(HARNESS_BIN): $(wildcard harness/src/*.rs) harness/Cargo.toml
	cd harness && cargo build --release

harness-run: $(OUT) $(HARNESS_BIN)
	$(HARNESS_BIN) $(OUT) --func version

# make harness-render SCENE=test/minimal.pov
harness-render: $(OUT) $(HARNESS_BIN)
	@test -n "$(SCENE)" || (echo "usage: make harness-render SCENE=<path>"; exit 1)
	$(HARNESS_BIN) $(OUT) --func render --arg @$(SCENE) --arg ''

# ---- Install ------------------------------------------------------------

install: $(OUT)
	mkdir -p ~/.local/share/typst/packages/local/povrayst/0.1.1
	cp pkg/povray.wasm pkg/povray.typ pkg/typst.toml \
		~/.local/share/typst/packages/local/povrayst/0.1.1/

# ---- Housekeeping -------------------------------------------------------

clean:
	rm -rf $(BUILD_DIR) $(OUT) harness/target

distclean:
	rm -rf $(BUILD_DIR) pkg/povray.wasm $(POVRAY_DIR) $(PREFIX) harness/target
