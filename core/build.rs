// build.rs — enlaza libneedle.a solo si NEEDLE_LIB_DIR está seteado.
// Sin esa var, el crate compila igual (el ejemplo con required-features
// se saltea y `cargo test` no necesita el engine).
//
// El engine es C++ (libc++). Si no hay libc++ del sistema, se puede usar
// el del Android SDK (NEEDLE_CXX_DIR) más el shim de ffi-shim/ para el
// único símbolo que le falta (__hash_memory).
fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=ffi-shim/hash_memory.cpp");
    if let Ok(dir) = std::env::var("NEEDLE_LIB_DIR") {
        println!("cargo:rustc-link-search=native={dir}");
        println!("cargo:rustc-link-lib=static=needle");
        println!("cargo:rerun-if-env-changed=NEEDLE_LIB_DIR");
    }
    if let Ok(dir) = std::env::var("NEEDLE_CXX_DIR") {
        println!("cargo:rustc-link-search=native={dir}");
        println!("cargo:rustc-link-lib=dylib=c++");
        println!("cargo:rerun-if-env-changed=NEEDLE_CXX_DIR");
        let out = std::env::var("OUT_DIR").unwrap();
        let obj = format!("{out}/hash_memory.o");
        // C++ a propósito: el símbolo debe salir mangled como std::__1.
        let shim = std::process::Command::new("cc")
            .args(["-O2", "-x", "c++", "-c", "ffi-shim/hash_memory.cpp", "-o", &obj])
            .status()
            .expect("cc no encontrado para compilar el shim");
        assert!(shim.success(), "falló compilar ffi-shim/hash_memory.cpp");
        println!("cargo:rustc-link-arg={obj}");
    }
}
