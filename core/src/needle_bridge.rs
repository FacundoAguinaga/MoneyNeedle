//! Bindings al engine prebuilt de Cactus Needle (`libneedle.a` + `needle.h`).
//!
//! El engine NO se versiona: se descarga por plataforma con
//! `needle build --platform <t> --out <dir>` (ver `docs/training.md`).
//! Este módulo solo declara la FFI; el enlazado lo hace `build.rs`
//! cuando `NEEDLE_LIB_DIR` apunta al dir con `libneedle.a`.
//!
//! Ejemplo (engine linux-x86_64 ya descargado en /tmp/needle-device):
//! ```sh
//! NEEDLE_LIB_DIR=/tmp/needle-device cargo run --example needle_smoke \
//!   --features needle-engine -- prototype/data/tuned2.cact "gasté 5000 en súper"
//! ```
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_uchar, c_ulonglong};

extern "C" {
    fn needle_init(system_prompt: *const c_char, tools_json: *const c_char, tool_index_path: *const c_char) -> c_int;
    fn needle_last_error() -> *const c_char;
    fn needle_complete(input: *const c_char, max_new_tokens: c_int, out: *mut c_char, out_capacity: c_int) -> c_int;
    fn needle_reset();
    fn needle_load(cact: *const c_uchar, n: c_ulonglong) -> c_int;
}

fn last_error() -> String {
    unsafe {
        let p = needle_last_error();
        if p.is_null() {
            return "error desconocido".into();
        }
        CStr::from_ptr(p).to_string_lossy().into_owned()
    }
}

fn c(s: &str) -> CString {
    CString::new(s).expect("string con NUL interior")
}

/// Carga un `.cact` ya leído en memoria. Consume ~RAM del modelo una vez.
pub fn load(cact: &[u8]) -> Result<(), String> {
    let rc = unsafe { needle_load(cact.as_ptr(), cact.len() as c_ulonglong) };
    if rc < 0 {
        return Err(last_error());
    }
    Ok(())
}

/// Fija system prompt + tools (el prefijo KV se cachea en el engine).
/// `tool_index_path`: null hoy (sin embedding head en este release).
pub fn init(system_prompt: Option<&str>, tools_json: &str) -> Result<usize, String> {
    let sys = system_prompt.map(c);
    let tools = c(tools_json);
    let rc = unsafe {
        needle_init(
            sys.as_ref().map(|s| s.as_ptr()).unwrap_or(std::ptr::null()),
            tools.as_ptr(),
            std::ptr::null(),
        )
    };
    if rc < 0 {
        return Err(last_error());
    }
    Ok(rc as usize)
}

/// Una inferencia. Devuelve el JSON crudo del engine (envelope con
/// `function_calls` / `suppressed_calls`, ver `prototype/mn_parse.py`).
pub fn complete(input: &str, max_new_tokens: i32) -> Result<String, String> {
    // 64KB alcanzan para tool_calls chicos; el engine informa si falta.
    let mut buf = vec![0u8; 65536];
    let rc = unsafe {
        needle_complete(
            c(input).as_ptr(),
            max_new_tokens,
            buf.as_mut_ptr() as *mut c_char,
            buf.len() as c_int,
        )
    };
    if rc < 0 {
        return Err(last_error());
    }
    let len = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
    String::from_utf8(buf[..len].to_vec()).map_err(|e| e.to_string())
}

/// Limpia la conversación (obligatorio entre frases independientes).
pub fn reset() {
    unsafe { needle_reset() }
}
