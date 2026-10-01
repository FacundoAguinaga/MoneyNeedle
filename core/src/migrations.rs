//! Sistema de migraciones versionadas del esquema SQLite con soporte de backup físico previo.

use rusqlite::Connection;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

pub const SCHEMA_VERSION: u32 = 2;

/// Migración SQL inicial (v1): Modelo relacional completo para MoneyNeedle.
pub const MIGRATION_V1: &str = r#"
-- Cuentas / Billeteras
CREATE TABLE IF NOT EXISTS accounts (
    id BLOB PRIMARY KEY, -- UUID v7 (16 bytes)
    name TEXT NOT NULL,
    account_type TEXT NOT NULL CHECK (account_type IN ('cash', 'bank', 'wallet', 'credit_card', 'investment')),
    currency TEXT NOT NULL, -- Código ISO 4217 (ARS, USD, EUR)
    initial_balance INTEGER NOT NULL DEFAULT 0, -- en centavos
    color TEXT NOT NULL DEFAULT '#4CAF50',
    icon TEXT NOT NULL DEFAULT 'account_balance_wallet',
    -- Campos para tarjetas de crédito
    credit_limit INTEGER, -- en centavos (NULL si no es tarjeta)
    closing_day INTEGER CHECK (closing_day IS NULL OR (closing_day BETWEEN 1 AND 31)),
    due_day INTEGER CHECK (due_day IS NULL OR (due_day BETWEEN 1 AND 31)),
    created_at INTEGER NOT NULL, -- unix ms
    updated_at INTEGER NOT NULL, -- unix ms
    deleted_at INTEGER           -- soft delete unix ms
);

-- Categorías dinámicas
CREATE TABLE IF NOT EXISTS categories (
    id BLOB PRIMARY KEY, -- UUID v7
    name TEXT NOT NULL,
    icon TEXT NOT NULL DEFAULT 'category',
    color TEXT NOT NULL DEFAULT '#757575',
    parent_id BLOB REFERENCES categories(id) ON DELETE SET NULL,
    is_system INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER
);

-- Reglas de movimientos recurrentes
CREATE TABLE IF NOT EXISTS recurring_rules (
    id BLOB PRIMARY KEY, -- UUID v7
    account_id BLOB NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    category_id BLOB REFERENCES categories(id) ON DELETE SET NULL,
    transaction_type TEXT NOT NULL CHECK (transaction_type IN ('expense', 'income', 'transfer')),
    amount INTEGER NOT NULL CHECK (amount > 0),
    currency TEXT NOT NULL,
    destination_account_id BLOB REFERENCES accounts(id) ON DELETE SET NULL,
    frequency TEXT NOT NULL CHECK (frequency IN ('daily', 'weekly', 'monthly', 'yearly')),
    day_of_month INTEGER CHECK (day_of_month IS NULL OR (day_of_month BETWEEN 1 AND 31)),
    day_of_week INTEGER CHECK (day_of_week IS NULL OR (day_of_week BETWEEN 1 AND 7)),
    start_date INTEGER NOT NULL,
    end_date INTEGER,
    auto_apply INTEGER NOT NULL DEFAULT 0,
    last_processed_date INTEGER,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER
);

-- Transacciones principales
CREATE TABLE IF NOT EXISTS transactions (
    id BLOB PRIMARY KEY, -- UUID v7
    account_id BLOB NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    category_id BLOB REFERENCES categories(id) ON DELETE SET NULL,
    transaction_type TEXT NOT NULL CHECK (transaction_type IN ('expense', 'income', 'transfer')),
    amount INTEGER NOT NULL CHECK (amount > 0), -- en centavos
    currency TEXT NOT NULL,
    destination_account_id BLOB REFERENCES accounts(id) ON DELETE SET NULL,
    destination_amount INTEGER CHECK (destination_amount IS NULL OR destination_amount > 0),
    exchange_rate_snapshot INTEGER, -- tasa a moneda principal escalada a 1e8
    notes TEXT NOT NULL DEFAULT '',
    date INTEGER NOT NULL, -- fecha efectiva unix ms
    raw_prompt TEXT NOT NULL DEFAULT '', -- frase original de la IA
    recurring_rule_id BLOB REFERENCES recurring_rules(id) ON DELETE SET NULL,
    scheduled_date INTEGER, -- fecha teórica programada para idempotencia
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER,
    UNIQUE(recurring_rule_id, scheduled_date)
);

CREATE INDEX IF NOT EXISTS idx_transactions_account ON transactions(account_id);
CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions(date);
CREATE INDEX IF NOT EXISTS idx_transactions_deleted ON transactions(deleted_at);

-- Cuotas de compras con tarjeta de crédito
CREATE TABLE IF NOT EXISTS installments (
    id BLOB PRIMARY KEY, -- UUID v7
    transaction_id BLOB NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    account_id BLOB NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    installment_number INTEGER NOT NULL CHECK (installment_number > 0),
    total_installments INTEGER NOT NULL CHECK (total_installments > 0),
    amount INTEGER NOT NULL CHECK (amount > 0), -- monto específico de esta cuota
    cycle_year INTEGER NOT NULL,
    cycle_month INTEGER NOT NULL CHECK (cycle_month BETWEEN 1 AND 12),
    due_date INTEGER NOT NULL, -- unix ms
    status TEXT NOT NULL CHECK (status IN ('pending', 'billed', 'paid')),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER
);

CREATE INDEX IF NOT EXISTS idx_installments_account_cycle ON installments(account_id, cycle_year, cycle_month);

-- Cotizaciones de cambio
CREATE TABLE IF NOT EXISTS exchange_rates (
    id BLOB PRIMARY KEY, -- UUID v7
    base_currency TEXT NOT NULL,
    quote_currency TEXT NOT NULL,
    rate INTEGER NOT NULL CHECK (rate > 0), -- multiplicado por 1e8
    timestamp INTEGER NOT NULL, -- unix ms
    source TEXT NOT NULL CHECK (source IN ('manual', 'implicit_transfer', 'external_api')),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER
);

CREATE INDEX IF NOT EXISTS idx_exchange_rates_pair ON exchange_rates(base_currency, quote_currency, timestamp DESC);
"#;

/// Migración SQL v2: Presupuestos por categoría y Metas de ahorro (Fase 5).
pub const MIGRATION_V2: &str = r#"
-- Presupuestos mensuales por categoría
CREATE TABLE IF NOT EXISTS budgets (
    id BLOB PRIMARY KEY, -- UUID v7 (16 bytes)
    category_id BLOB NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
    currency TEXT NOT NULL,
    amount INTEGER NOT NULL CHECK (amount > 0), -- monto límite mensual en centavos
    alert_percentage INTEGER NOT NULL DEFAULT 80 CHECK (alert_percentage BETWEEN 1 AND 100),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER
);

CREATE INDEX IF NOT EXISTS idx_budgets_category ON budgets(category_id);

-- Metas de ahorro
CREATE TABLE IF NOT EXISTS saving_goals (
    id BLOB PRIMARY KEY, -- UUID v7 (16 bytes)
    name TEXT NOT NULL,
    target_amount INTEGER NOT NULL CHECK (target_amount > 0), -- en centavos
    currency TEXT NOT NULL,
    target_date INTEGER, -- unix ms opcional
    color TEXT NOT NULL DEFAULT '#2196F3',
    icon TEXT NOT NULL DEFAULT 'flag',
    current_amount INTEGER NOT NULL DEFAULT 0, -- centavos acumulados
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'paused')),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER
);

CREATE INDEX IF NOT EXISTS idx_saving_goals_status ON saving_goals(status);
"#;

/// Obtiene la versión actual del esquema de la base de datos.
pub fn get_user_version(conn: &Connection) -> Result<u32, String> {
    let mut stmt = conn
        .prepare("PRAGMA user_version;")
        .map_err(|e| e.to_string())?;
    let version = stmt
        .query_row([], |row| row.get(0))
        .map_err(|e| e.to_string())?;
    Ok(version)
}

/// Establece la versión del esquema.
pub fn set_user_version(conn: &Connection, version: u32) -> Result<(), String> {
    conn.execute(&format!("PRAGMA user_version = {};", version), [])
        .map_err(|e| e.to_string())?;
    Ok(())
}

/// Realiza una copia de seguridad física del archivo de base de datos antes de migrar.
pub fn backup_database_file(db_path: &str) -> std::io::Result<Option<PathBuf>> {
    if db_path == ":memory:" || db_path.is_empty() {
        return Ok(None);
    }
    let p = Path::new(db_path);
    if !p.exists() {
        return Ok(None);
    }

    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis();
    let bak_path = p.with_extension(format!("bak_{}", timestamp));
    fs::copy(p, &bak_path)?;
    Ok(Some(bak_path))
}

/// Aplica todas las migraciones pendientes dentro de una transacción.
pub fn run_migrations(conn: &mut Connection) -> Result<(), String> {
    conn.execute("PRAGMA foreign_keys = ON;", [])
        .map_err(|e| e.to_string())?;

    let current_version = get_user_version(conn)?;
    if current_version >= SCHEMA_VERSION {
        return Ok(());
    }

    let tx = conn.transaction().map_err(|e| e.to_string())?;

    if current_version < 1 {
        tx.execute_batch(MIGRATION_V1).map_err(|e| e.to_string())?;
    }
    if current_version < 2 {
        tx.execute_batch(MIGRATION_V2).map_err(|e| e.to_string())?;
    }

    tx.commit().map_err(|e| e.to_string())?;
    set_user_version(conn, SCHEMA_VERSION)?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_migrations_fresh_db() {
        let mut conn = Connection::open_in_memory().unwrap();
        assert_eq!(get_user_version(&conn).unwrap(), 0);

        run_migrations(&mut conn).unwrap();
        assert_eq!(get_user_version(&conn).unwrap(), 2);

        // Correrlas de nuevo no debería fallar ni alterar versión
        run_migrations(&mut conn).unwrap();
        assert_eq!(get_user_version(&conn).unwrap(), 2);
    }

    #[test]
    fn test_migration_incremental_v1_to_v2() {
        let mut conn = Connection::open_in_memory().unwrap();
        // Simular base que ya estaba en v1
        conn.execute_batch(MIGRATION_V1).unwrap();
        set_user_version(&conn, 1).unwrap();
        assert_eq!(get_user_version(&conn).unwrap(), 1);

        // Ejecutar migración: debe aplicar solo v2 y actualizar versión a 2
        run_migrations(&mut conn).unwrap();
        assert_eq!(get_user_version(&conn).unwrap(), 2);

        // Verificar que las nuevas tablas existen
        let budget_count: i64 = conn.query_row("SELECT count(*) FROM budgets", [], |r| r.get(0)).unwrap();
        assert_eq!(budget_count, 0);
        let goals_count: i64 = conn.query_row("SELECT count(*) FROM saving_goals", [], |r| r.get(0)).unwrap();
        assert_eq!(goals_count, 0);
    }

    #[test]
    fn test_backup_non_existent_file() {
        let res = backup_database_file("/tmp/non_existent_moneyneedle_test.db").unwrap();
        assert!(res.is_none());
    }
}
