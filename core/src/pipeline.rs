//! Pipeline público que Flutter va a llamar: `propose(frase) -> Proposal`.
//!
//! Encadena `for_model` → inferencia → `extract_call` → grounding →
//! keywords → moneda. La inferencia se inyecta como función para testear
//! sin GPU (`Ok(String)` = envelope JSON crudo del engine).
use crate::parse::{detect_currency, for_model, keyword_category, numbers_in_query};
use crate::{TipoMovimiento, Transaction};

/// Propuesta lista para mostrar en la tarjeta de confirmación.
#[derive(Debug, Clone, PartialEq)]
pub struct Proposal {
    pub transaction: Transaction,
    /// `false` = el monto no aparece en la frase (posible alucinación).
    pub grounded: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub enum ProposeError {
    /// El engine no devolvió ninguna llamada.
    NoCall,
    /// El envelope no es JSON válido.
    BadEnvelope(String),
    /// `tipo` desconocido (ni gasto ni ingreso).
    BadType(String),
}

fn parse_tipo(s: &str) -> Result<TipoMovimiento, ProposeError> {
    match s {
        "gasto" => Ok(TipoMovimiento::Gasto),
        "ingreso" => Ok(TipoMovimiento::Ingreso),
        other => Err(ProposeError::BadType(other.to_string())),
    }
}

/// Extrae el primer call de `function_calls`, si no de `suppressed_calls`.
/// Devuelve (nombre_tool, argumentos).
fn extract_call(envelope: &serde_json::Value) -> Option<(&str, &serde_json::Value)> {
    for key in ["function_calls", "suppressed_calls"] {
        if let Some(calls) = envelope.get(key).and_then(|v| v.as_array()) {
            if let Some(first) = calls.first() {
                let name = first.get("name")?.as_str()?;
                let args = first.get("arguments")?;
                return Some((name, args));
            }
        }
    }
    None
}

/// Pipeline completo. `infer` es la inferencia (engine real o mock en tests).
/// `fecha_hoy` es `YYYY-MM-DD` (la pone la app, nunca el modelo).
pub fn propose(
    query: &str,
    fecha_hoy: &str,
    infer: impl Fn(&str) -> Result<String, String>,
) -> Result<Proposal, ProposeError> {
    let envelope: serde_json::Value =
        serde_json::from_str(&infer(&for_model(query)).map_err(ProposeError::BadEnvelope)?)
            .map_err(|e| ProposeError::BadEnvelope(e.to_string()))?;
    let (name, args) = extract_call(&envelope).ok_or(ProposeError::NoCall)?;

    let mut tipo_s = args.get("tipo").and_then(|v| v.as_str()).unwrap_or("").to_string();
    if name == "add_gasto" {
        tipo_s = "gasto".into();
    } else if name == "add_ingreso" {
        tipo_s = "ingreso".into();
    }
    let tipo = parse_tipo(&tipo_s)?;
    let monto = args.get("monto").and_then(|v| v.as_f64()).unwrap_or(-1.0);
    let mut categoria = args.get("categoria").and_then(|v| v.as_str()).unwrap_or("otros").to_string();

    let grounded = numbers_in_query(query).iter().any(|n| (monto - n).abs() < 0.01);
    if let Some(sug) = keyword_category(query) {
        categoria = sug.to_string(); // la regla manda hasta el finetune
    }

    Ok(Proposal {
        transaction: Transaction {
            tipo,
            monto,
            moneda: detect_currency(query).to_string(),
            categoria,
            descripcion: query.to_string(),
            fecha: fecha_hoy.to_string(),
        },
        grounded,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn env_with(args_json: &str) -> String {
        format!(r#"{{"function_calls": [], "suppressed_calls": [{{"name": "add_transaction", "arguments": {args_json}}}]}}"#)
    }

    fn mock(json: String) -> impl Fn(&str) -> Result<String, String> {
        move |_| Ok(json.clone())
    }

    #[test]
    fn propone_caso_feliz() {
        let p = propose(
            "gasté 5000 en supermercado",
            "2026-09-30",
            mock(env_with(r#"{"tipo":"gasto","monto":5000,"categoria":"supermercado"}"#)),
        )
        .unwrap();
        assert_eq!(p.transaction.tipo, TipoMovimiento::Gasto);
        assert_eq!(p.transaction.monto, 5000.0);
        assert_eq!(p.transaction.categoria, "supermercado");
        assert!(p.grounded);
    }

    #[test]
    fn keyword_pisa_categoria_y_moneda_usd() {
        let p = propose(
            "compre un perfume de 100 usd",
            "2026-09-30",
            mock(env_with(r#"{"tipo":"gasto","monto":100,"categoria":"supermercado"}"#)),
        )
        .unwrap();
        assert_eq!(p.transaction.categoria, "otros");
        assert_eq!(p.transaction.moneda, "USD");
        assert!(p.grounded);
    }

    #[test]
    fn no_grounded_no_descarta() {
        let p = propose(
            "pague mil en impuestos",
            "2026-09-30",
            mock(env_with(r#"{"tipo":"gasto","monto":200000,"categoria":"servicios"}"#)),
        )
        .unwrap();
        assert!(!p.grounded); // la UI avisa, no se auto-carga
    }

    #[test]
    fn sin_llamadas_es_error() {
        let err = propose(
            "hola qué hora es",
            "2026-09-30",
            mock(r#"{"function_calls": [], "suppressed_calls": []}"#.into()),
        )
        .unwrap_err();
        assert_eq!(err, ProposeError::NoCall);
    }

    #[test]
    fn envelope_roto_es_error() {
        let err = propose("taxi 8000", "2026-09-30", mock("esto no es json".into())).unwrap_err();
        assert!(matches!(err, ProposeError::BadEnvelope(_)));
    }

    #[test]
    fn tipo_implicado_por_tool() {
        let json = r#"{"function_calls": [{"name": "add_ingreso", "arguments": {"monto": 200000, "categoria": "sueldo"}}], "suppressed_calls": []}"#;
        let p = propose("me pagaron 200k", "2026-09-30", mock(json.into())).unwrap();
        assert_eq!(p.transaction.tipo, TipoMovimiento::Ingreso);
        assert!(p.grounded);
    }
}
