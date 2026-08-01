// povray-harness
//
// Standalone wasmi driver for pkg/povray.wasm — reproduces Typst's
// runtime behavior exactly (same interpreter, same import shape) but
// lets us pass arbitrary inputs, enforce fuel limits, and get real
// trap reports that Typst hides.
//
// Usage:
//   povray-harness <wasm> --func <name> [--arg <s>|@file]... [--fuel N] [--trace-imports]
//
// Examples:
//   povray-harness pkg/povray.wasm --func version
//   povray-harness pkg/povray.wasm --func render --arg 'sphere{...}' --arg ''
//   povray-harness pkg/povray.wasm --func render --arg @scene.pov --arg '' --fuel 100000000

use std::cell::Cell;
use std::path::PathBuf;
use std::process::ExitCode;
use std::rc::Rc;
use std::time::Instant;

use wasmi::{Caller, Config, Engine, Instance, Linker, Memory, Module, Store};

// ---------------------------------------------------------------------------
// Host state shared by every import callback.

struct HostState {
    /// Concatenated argument bytes the guest will read via
    /// wasm_minimal_protocol_write_args_to_buffer.
    args: Vec<u8>,
    /// Captured by wasm_minimal_protocol_send_result_to_host.
    result: Vec<u8>,
    /// Set after instantiation so the import callbacks can read/write
    /// the guest's linear memory.
    memory: Option<Memory>,
    /// Logging counters — cheap observability.
    send_calls: Rc<Cell<u64>>,
    write_calls: Rc<Cell<u64>>,
    /// Print each import invocation. Useful for deadlock diagnosis.
    trace_imports: bool,
}

// ---------------------------------------------------------------------------
// CLI parsing — small enough to hand-roll.

struct Cli {
    wasm:           PathBuf,
    func:           String,
    args:           Vec<Vec<u8>>,
    fuel:           Option<u64>,
    trace_imports:  bool,
    list_only:      bool,
    no_init:        bool,
    out:            Option<PathBuf>,
}

fn parse_cli() -> Result<Cli, String> {
    let raw: Vec<String> = std::env::args().skip(1).collect();
    let mut wasm: Option<PathBuf> = None;
    let mut func: Option<String> = None;
    let mut args: Vec<Vec<u8>> = Vec::new();
    let mut fuel: Option<u64> = None;
    let mut trace_imports = false;
    let mut list_only = false;
    let mut no_init = false;
    let mut out: Option<PathBuf> = None;

    let mut i = 0;
    while i < raw.len() {
        match raw[i].as_str() {
            "-h" | "--help" => return Err(usage()),
            "--list" => list_only = true,
            "--func" => {
                i += 1;
                func = Some(raw.get(i).ok_or_else(|| "missing value for --func".to_string())?.clone());
            }
            "--arg" => {
                i += 1;
                let v = raw.get(i).ok_or_else(|| "missing value for --arg".to_string())?;
                args.push(read_arg(v)?);
            }
            "--fuel" => {
                i += 1;
                let v = raw.get(i).ok_or_else(|| "missing value for --fuel".to_string())?;
                fuel = Some(v.parse::<u64>().map_err(|e| format!("--fuel: {e}"))?);
            }
            "--trace-imports" => trace_imports = true,
            "--no-init" => no_init = true,
            "--out" => {
                i += 1;
                out = Some(PathBuf::from(raw.get(i).ok_or_else(|| "missing value for --out".to_string())?));
            }
            other if wasm.is_none() && !other.starts_with('-') => {
                wasm = Some(PathBuf::from(other));
            }
            other => return Err(format!("unknown argument: {other}\n\n{}", usage())),
        }
        i += 1;
    }

    Ok(Cli {
        wasm:          wasm.ok_or_else(|| format!("missing <wasm> path\n\n{}", usage()))?,
        func:          func.unwrap_or_else(|| "version".to_string()),
        args,
        fuel,
        trace_imports,
        list_only,
        no_init,
        out,
    })
}

fn read_arg(s: &str) -> Result<Vec<u8>, String> {
    if let Some(path) = s.strip_prefix('@') {
        std::fs::read(path).map_err(|e| format!("read {path}: {e}"))
    } else {
        Ok(s.as_bytes().to_vec())
    }
}

fn usage() -> String {
    "usage: povray-harness <wasm> [options]\n\
     \n\
       --list                 print imports + exports, then exit\n\
       --func NAME            export to call (default: version)\n\
       --arg VAL | @PATH      add a bytes argument (repeatable)\n\
       --fuel N               abort if call exceeds N instructions\n\
       --trace-imports        log each typst_env import call".to_string()
}

// ---------------------------------------------------------------------------
// Module introspection (for --list).

fn print_module_summary(module: &Module) {
    eprintln!("imports:");
    for imp in module.imports() {
        eprintln!("  {}::{}  {:?}", imp.module(), imp.name(), imp.ty());
    }
    eprintln!("exports:");
    for exp in module.exports() {
        eprintln!("  {}  {:?}", exp.name(), exp.ty());
    }
}

// ---------------------------------------------------------------------------
// Instantiation.

fn build_store(
    wasm_bytes: &[u8],
    fuel: Option<u64>,
    trace_imports: bool,
    no_init: bool,
) -> Result<(Store<HostState>, Instance), String> {
    let mut config = Config::default();
    if fuel.is_some() {
        config.consume_fuel(true);
    }
    let engine = Engine::new(&config);
    let module = Module::new(&engine, wasm_bytes)
        .map_err(|e| format!("parse wasm: {e}"))?;

    let send_calls  = Rc::new(Cell::new(0u64));
    let write_calls = Rc::new(Cell::new(0u64));

    let mut store = Store::new(
        &engine,
        HostState {
            args: Vec::new(),
            result: Vec::new(),
            memory: None,
            send_calls:  send_calls.clone(),
            write_calls: write_calls.clone(),
            trace_imports,
        },
    );

    if let Some(n) = fuel {
        store.set_fuel(n).map_err(|e| format!("set_fuel: {e}"))?;
    }

    let mut linker = Linker::<HostState>::new(&engine);

    // ---- typst_env::wasm_minimal_protocol_write_args_to_buffer ----
    linker
        .func_wrap(
            "typst_env",
            "wasm_minimal_protocol_write_args_to_buffer",
            |mut caller: Caller<'_, HostState>, ptr: i32| {
                if caller.data().trace_imports {
                    eprintln!("[trace] write_args_to_buffer(ptr={ptr}) len={}",
                              caller.data().args.len());
                }
                caller.data().write_calls.set(caller.data().write_calls.get() + 1);
                let mem = caller.data().memory.expect("memory not set");
                let data = caller.data().args.clone();
                mem.write(&mut caller, ptr as usize, &data)
                    .expect("write_args_to_buffer: memory write failed");
            },
        )
        .map_err(|e| format!("linker: {e}"))?;

    // ---- typst_env::wasm_minimal_protocol_send_result_to_host ----
    linker
        .func_wrap(
            "typst_env",
            "wasm_minimal_protocol_send_result_to_host",
            |mut caller: Caller<'_, HostState>, ptr: i32, len: i32| {
                caller.data().send_calls.set(caller.data().send_calls.get() + 1);
                let mem = caller.data().memory.expect("memory not set");
                let mut buf = vec![0u8; len as usize];
                mem.read(&caller, ptr as usize, &mut buf)
                    .expect("send_result_to_host: memory read failed");
                if caller.data().trace_imports {
                    // Render short payloads as UTF-8 inline so probe
                    // strings show up directly; otherwise just the
                    // length + hex prefix.
                    match std::str::from_utf8(&buf) {
                        Ok(s) if s.len() <= 160 && s.is_ascii() => {
                            eprintln!("[trace] send_result_to_host({len}B) = {s:?}");
                        }
                        _ => {
                            let hex: String = buf.iter().take(32).map(|b| format!("{b:02x}")).collect();
                            eprintln!("[trace] send_result_to_host({len}B) = {hex}...");
                        }
                    }
                }
                caller.data_mut().result = buf;
            },
        )
        .map_err(|e| format!("linker: {e}"))?;

    // ---- env::invoke_* --- call through indirect function table ----
    // Emscripten's JS-based EH wraps potentially-throwing C++ calls in
    // invoke_* functions. The first arg is the function table index;
    // remaining args are forwarded to the indirect call target.
    //
    // For non-invoke env imports we fall back to zero-return stubs.
    use wasmi::{Func as WasmFunc, Ref, Table, Val};

    /// Helper: look up __indirect_function_table from the caller's instance,
    /// extract the Func at `index`, call it with `args`, write results back.
    fn do_invoke(
        caller: &mut Caller<'_, HostState>,
        index: i32,
        args: &[Val],
        results: &mut [Val],
    ) -> Result<(), wasmi::Error> {
        let table: Table = caller
            .get_export("__indirect_function_table")
            .and_then(|e| e.into_table())
            .expect("invoke_*: no __indirect_function_table export");

        let val = table.get(&*caller, index as u64)
            .unwrap_or_else(|| panic!("invoke_*: table index {index} out of bounds"));

        let func = match val.funcref() {
            Some(Ref::Val(f)) => *f,
            _ => panic!("invoke_*: table slot {index} is null or not a funcref"),
        };

        // Allocate output buffer matching the callee's result count.
        let n_results = func.ty(&*caller).results().len();
        let mut out = vec![Val::I32(0); n_results];
        func.call(&mut *caller, args, &mut out)?;

        // Copy callee results into our results (invoke_* may return fewer
        // results than the callee if the invoke variant is void).
        for (dst, src) in results.iter_mut().zip(out.iter()) {
            *dst = src.clone();
        }
        Ok(())
    }

    for import in module.imports() {
        if import.module() == "typst_env" { continue; }
        match import.ty() {
            wasmi::ExternType::Func(func_ty) => {
                let name = import.name().to_string();
                let ft = func_ty.clone();

                if name.starts_with("invoke_") {
                    // invoke_*: first param is table index, rest forwarded.
                    let func = WasmFunc::new(
                        &mut store,
                        ft,
                        move |mut caller: Caller<'_, HostState>, params, results| {
                            if caller.data().trace_imports {
                                eprintln!("[trace] {name}(fp={}, +{} args)",
                                    params[0].i32().unwrap_or(-1),
                                    params.len() - 1);
                            }
                            let fp = params[0].i32().unwrap_or(0);
                            let args = &params[1..];
                            match do_invoke(&mut caller, fp, args, results) {
                                Ok(()) => Ok(()),
                                Err(e) => {
                                    let msg = format!("{e}");
                                    if msg.contains("incorrect number of parameters") ||
                                       msg.contains("type mismatch") {
                                        // Type mismatch on indirect call — treat as
                                        // "function threw" (return 0, let EH unwind).
                                        for r in results.iter_mut() {
                                            *r = Val::I32(0);
                                        }
                                        Ok(())
                                    } else if msg.contains("__resumeException") ||
                                              msg.contains("unhandled") {
                                        // Exception unwind hit dead end — trap.
                                        Err(e)
                                    } else {
                                        // Other errors — also treat as "threw".
                                        for r in results.iter_mut() {
                                            *r = Val::I32(0);
                                        }
                                        Ok(())
                                    }
                                }
                            }
                        },
                    );
                    let _ = linker.define(import.module(), import.name(), func);
                } else if name == "__resumeException" {
                    // __resumeException: unhandled exception must not return
                    // (would cause infinite EH loop). Trap instead.
                    let func = WasmFunc::new(
                        &mut store,
                        ft,
                        move |_caller, _params, _results| {
                            Err(wasmi::Error::new("__resumeException: unhandled C++ exception (trap)"))
                        },
                    );
                    let _ = linker.define(import.module(), import.name(), func);
                } else {
                    // Non-invoke: zero-return stub.
                    let func = WasmFunc::new(
                        &mut store,
                        ft,
                        move |_caller, _params, results| {
                            for r in results.iter_mut() {
                                *r = Val::I32(0);
                            }
                            Ok(())
                        },
                    );
                    let _ = linker.define(import.module(), import.name(), func);
                }
            }
            _ => {}
        }
    }

    let instance = linker
        .instantiate_and_start(&mut store, &module)
        .map_err(|e| format!("instantiate: {e}"))?;

    let memory = instance
        .get_memory(&store, "memory")
        .ok_or_else(|| "wasm has no exported 'memory'".to_string())?;
    store.data_mut().memory = Some(memory);

    // Call `_initialize` to run global C++ constructors and populate
    // the indirect function table. With -sDISABLE_EXCEPTION_CATCHING=1,
    // the invoke_* wrappers are gone so _initialize should succeed.
    // Scan the entire first data segment (0x400 to 0x10938) for corruption.
    let data_start: usize = 0x400;
    let data_end: usize = 0x10938;
    let data_len = data_end - data_start;
    let before = {
        let mut buf = vec![0u8; data_len];
        memory.read(&store, data_start, &mut buf).ok();
        buf
    };

    if !no_init {
    if let Ok(init) = instance.get_typed_func::<(), ()>(&store, "_initialize") {
        eprintln!("         calling _initialize...");
        match init.call(&mut store, ()) {
            Err(e) => {
                let msg = format!("{e}");
                if msg.contains("fuel") {
                    eprintln!("         _initialize ran out of fuel (expected for bisect)");
                } else {
                    eprintln!("         _initialize failed: {e}");
                }
            }
            Ok(()) => {
                eprintln!("         _initialize OK");
            }
        }
    }
    } else {
        eprintln!("         _initialize SKIPPED (--no-init)");
    }

    {
        let mut after = vec![0u8; data_len];
        memory.read(&store, data_start, &mut after).ok();
        // Find first and last changed byte
        let mut first_diff = None;
        let mut last_diff = None;
        let mut diff_count = 0usize;
        for i in 0..data_len {
            if before[i] != after[i] {
                if first_diff.is_none() { first_diff = Some(i); }
                last_diff = Some(i);
                diff_count += 1;
            }
        }
        if let (Some(first), Some(last)) = (first_diff, last_diff) {
            eprintln!("         DATA CORRUPTION: {diff_count} bytes changed in range 0x{:x}..0x{:x} (mem addrs 0x{:x}..0x{:x})",
                first, last, data_start + first, data_start + last);
            // Show first few changed bytes
            let show_start = first;
            let show_end = (first + 32).min(data_len);
            let before_hex: String = before[show_start..show_end].iter().map(|b| format!("{b:02x}")).collect();
            let after_hex: String = after[show_start..show_end].iter().map(|b| format!("{b:02x}")).collect();
            eprintln!("         before@0x{:x}: {before_hex}", data_start + show_start);
            eprintln!("         after @0x{:x}: {after_hex}", data_start + show_start);
        } else {
            eprintln!("         No data corruption in segment 0 (0x{data_start:x}..0x{data_end:x})");
        }
    }

    Ok((store, instance))
}

// ---------------------------------------------------------------------------
// Export invocation — arity is determined by the #args passed on the CLI.
// Typst plugin ABI: every arg is a byte slice; the guest receives their
// lengths as i32s in call order and pulls the bytes via write_args_to_buffer.

fn load_args(store: &mut Store<HostState>, args: &[Vec<u8>]) {
    let st = store.data_mut();
    st.args.clear();
    for a in args {
        st.args.extend_from_slice(a);
    }
    st.result.clear();
}

fn call(
    store: &mut Store<HostState>,
    instance: &Instance,
    name: &str,
    args: &[Vec<u8>],
) -> Result<(i32, Vec<u8>), String> {
    load_args(store, args);

    let lens: Vec<i32> = args.iter().map(|a| a.len() as i32).collect();

    let code = match lens.len() {
        0 => instance.get_typed_func::<(), i32>(&store, name)
                .map_err(|e| format!("get {name}: {e}"))?
                .call(&mut *store, ()),
        1 => instance.get_typed_func::<i32, i32>(&store, name)
                .map_err(|e| format!("get {name}: {e}"))?
                .call(&mut *store, lens[0]),
        2 => instance.get_typed_func::<(i32, i32), i32>(&store, name)
                .map_err(|e| format!("get {name}: {e}"))?
                .call(&mut *store, (lens[0], lens[1])),
        3 => instance.get_typed_func::<(i32, i32, i32), i32>(&store, name)
                .map_err(|e| format!("get {name}: {e}"))?
                .call(&mut *store, (lens[0], lens[1], lens[2])),
        n => return Err(format!("unsupported arg count: {n}")),
    };

    let result = store.data().result.clone();
    code.map(|c| (c, result))
        .map_err(|e| format!("{name} trapped: {e}"))
}

// ---------------------------------------------------------------------------
// Main.

fn main() -> ExitCode {
    let cli = match parse_cli() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{e}");
            return ExitCode::from(2);
        }
    };

    eprintln!("harness: loading {}", cli.wasm.display());
    let bytes = match std::fs::read(&cli.wasm) {
        Ok(b) => b,
        Err(e) => {
            eprintln!("read {}: {e}", cli.wasm.display());
            return ExitCode::from(1);
        }
    };
    eprintln!("         {} bytes", bytes.len());

    if cli.list_only {
        let engine = Engine::default();
        match Module::new(&engine, &bytes) {
            Ok(m) => {
                print_module_summary(&m);
                return ExitCode::SUCCESS;
            }
            Err(e) => {
                eprintln!("parse wasm: {e}");
                return ExitCode::from(1);
            }
        }
    }

    let (mut store, instance) = match build_store(&bytes, cli.fuel, cli.trace_imports, cli.no_init) {
        Ok(p) => p,
        Err(e) => {
            eprintln!("instantiate failed: {e}");
            return ExitCode::from(1);
        }
    };

    let mem = instance.get_memory(&store, "memory").unwrap();
    eprintln!(
        "         memory: {} pages ({} KB)",
        mem.size(&store),
        mem.size(&store) * 64
    );
    if let Some(n) = cli.fuel {
        eprintln!("         fuel: {n} instructions");
    }
    // Table slot 0 is always null in wasm. Code that calls through a
    // null function pointer dispatches via slot 0 → IndirectCallToNull
    // trap. Populate slot 0 with a no-op so these become silent no-ops.
    if let Some(table) = instance.get_table(&store, "__indirect_function_table") {
        let sz = table.size(&store);
        eprintln!("         table: {sz} entries");
        // We can't easily create a generic no-op function for ALL
        // signatures. Instead, just report if slot 0 is hit.
    }

    eprintln!("harness: calling {}({} args)", cli.func, cli.args.len());
    let started = Instant::now();
    let outcome = call(&mut store, &instance, &cli.func, &cli.args);
    let elapsed = started.elapsed();

    let fuel_used = cli.fuel.and_then(|n| store.get_fuel().ok().map(|left| n - left));
    let send_calls  = store.data().send_calls.get();
    let write_calls = store.data().write_calls.get();

    eprintln!("         elapsed: {:.3} ms", elapsed.as_secs_f64() * 1000.0);
    eprintln!("         memory after: {} pages", mem.size(&store));
    eprintln!("         imports: {write_calls} write_args, {send_calls} send_result");
    if let Some(n) = fuel_used {
        eprintln!("         fuel used: {n} instructions");
    }

    match outcome {
        Ok((0, result)) => {
            eprintln!("         return: 0 (success), {} bytes", result.len());
            if let Some(p) = &cli.out {
                let _ = std::fs::write(p, &result).map_err(|e| eprintln!("write {}: {e}", p.display()));
                eprintln!("         wrote {} bytes to {}", result.len(), p.display());
            }
            // Try to render as UTF-8; fall back to hex-dump of first 64 bytes.
            match std::str::from_utf8(&result) {
                Ok(s) => println!("{s}"),
                Err(_) => {
                    eprintln!("         (binary — writing to stdout raw)");
                    use std::io::Write;
                    std::io::stdout().write_all(&result).ok();
                }
            }
            ExitCode::SUCCESS
        }
        Ok((code, result)) => {
            eprintln!("         return: {code} (error), {} bytes", result.len());
            println!("{}", String::from_utf8_lossy(&result));
            ExitCode::from(code.clamp(1, 127) as u8)
        }
        Err(e) => {
            eprintln!("         TRAPPED: {e}");
            ExitCode::from(1)
        }
    }
}
