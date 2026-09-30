mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
//! MoneyNeedle core — lógica compartida (Rust + Flutter vía FFI).
//!
//! - `parse`: port de `prototype/mn_parse.py` (montos, categorías, moneda).
//! - Modelos + validación pura, cero deps para que `cargo test` corra.
//! - Futuro: rusqlite (persistencia), needle-bridge (C API .cact),
//!   stt-bridge (sherpa-onnx).

pub mod parse;
pub mod needle_bridge;
pub mod pipeline;
pub mod api;

#[derive(Debug, Clone, PartialEq)]
pub enum TipoMovimiento {
    Gasto,
    Ingreso,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Transaction {
    pub tipo: TipoMovimiento,
    pub monto: f64,
    pub moneda: String,
    pub categoria: String,
    pub descripcion: String,
    pub fecha: String, // YYYY-MM-DD
}

impl Transaction {
    pub fn validate(&self) -> Result<(), String> {
        if self.monto <= 0.0 {
            return Err("monto debe ser > 0".into());
        }
        if self.categoria.trim().is_empty() {
            return Err("categoria requerida".into());
        }
        if self.fecha.len() != 10 {
            return Err("fecha debe ser YYYY-MM-DD".into());
        }
        Ok(())
    }
}

/// Decisión de ruteo según confidence de Needle 3.
/// LoRA local deja confidence en None -> siempre confirmar.
#[derive(Debug, Clone, PartialEq)]
pub enum Routing {
    AutoAccept,
    AskConfirm,
    AskClarify,
}

pub fn route_by_confidence(confidence: Option<f32>) -> Routing {
    match confidence {
        Some(c) if c >= 0.8 => Routing::AutoAccept,
        Some(c) if c >= 0.5 => Routing::AskConfirm,
        _ => Routing::AskClarify,
    }
}

/// MVP: siempre confirmar, aunque el score diga auto.
pub fn should_autoload(routing: &Routing) -> bool {
    let _ = routing;
    false // Fase 0: confirmación humana obligatoria
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Transaction {
        Transaction {
            tipo: TipoMovimiento::Gasto,
            monto: 5000.0,
            moneda: "ARS".into(),
            categoria: "supermercado".into(),
            descripcion: "súper".into(),
            fecha: "2026-09-28".into(),
        }
    }

    #[test]
    fn valid_transaction_passes() {
        assert!(sample().validate().is_ok());
    }

    #[test]
    fn zero_amount_fails() {
        let mut t = sample();
        t.monto = 0.0;
        assert!(t.validate().is_err());
    }

    #[test]
    fn routing_thresholds() {
        assert_eq!(route_by_confidence(Some(0.9)), Routing::AutoAccept);
        assert_eq!(route_by_confidence(Some(0.6)), Routing::AskConfirm);
        assert_eq!(route_by_confidence(Some(0.2)), Routing::AskClarify);
        assert_eq!(route_by_confidence(None), Routing::AskClarify);
    }

    #[test]
    fn mvp_never_autoloads() {
        assert!(!should_autoload(&Routing::AutoAccept));
    }
}
