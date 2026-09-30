//! Prueba interactiva del pipeline: propose() con el engine real.
//! Uso:
//! NEEDLE_LIB_DIR=/tmp/needle-device NEEDLE_CXX_DIR=~/Android/Sdk/emulator/lib64 \
//!   cargo run --example pipeline_probe --features needle-engine -- \
//!   prototype/data/tuned2.cact "gasté 5000 en súper"
//! (En runtime exportar LD_LIBRARY_PATH al NEEDLE_CXX_DIR.)
use moneyneedle_core::{needle_bridge, pipeline};

const TOOLS: &str = r#"[{"name":"add_transaction","description":"Movimiento de finanzas en español. k=miles (200k=200000). luca=mil (5 lucas=5000). mil solo=1000. Fecha y moneda las pone la app.","parameters":{"type":"object","properties":{"tipo":{"type":"string","enum":["gasto","ingreso"]},"monto":{"type":"number"},"categoria":{"type":"string","enum":["supermercado","transporte","comida","alquiler","sueldo","servicios","salud","otros"]}},"required":["tipo","monto","categoria"]}}]"#;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let cact = std::fs::read(&args[1]).expect("cact");
    needle_bridge::load(&cact).expect("load");
    needle_bridge::init(None, TOOLS).expect("init");
    needle_bridge::reset();
    let p = pipeline::propose(&args[2], "2026-09-30", |q| needle_bridge::complete(q, 1024))
        .expect("propose");
    println!("{p:?}");
}
