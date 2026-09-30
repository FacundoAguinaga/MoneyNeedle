//! Smoke test del bridge FFI: carga un .cact, declara el tool de finanzas
//! y corre una frase. Uso:
//! NEEDLE_LIB_DIR=/tmp/needle-device NEEDLE_CXX_DIR=~/Android/Sdk/emulator/lib64 \
//!   cargo run --example needle_smoke --features needle-engine -- \
//!   prototype/data/tuned2.cact "gasté 5000 en súper"
//! (NEEDLE_CXX_DIR = dir con libc++.so si no hay libc++ del sistema;
//!  en runtime exportar LD_LIBRARY_PATH a ese mismo dir.)
use moneyneedle_core::needle_bridge;

const TOOLS: &str = r#"[{"name":"add_transaction","description":"Movimiento de finanzas en español. k=miles (200k=200000). luca=mil (5 lucas=5000). mil solo=1000. Fecha y moneda las pone la app.","parameters":{"type":"object","properties":{"tipo":{"type":"string","enum":["gasto","ingreso"]},"monto":{"type":"number"},"categoria":{"type":"string","enum":["supermercado","transporte","comida","alquiler","sueldo","servicios","salud","otros"]}},"required":["tipo","monto","categoria"]}}]"#;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        eprintln!("uso: needle_smoke <tuned.cact> <frase>");
        std::process::exit(2);
    }
    let cact = std::fs::read(&args[1]).expect("no se pudo leer el .cact");
    needle_bridge::load(&cact).expect("needle_load falló");
    let prefix = needle_bridge::init(None, TOOLS).expect("needle_init falló");
    println!("prefijo: {prefix} tokens");
    needle_bridge::reset();
    match needle_bridge::complete(&args[2], 1024) {
        Ok(json) => println!("{json}"),
        Err(e) => {
            eprintln!("complete falló: {e}");
            std::process::exit(1);
        }
    }
}
