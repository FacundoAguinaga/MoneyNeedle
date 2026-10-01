//! API pública para Flutter vía flutter_rust_bridge.
//!
//! - `propose_mocked`: pipeline con inferencia falsa (prueba el cableado
//!   Dart↔Rust sin modelo ni GPU).
//! - `propose_real`: pipeline con el engine Cactus (carga el .cact una vez,
//!   el engine es process-global y NO thread-safe: todo va bajo un Mutex).
//!
//! Los DTOs usan tipos simples (String/f64/bool) para un binding estable.
use std::sync::{Mutex, OnceLock};

use crate::{needle_bridge, pipeline, store, TipoMovimiento};

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

/// Movimiento guardado, listo para la lista de la UI.
#[derive(Debug, Clone)]
pub struct MovementDto {
    pub id: String,
    pub tipo: String,
    pub monto: f64,
    pub moneda: String,
    pub categoria: String,
    pub descripcion: String,
    pub fecha: String,
}

impl From<store::Movement> for MovementDto {
    fn from(m: store::Movement) -> Self {
        MovementDto {
            id: m.id,
            tipo: m.tipo,
            monto: m.monto,
            moneda: m.moneda,
            categoria: m.categoria,
            descripcion: m.descripcion,
            fecha: m.fecha,
        }
    }
}

/// Inicializa la base de datos con clave SQLCipher opcional (hex crudo).
pub fn init_database(db_path: String, raw_key_hex: Option<String>) -> anyhow::Result<bool> {
    let zero_key = raw_key_hex.map(zeroize::Zeroizing::new);
    let _conn = store::open(&db_path, zero_key.as_ref())
        .map_err(|e| anyhow::anyhow!("init_database: {e}"))?;
    Ok(true)
}

/// Guarda la propuesta confirmada. `db_path` = archivo SQLite en la app.
#[allow(clippy::too_many_arguments)]
pub fn confirm_movement(
    db_path: String,
    tipo: String,
    monto: f64,
    moneda: String,
    categoria: String,
    descripcion: String,
    fecha: String,
    frase: String,
) -> anyhow::Result<String> {
    let t = match tipo.as_str() {
        "gasto" => TipoMovimiento::Gasto,
        "ingreso" => TipoMovimiento::Ingreso,
        other => anyhow::bail!("tipo inválido: {other}"),
    };
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    store::insert(&conn, &t, monto, &moneda, &categoria, &descripcion, &fecha, &frase)
        .map_err(|e| anyhow::anyhow!("{e}"))
}

/// DTO con los datos de creación inicial del vault.
#[derive(Debug, Clone)]
pub struct VaultInitDto {
    pub raw_master_key_hex: String,
    pub recovery_phrase: String,
    pub wrapped_recovery_payload: String,
}

impl From<crate::vault::VaultInitResult> for VaultInitDto {
    fn from(v: crate::vault::VaultInitResult) -> Self {
        VaultInitDto {
            raw_master_key_hex: v.raw_master_key_hex,
            recovery_phrase: v.recovery_phrase,
            wrapped_recovery_payload: v.wrapped_recovery_payload,
        }
    }
}

/// Genera una nueva Master Key aleatoria y la envuelve con 12 palabras BIP-39.
pub fn create_vault(custom_passphrase: Option<String>) -> anyhow::Result<VaultInitDto> {
    crate::vault::create_vault(custom_passphrase.as_deref())
        .map(VaultInitDto::from)
        .map_err(|e| anyhow::anyhow!("{e}"))
}

/// Desenvuelve la Master Key a partir del payload y la frase de recuperación.
pub fn recover_master_key(
    wrapped_recovery_payload: String,
    recovery_phrase: String,
) -> anyhow::Result<String> {
    crate::vault::recover_master_key(&wrapped_recovery_payload, &recovery_phrase)
        .map(|z| (*z).clone())
        .map_err(|e| anyhow::anyhow!("{e}"))
}

/// Últimos movimientos para la lista.
pub fn list_movements(db_path: String, limit: i64) -> anyhow::Result<Vec<MovementDto>> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    Ok(store::list(&conn, limit)
        .map_err(|e| anyhow::anyhow!("{e}"))?
        .into_iter()
        .map(MovementDto::from)
        .collect())
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
