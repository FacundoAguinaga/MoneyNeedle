//! Persistencia SQLite (rusqlite bundled, sin dependencias del sistema).
//!
//! Una tabla `movements` con lo que la UI necesita. Correcciones para
//! reentrenar se exportan con [`export_corrections_jsonl`] en el formato
//! que `make_dataset.py` ya entiende.
use rusqlite::{params, Connection};

use crate::TipoMovimiento;

/// Fila lista para la UI / FRB (tipos simples).
#[derive(Debug, Clone, PartialEq)]
pub struct Movement {
    pub id: i64,
    pub tipo: String, // "gasto" | "ingreso"
    pub monto: f64,
    pub moneda: String,
    pub categoria: String,
    pub descripcion: String,
    pub fecha: String, // YYYY-MM-DD
}

/// Abre (o crea) la DB y aplica el schema. `path` = dir de la app.
pub fn open(db_path: &str) -> Result<Connection, String> {
    let conn = Connection::open(db_path).map_err(|e| e.to_string())?;
    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS movements (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tipo TEXT NOT NULL CHECK (tipo IN ('gasto','ingreso')),
            monto REAL NOT NULL CHECK (monto > 0),
            moneda TEXT NOT NULL DEFAULT 'ARS',
            categoria TEXT NOT NULL,
            descripcion TEXT NOT NULL DEFAULT '',
            fecha TEXT NOT NULL,
            frase TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        CREATE INDEX IF NOT EXISTS idx_movements_fecha ON movements(fecha);",
    )
    .map_err(|e| e.to_string())?;
    Ok(conn)
}

pub fn tipo_str(t: &TipoMovimiento) -> &'static str {
    match t {
        TipoMovimiento::Gasto => "gasto",
        TipoMovimiento::Ingreso => "ingreso",
    }
}

/// Guarda un movimiento confirmado. Devuelve el id.
#[allow(clippy::too_many_arguments)]
pub fn insert(
    conn: &Connection,
    tipo: &TipoMovimiento,
    monto: f64,
    moneda: &str,
    categoria: &str,
    descripcion: &str,
    fecha: &str,
    frase: &str,
) -> Result<i64, String> {
    if monto <= 0.0 {
        return Err("monto debe ser > 0".into());
    }
    if fecha.len() != 10 {
        return Err("fecha debe ser YYYY-MM-DD".into());
    }
    conn.execute(
        "INSERT INTO movements (tipo, monto, moneda, categoria, descripcion, fecha, frase)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        params![tipo_str(tipo), monto, moneda, categoria, descripcion, fecha, frase],
    )
    .map_err(|e| e.to_string())?;
    Ok(conn.last_insert_rowid())
}

/// Últimos N movimientos (más recientes primero).
pub fn list(conn: &Connection, limit: i64) -> Result<Vec<Movement>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT id, tipo, monto, moneda, categoria, descripcion, fecha
             FROM movements ORDER BY id DESC LIMIT ?1",
        )
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map(params![limit], |row| {
            Ok(Movement {
                id: row.get(0)?,
                tipo: row.get(1)?,
                monto: row.get(2)?,
                moneda: row.get(3)?,
                categoria: row.get(4)?,
                descripcion: row.get(5)?,
                fecha: row.get(6)?,
            })
        })
        .map_err(|e| e.to_string())?;
    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| e.to_string())?);
    }
    Ok(out)
}

/// Totales por moneda: (moneda, gastos, ingresos).
pub fn balance(conn: &Connection) -> Result<Vec<(String, f64, f64)>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT moneda,
                    SUM(CASE WHEN tipo='gasto' THEN monto ELSE 0 END),
                    SUM(CASE WHEN tipo='ingreso' THEN monto ELSE 0 END)
             FROM movements GROUP BY moneda",
        )
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, Option<f64>>(1)?.unwrap_or(0.0),
                row.get::<_, Option<f64>>(2)?.unwrap_or(0.0),
            ))
        })
        .map_err(|e| e.to_string())?;
    let mut out: Vec<(String, f64, f64)> = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| e.to_string())?);
    }
    Ok(out)
}

/// Exporta todo como JSONL de correcciones (formato make_dataset.py).
/// Cada línea: {"query": frase, "answers": [{...}], "reasoning": "app ..."}.
/// `tools_json` se incrusta tal cual (el caller lo lee de tools.json).
pub fn export_corrections_jsonl(conn: &Connection, tools_json: &str) -> Result<String, String> {
    let mut stmt = conn
        .prepare("SELECT tipo, monto, categoria, frase, fecha FROM movements ORDER BY id")
        .map_err(|e| e.to_string())?;
    let rows = stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, f64>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
                row.get::<_, String>(4)?,
            ))
        })
        .map_err(|e| e.to_string())?;
    let mut out = String::new();
    for r in rows {
        let (tipo, monto, categoria, frase, fecha) = r.map_err(|e| e.to_string())?;
        let esc = |s: &str| s.replace('\\', "\\\\").replace('"', "\\\"");
        out.push_str(&format!(
            "{{\"query\": \"{}\", \"tools\": {}, \"answers\": [{{\"name\": \"add_transaction\", \"arguments\": {{\"tipo\": \"{}\", \"monto\": {}, \"categoria\": \"{}\"}}}}], \"reasoning\": \"app {}\"}}\n",
            esc(&frase),
            tools_json,
            tipo,
            monto,
            esc(&categoria),
            fecha,
        ));
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::TipoMovimiento::{Gasto, Ingreso};

    fn mem() -> Connection {
        open(":memory:").unwrap()
    }

    #[test]
    fn insert_y_list() {
        let c = mem();
        let id = insert(&c, &Gasto, 5000.0, "ARS", "supermercado", "súper", "2026-09-30", "gasté 5000").unwrap();
        assert_eq!(id, 1);
        insert(&c, &Ingreso, 200000.0, "ARS", "sueldo", "", "2026-09-30", "sueldo").unwrap();
        let all = list(&c, 10).unwrap();
        assert_eq!(all.len(), 2);
        assert_eq!(all[0].tipo, "ingreso"); // más reciente primero
        assert_eq!(all[1].monto, 5000.0);
    }

    #[test]
    fn valida_monto_y_fecha() {
        let c = mem();
        assert!(insert(&c, &Gasto, 0.0, "ARS", "x", "", "2026-09-30", "q").is_err());
        assert!(insert(&c, &Gasto, 10.0, "ARS", "x", "", "30/09", "q").is_err());
        assert!(insert(&c, &Gasto, 10.0, "ARS", "x", "", "2026-09-30", "q").is_ok());
    }

    #[test]
    fn balance_por_moneda() {
        let c = mem();
        insert(&c, &Gasto, 5000.0, "ARS", "s", "", "2026-09-30", "q1").unwrap();
        insert(&c, &Ingreso, 200000.0, "ARS", "s", "", "2026-09-30", "q2").unwrap();
        insert(&c, &Gasto, 100.0, "USD", "o", "", "2026-09-30", "q3").unwrap();
        let mut b = balance(&c).unwrap();
        b.sort_by(|a, b| a.0.cmp(&b.0));
        assert_eq!(b.len(), 2);
        assert_eq!(b[0].0, "ARS");
        assert!((b[0].1 - 5000.0).abs() < 0.01 && (b[0].2 - 200000.0).abs() < 0.01);
        assert_eq!(b[1].0, "USD");
        assert!((b[1].1 - 100.0).abs() < 0.01 && b[1].2.abs() < 0.01);
    }

    #[test]
    fn export_jsonl_parseable() {
        let c = mem();
        insert(&c, &Gasto, 5000.0, "ARS", "supermercado", "", "2026-09-30", "gasté \"5\" lucas").unwrap();
        let out = export_corrections_jsonl(&c, "[]").unwrap();
        assert!(out.contains("\"query\""));
        assert!(out.contains("\\\"5\\\"")); // comillas escapadas
    }
}
