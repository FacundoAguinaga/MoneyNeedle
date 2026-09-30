//! API pública para Flutter vía flutter_rust_bridge.
//!
//! - `propose_mocked`: pipeline con inferencia falsa (prueba el cableado
//!   Dart↔Rust sin modelo ni GPU).
//! - `propose_real`: pipeline con el engine Cactus (carga el .cact una vez,
//!   el engine es process-global y NO thread-safe: todo va bajo un Mutex).
//!
//! Los DTOs usan tipos simples (String/f64/bool) para un binding estable.
use std::sync::{Mutex, OnceLock};

use crate::{needle_bridge, pipeline, TipoMovimiento};

/// Lo que Flutter muestra en la tarjeta de confirmación.
#[derive(Debug, Clone)]
pub struct ProposalDto {
    pub tipo: String,
    pub monto: f64,
    pub categoria: String,
    pub moneda: String,
    pub fecha: String,
    pub grounded: bool,
}

impl From<pipeline::Proposal> for ProposalDto {
    fn from(p: pipeline::Proposal) -> Self {
        let tipo = match p.transaction.tipo {
            TipoMovimiento::Gasto => "gasto".to_string(),
            TipoMovimiento::Ingreso => "ingreso".to_string(),
        };
        ProposalDto {
            tipo,
            monto: p.transaction.monto,
            categoria: p.transaction.categoria,
            moneda: p.transaction.moneda,
            fecha: p.transaction.fecha,
            grounded: p.grounded,
        }
    }
}

const TOOLS: &str = r#"[{"name":"add_transaction","description":"Movimiento de finanzas en español. k=miles (200k=200000). luca=mil (5 lucas=5000). mil solo=1000. Fecha y moneda las pone la app.","parameters":{"type":"object","properties":{"tipo":{"type":"string","enum":["gasto","ingreso"]},"monto":{"type":"number"},"categoria":{"type":"string","enum":["supermercado","transporte","comida","alquiler","sueldo","servicios","salud","otros"]}},"required":["tipo","monto","categoria"]}}]"#;

/// Pipeline con inferencia mockeada: verifica el cableado sin modelo.
pub fn propose_mocked(query: String, fecha_hoy: String) -> ProposalDto {
    let fake = r#"{"function_calls": [{"name": "add_transaction", "arguments": {"tipo": "gasto", "monto": 5000, "categoria": "supermercado"}}], "suppressed_calls": []}"#.to_string();
    pipeline::propose(&query, &fecha_hoy, |_| Ok(fake.clone()))
        .map(ProposalDto::from)
        .unwrap_or(ProposalDto {
            tipo: "gasto".to_string(),
            monto: -1.0,
            categoria: "otros".to_string(),
            moneda: "ARS".to_string(),
            fecha: fecha_hoy,
            grounded: false,
        })
}

struct Engine {
    loaded_path: Option<String>,
}

static ENGINE: OnceLock<Mutex<Engine>> = OnceLock::new();

fn engine() -> &'static Mutex<Engine> {
    ENGINE.get_or_init(|| Mutex::new(Engine { loaded_path: None }))
}

/// Pipeline con el engine real. `cact_path` = asset desempaquetado en device.
pub fn propose_real(
    query: String,
    fecha_hoy: String,
    cact_path: String,
) -> anyhow::Result<ProposalDto> {
    let mut eng = engine()
        .lock()
        .map_err(|_| anyhow::anyhow!("engine lock envenenado"))?;
    if eng.loaded_path.as_deref() != Some(&cact_path) {
        let cact = std::fs::read(&cact_path)
            .map_err(|e| anyhow::anyhow!("no se pudo leer el .cact: {e}"))?;
        needle_bridge::load(&cact).map_err(|e| anyhow::anyhow!("needle_load: {e}"))?;
        needle_bridge::init(None, TOOLS).map_err(|e| anyhow::anyhow!("needle_init: {e}"))?;
        eng.loaded_path = Some(cact_path);
    }
    needle_bridge::reset();
    let proposal =
        pipeline::propose(&query, &fecha_hoy, |q| needle_bridge::complete(q, 1024))
            .map_err(|e| anyhow::anyhow!("propose: {e:?}"))?;
    Ok(ProposalDto::from(proposal))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mocked_propone_sin_engine() {
        let p = propose_mocked("cualquier frase".into(), "2026-09-30".into());
        assert_eq!(p.tipo, "gasto");
        assert_eq!(p.monto, 5000.0);
    }
}
