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
    println!("cargo:rerun-if-env-changed=NEEDLE_LIB_DIR");
    println!("cargo:rerun-if-env-changed=NEEDLE_CXX_DIR");
    println!("cargo:rerun-if-env-changed=ANDROID_NDK_HOME");

    let target = std::env::var("TARGET").unwrap_or_default();
    let is_android = target.contains("android");

    if let Ok(dir) = std::env::var("NEEDLE_LIB_DIR") {
        println!("cargo:rustc-link-search=native={dir}");
        println!("cargo:rustc-link-lib=static=needle");
    }
    if is_android {
        // En Android, libc++_shared viene del NDK (completo, sin shim).
        // OJO: se pasa por ruta completa, NO por -L: si el dir del sysroot
        // entra al search path, el linker pesca objetos de libc.a estática
        // (ej. un getauxval incompatible que crashea al cargar en el device).
        if let Some(libdir) = ndk_cxx_libdir(&target) {
            println!("cargo:rustc-link-arg={libdir}/libc++_shared.so");
            return;
        }
        panic!("ANDROID_NDK_HOME no apunta a un NDK válido");
    }
    // Solo desktop sin libc++ del sistema: libc++.so del Android SDK
    // (emulador) + shim para el único símbolo que le falta.
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

/// Dir con libc++_shared.so del NDK para el target dado, o None.
fn ndk_cxx_libdir(target: &str) -> Option<String> {
    let ndk = std::env::var("ANDROID_NDK_HOME").ok().or_else(|| {
        std::env::var("HOME").ok().map(|h| format!("{h}/Android/Sdk/ndk/28.2.13676358"))
    })?;
    // aarch64-linux-android -> aarch64-linux-android (dir del NDK)
    let abi = target
        .split('-')
        .take(3)
        .collect::<Vec<_>>()
        .join("-");
    let dir = format!("{ndk}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/{abi}");
    std::path::Path::new(&format!("{dir}/libc++_shared.so"))
        .exists()
        .then_some(dir)
}
