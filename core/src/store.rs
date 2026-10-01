//! Persistencia SQLite protegida con SQLCipher y modelo relacional completo.
//!
//! Soporta cuentas, categorías dinámicas, transferencias multimoneda,
//! compras en cuotas con tarjeta de crédito, reglas recurrentes idempotentes
//! y exportación para reentrenamiento de Cactus Needle.

use rusqlite::{params, Connection, OptionalExtension};
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;
use zeroize::Zeroizing;

use crate::migrations;
use crate::TipoMovimiento;

pub const FX_SCALE: i64 = 100_000_000; // 1e8 factor de punto fijo

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AccountType {
    Cash,
    Bank,
    Wallet,
    CreditCard,
    Investment,
}

impl AccountType {
    pub fn as_str(&self) -> &'static str {
        match self {
            AccountType::Cash => "cash",
            AccountType::Bank => "bank",
            AccountType::Wallet => "wallet",
            AccountType::CreditCard => "credit_card",
            AccountType::Investment => "investment",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "cash" => Some(AccountType::Cash),
            "bank" => Some(AccountType::Bank),
            "wallet" => Some(AccountType::Wallet),
            "credit_card" => Some(AccountType::CreditCard),
            "investment" => Some(AccountType::Investment),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Account {
    pub id: [u8; 16],
    pub name: String,
    pub account_type: AccountType,
    pub currency: String,
    pub initial_balance: i64, // en centavos
    pub color: String,
    pub icon: String,
    pub credit_limit: Option<i64>,
    pub closing_day: Option<i32>,
    pub due_day: Option<i32>,
    pub created_at: i64,
    pub updated_at: i64,
    pub deleted_at: Option<i64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Category {
    pub id: [u8; 16],
    pub name: String,
    pub icon: String,
    pub color: String,
    pub parent_id: Option<[u8; 16]>,
    pub is_system: bool,
    pub created_at: i64,
    pub updated_at: i64,
    pub deleted_at: Option<i64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransactionType {
    Expense,
    Income,
    Transfer,
}

impl TransactionType {
    pub fn as_str(&self) -> &'static str {
        match self {
            TransactionType::Expense => "expense",
            TransactionType::Income => "income",
            TransactionType::Transfer => "transfer",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "expense" | "gasto" => Some(TransactionType::Expense),
            "income" | "ingreso" => Some(TransactionType::Income),
            "transfer" | "transferencia" => Some(TransactionType::Transfer),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct TransactionRecord {
    pub id: [u8; 16],
    pub account_id: [u8; 16],
    pub category_id: Option<[u8; 16]>,
    pub transaction_type: TransactionType,
    pub amount: i64, // centavos
    pub currency: String,
    pub destination_account_id: Option<[u8; 16]>,
    pub destination_amount: Option<i64>,
    pub exchange_rate_snapshot: Option<i64>,
    pub notes: String,
    pub date: i64, // unix ms
    pub raw_prompt: String,
    pub recurring_rule_id: Option<[u8; 16]>,
    pub scheduled_date: Option<i64>,
    pub created_at: i64,
    pub updated_at: i64,
    pub deleted_at: Option<i64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InstallmentStatus {
    Pending,
    Billed,
    Paid,
}

impl InstallmentStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            InstallmentStatus::Pending => "pending",
            InstallmentStatus::Billed => "billed",
            InstallmentStatus::Paid => "paid",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "pending" => Some(InstallmentStatus::Pending),
            "billed" => Some(InstallmentStatus::Billed),
            "paid" => Some(InstallmentStatus::Paid),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Installment {
    pub id: [u8; 16],
    pub transaction_id: [u8; 16],
    pub account_id: [u8; 16],
    pub installment_number: i32,
    pub total_installments: i32,
    pub amount: i64, // centavos de esta cuota
    pub cycle_year: i32,
    pub cycle_month: i32,
    pub due_date: i64,
    pub status: InstallmentStatus,
    pub created_at: i64,
    pub updated_at: i64,
    pub deleted_at: Option<i64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Frequency {
    Daily,
    Weekly,
    Monthly,
    Yearly,
}

impl Frequency {
    pub fn as_str(&self) -> &'static str {
        match self {
            Frequency::Daily => "daily",
            Frequency::Weekly => "weekly",
            Frequency::Monthly => "monthly",
            Frequency::Yearly => "yearly",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s {
            "daily" => Some(Frequency::Daily),
            "weekly" => Some(Frequency::Weekly),
            "monthly" => Some(Frequency::Monthly),
            "yearly" => Some(Frequency::Yearly),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct RecurringRule {
    pub id: [u8; 16],
    pub account_id: [u8; 16],
    pub category_id: Option<[u8; 16]>,
    pub transaction_type: TransactionType,
    pub amount: i64,
    pub currency: String,
    pub destination_account_id: Option<[u8; 16]>,
    pub frequency: Frequency,
    pub day_of_month: Option<i32>,
    pub day_of_week: Option<i32>,
    pub start_date: i64,
    pub end_date: Option<i64>,
    pub auto_apply: bool,
    pub last_processed_date: Option<i64>,
    pub created_at: i64,
    pub updated_at: i64,
    pub deleted_at: Option<i64>,
}

/// Fila lista para la UI de Flutter / FRB.
#[derive(Debug, Clone, PartialEq)]
pub struct Movement {
    pub id: String, // UUID string
    pub tipo: String, // "gasto" | "ingreso" | "transferencia"
    pub monto: f64, // para compatibilidad con UI actual
    pub monto_centavos: i64,
    pub moneda: String,
    pub categoria: String,
    pub descripcion: String,
    pub fecha: String, // YYYY-MM-DD
}

pub fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

fn is_plain_sqlite_file(path: &str) -> bool {
    if let Ok(mut f) = std::fs::File::open(path) {
        use std::io::Read;
        let mut magic = [0u8; 16];
        if f.read_exact(&mut magic).is_ok() {
            return &magic == b"SQLite format 3\0";
        }
    }
    false
}

fn migrate_legacy_movements(legacy: &Connection, encrypted: &Connection) -> Result<(), String> {
    let has_table: bool = legacy
        .query_row(
            "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='movements'",
            [],
            |r| Ok(r.get::<_, i64>(0)? > 0),
        )
        .unwrap_or(false);

    if !has_table {
        return Ok(());
    }

    let mut stmt = legacy
        .prepare("SELECT tipo, monto, moneda, categoria, descripcion, fecha, frase FROM movements")
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, f64>(1)?,
                r.get::<_, String>(2)?,
                r.get::<_, String>(3)?,
                r.get::<_, String>(4)?,
                r.get::<_, String>(5)?,
                r.get::<_, String>(6)?,
            ))
        })
        .map_err(|e| e.to_string())?;

    for row in rows {
        if let Ok((tipo_str, monto, moneda, cat, desc, fecha, frase)) = row {
            let t = match tipo_str.as_str() {
                "ingreso" => TipoMovimiento::Ingreso,
                _ => TipoMovimiento::Gasto,
            };
            let _ = insert(encrypted, &t, monto, &moneda, &cat, &desc, &fecha, &frase);
        }
    }

    Ok(())
}

/// Abre (o crea) la DB SQLite con o sin clave SQLCipher y aplica migraciones.
pub fn open(
    db_path: &str,
    raw_hex_key: Option<&Zeroizing<String>>,
) -> Result<Connection, String> {
    if db_path != ":memory:" && !db_path.is_empty() {
        let _ = migrations::backup_database_file(db_path);
    }

    // Si el archivo ya existía pero es SQLite plano (legacy) y ahora recibimos clave SQLCipher:
    if let Some(key) = raw_hex_key {
        let clean_key = key.trim();
        if !clean_key.is_empty() && db_path != ":memory:" && !db_path.is_empty() && is_plain_sqlite_file(db_path) {
            let legacy_backup_path = format!("{}.legacy_plain_{}", db_path, now_ms());
            std::fs::rename(db_path, &legacy_backup_path)
                .map_err(|e| format!("Error al respaldar DB plana legacy: {e}"))?;

            let mut conn = Connection::open(db_path).map_err(|e| e.to_string())?;
            conn.execute_batch(&format!("PRAGMA key = \"x'{}'\";", clean_key))
                .map_err(|e| format!("Error al aplicar clave SQLCipher: {e}"))?;

            migrations::run_migrations(&mut conn)?;
            ensure_default_accounts_and_categories(&conn)?;

            if let Ok(legacy_conn) = Connection::open(&legacy_backup_path) {
                let _ = migrate_legacy_movements(&legacy_conn, &conn);
            }

            return Ok(conn);
        }
    }

    let mut conn = Connection::open(db_path).map_err(|e| e.to_string())?;

    if let Some(key) = raw_hex_key {
        let clean_key = key.trim();
        if !clean_key.is_empty() {
            conn.execute_batch(&format!("PRAGMA key = \"x'{}'\";", clean_key))
                .map_err(|e| format!("Error al aplicar clave SQLCipher: {e}"))?;
        }
    }

    migrations::run_migrations(&mut conn)?;
    ensure_default_accounts_and_categories(&conn)?;

    Ok(conn)
}

/// Helper para tests o apertura sin clave cifrada.
pub fn open_default(db_path: &str) -> Result<Connection, String> {
    open(db_path, None)
}

/// Garantiza que exista al menos una cuenta por defecto y categorías base.
pub fn ensure_default_accounts_and_categories(conn: &Connection) -> Result<(), String> {
    let now = now_ms();

    // Cuenta Efectivo por defecto si no hay ninguna
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM accounts WHERE deleted_at IS NULL", [], |r| r.get(0))
        .map_err(|e| e.to_string())?;

    if count == 0 {
        let default_account_id = Uuid::now_v7();
        conn.execute(
            "INSERT INTO accounts (id, name, account_type, currency, initial_balance, color, icon, created_at, updated_at)
             VALUES (?1, 'Efectivo', 'cash', 'ARS', 0, '#4CAF50', 'payments', ?2, ?2)",
            params![default_account_id.as_bytes().as_slice(), now],
        )
        .map_err(|e| e.to_string())?;
    }

    // Categorías base si la tabla está vacía
    let cat_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM categories WHERE deleted_at IS NULL", [], |r| r.get(0))
        .map_err(|e| e.to_string())?;

    if cat_count == 0 {
        let default_cats = [
            ("supermercado", "shopping_cart", "#4CAF50"),
            ("transporte", "directions_bus", "#2196F3"),
            ("comida", "restaurant", "#FF9800"),
            ("alquiler", "home", "#9C27B0"),
            ("sueldo", "work", "#3F51B5"),
            ("servicios", "receipt_long", "#00BCD4"),
            ("salud", "medical_services", "#E91E63"),
            ("otros", "category", "#9E9E9E"),
        ];

        for (name, icon, color) in default_cats {
            let cat_id = Uuid::now_v7();
            conn.execute(
                "INSERT INTO categories (id, name, icon, color, is_system, created_at, updated_at)
                 VALUES (?1, ?2, ?3, ?4, 1, ?5, ?5)",
                params![cat_id.as_bytes().as_slice(), name, icon, color, now],
            )
            .map_err(|e| e.to_string())?;
        }
    }

    Ok(())
}

/// Obtiene el ID de la primera cuenta activa disponible (para fallback/compatibilidad).
pub fn get_default_account_id(conn: &Connection) -> Result<[u8; 16], String> {
    let mut stmt = conn
        .prepare("SELECT id FROM accounts WHERE deleted_at IS NULL ORDER BY created_at ASC LIMIT 1")
        .map_err(|e| e.to_string())?;
    let blob: Vec<u8> = stmt
        .query_row([], |r| r.get(0))
        .map_err(|e| e.to_string())?;
    let mut out = [0u8; 16];
    out.copy_from_slice(&blob[..16]);
    Ok(out)
}

/// Busca o crea una categoría por nombre.
pub fn get_or_create_category(conn: &Connection, name: &str) -> Result<[u8; 16], String> {
    let norm = name.trim().to_lowercase();
    let mut stmt = conn
        .prepare("SELECT id FROM categories WHERE lower(name) = ?1 AND deleted_at IS NULL LIMIT 1")
        .map_err(|e| e.to_string())?;

    let existing: Option<Vec<u8>> = stmt.query_row(params![norm], |r| r.get(0)).optional().map_err(|e| e.to_string())?;

    if let Some(blob) = existing {
        let mut out = [0u8; 16];
        out.copy_from_slice(&blob[..16]);
        return Ok(out);
    }

    let cat_id = Uuid::now_v7();
    let now = now_ms();
    conn.execute(
        "INSERT INTO categories (id, name, icon, color, is_system, created_at, updated_at)
         VALUES (?1, ?2, 'category', '#757575', 0, ?3, ?3)",
        params![cat_id.as_bytes().as_slice(), norm, now],
    )
    .map_err(|e| e.to_string())?;

    Ok(*cat_id.as_bytes())
}

#[derive(Debug, Clone, PartialEq)]
pub struct AccountWithBalance {
    pub id: String,
    pub name: String,
    pub account_type: String,
    pub currency: String,
    pub initial_balance: f64,
    pub current_balance: f64,
    pub color: String,
    pub icon: String,
    pub credit_limit: Option<f64>,
    pub closing_day: Option<i32>,
    pub due_day: Option<i32>,
}

pub fn create_account(
    conn: &Connection,
    name: &str,
    account_type: &AccountType,
    currency: &str,
    initial_balance_cents: i64,
    credit_limit_cents: Option<i64>,
    closing_day: Option<i32>,
    due_day: Option<i32>,
    color: &str,
    icon: &str,
) -> Result<String, String> {
    let id = Uuid::now_v7();
    let now = now_ms();
    conn.execute(
        "INSERT INTO accounts (id, name, account_type, currency, initial_balance, color, icon, credit_limit, closing_day, due_day, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?11)",
        params![
            id.as_bytes().as_slice(),
            name,
            account_type.as_str(),
            currency,
            initial_balance_cents,
            color,
            icon,
            credit_limit_cents,
            closing_day,
            due_day,
            now,
        ],
    )
    .map_err(|e| e.to_string())?;

    Ok(id.to_string())
}

pub fn list_accounts(conn: &Connection) -> Result<Vec<AccountWithBalance>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT id, name, account_type, currency, initial_balance, color, icon, credit_limit, closing_day, due_day
             FROM accounts
             WHERE deleted_at IS NULL
             ORDER BY created_at ASC",
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map([], |row| {
            let id_raw: Vec<u8> = row.get(0)?;
            let mut id_bytes = [0u8; 16];
            id_bytes.copy_from_slice(&id_raw[..16]);
            let id_str = Uuid::from_bytes(id_bytes).to_string();

            let name: String = row.get(1)?;
            let atype: String = row.get(2)?;
            let curr: String = row.get(3)?;
            let init_cents: i64 = row.get(4)?;
            let color: String = row.get(5)?;
            let icon: String = row.get(6)?;
            let limit_cents: Option<i64> = row.get(7)?;
            let closing: Option<i32> = row.get(8)?;
            let due: Option<i32> = row.get(9)?;

            Ok((id_bytes, id_str, name, atype, curr, init_cents, color, icon, limit_cents, closing, due))
        })
        .map_err(|e| e.to_string())?;

    let mut out = Vec::new();
    for r in rows {
        let (id_bytes, id_str, name, atype, curr, init_cents, color, icon, limit_cents, closing, due) = r.map_err(|e| e.to_string())?;
        let current_cents = get_account_balance(conn, &id_bytes).unwrap_or(init_cents);
        out.push(AccountWithBalance {
            id: id_str,
            name,
            account_type: atype,
            currency: curr,
            initial_balance: init_cents as f64 / 100.0,
            current_balance: current_cents as f64 / 100.0,
            color,
            icon,
            credit_limit: limit_cents.map(|c| c as f64 / 100.0),
            closing_day: closing,
            due_day: due,
        });
    }

    Ok(out)
}

#[derive(Debug, Clone, PartialEq)]
pub struct CardStatementItem {
    pub installment_id: String,
    pub transaction_id: String,
    pub installment_number: i32,
    pub total_installments: i32,
    pub amount: f64,
    pub description: String,
    pub status: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CardStatement {
    pub card_id: String,
    pub cycle_year: i32,
    pub cycle_month: i32,
    pub total_due: f64,
    pub items: Vec<CardStatementItem>,
}

pub fn get_card_statement(
    conn: &Connection,
    card_id: &[u8; 16],
    cycle_year: i32,
    cycle_month: i32,
) -> Result<CardStatement, String> {
    let mut stmt = conn
        .prepare(
            "SELECT i.id, i.transaction_id, i.installment_number, i.total_installments,
                    i.amount, COALESCE(t.notes, ''), i.status
             FROM installments i
             JOIN transactions t ON i.transaction_id = t.id
             WHERE i.account_id = ?1 AND i.cycle_year = ?2 AND i.cycle_month = ?3 AND i.deleted_at IS NULL
             ORDER BY i.due_date ASC",
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map(params![card_id.as_slice(), cycle_year, cycle_month], |row| {
            let inst_id_raw: Vec<u8> = row.get(0)?;
            let tx_id_raw: Vec<u8> = row.get(1)?;
            let mut i_id = [0u8; 16];
            i_id.copy_from_slice(&inst_id_raw[..16]);
            let mut t_id = [0u8; 16];
            t_id.copy_from_slice(&tx_id_raw[..16]);

            let num: i32 = row.get(2)?;
            let total: i32 = row.get(3)?;
            let amount_cents: i64 = row.get(4)?;
            let desc: String = row.get(5)?;
            let status: String = row.get(6)?;

            Ok(CardStatementItem {
                installment_id: Uuid::from_bytes(i_id).to_string(),
                transaction_id: Uuid::from_bytes(t_id).to_string(),
                installment_number: num,
                total_installments: total,
                amount: amount_cents as f64 / 100.0,
                description: desc,
                status,
            })
        })
        .map_err(|e| e.to_string())?;

    let mut items = Vec::new();
    let mut total_cents = 0i64;
    for r in rows {
        let item = r.map_err(|e| e.to_string())?;
        total_cents += (item.amount * 100.0).round() as i64;
        items.push(item);
    }

    Ok(CardStatement {
        card_id: Uuid::from_bytes(*card_id).to_string(),
        cycle_year,
        cycle_month,
        total_due: total_cents as f64 / 100.0,
        items,
    })
}

#[derive(Debug, Clone, PartialEq)]
pub struct RecurringRuleView {
    pub id: String,
    pub account_id: String,
    pub account_name: String,
    pub transaction_type: String,
    pub amount: f64,
    pub currency: String,
    pub frequency: String,
    pub start_date: i64,
    pub auto_apply: bool,
}

pub fn create_recurring_rule(
    conn: &Connection,
    account_id: &[u8; 16],
    transaction_type: &TransactionType,
    amount_cents: i64,
    currency: &str,
    frequency: &Frequency,
    auto_apply: bool,
) -> Result<String, String> {
    let id = Uuid::now_v7();
    let now = now_ms();
    conn.execute(
        "INSERT INTO recurring_rules (id, account_id, transaction_type, amount, currency, frequency, start_date, auto_apply, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?7, ?7)",
        params![
            id.as_bytes().as_slice(),
            account_id.as_slice(),
            transaction_type.as_str(),
            amount_cents,
            currency,
            frequency.as_str(),
            now,
            if auto_apply { 1 } else { 0 },
        ],
    )
    .map_err(|e| e.to_string())?;

    Ok(id.to_string())
}

pub fn list_recurring_rules(conn: &Connection) -> Result<Vec<RecurringRuleView>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT r.id, r.account_id, COALESCE(a.name, 'Cuenta'), r.transaction_type,
                    r.amount, r.currency, r.frequency, r.start_date, r.auto_apply
             FROM recurring_rules r
             LEFT JOIN accounts a ON r.account_id = a.id
             WHERE r.deleted_at IS NULL
             ORDER BY r.created_at DESC",
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map([], |row| {
            let id_raw: Vec<u8> = row.get(0)?;
            let acc_raw: Vec<u8> = row.get(1)?;
            let mut i_id = [0u8; 16];
            i_id.copy_from_slice(&id_raw[..16]);
            let mut a_id = [0u8; 16];
            a_id.copy_from_slice(&acc_raw[..16]);

            let aname: String = row.get(2)?;
            let ttype: String = row.get(3)?;
            let cents: i64 = row.get(4)?;
            let curr: String = row.get(5)?;
            let freq: String = row.get(6)?;
            let sdate: i64 = row.get(7)?;
            let auto: bool = row.get::<_, i64>(8)? == 1;

            Ok(RecurringRuleView {
                id: Uuid::from_bytes(i_id).to_string(),
                account_id: Uuid::from_bytes(a_id).to_string(),
                account_name: aname,
                transaction_type: ttype,
                amount: cents as f64 / 100.0,
                currency: curr,
                frequency: freq,
                start_date: sdate,
                auto_apply: auto,
            })
        })
        .map_err(|e| e.to_string())?;

    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| e.to_string())?);
    }
    Ok(out)
}

pub fn delete_account(conn: &Connection, id: &[u8; 16]) -> Result<bool, String> {
    let now = now_ms();
    let affected = conn
        .execute(
            "UPDATE accounts SET deleted_at = ?1 WHERE id = ?2 AND deleted_at IS NULL",
            params![now, id.as_slice()],
        )
        .map_err(|e| e.to_string())?;
    Ok(affected > 0)
}

pub fn delete_recurring_rule(conn: &Connection, id: &[u8; 16]) -> Result<bool, String> {
    let now = now_ms();
    let affected = conn
        .execute(
            "UPDATE recurring_rules SET deleted_at = ?1 WHERE id = ?2 AND deleted_at IS NULL",
            params![now, id.as_slice()],
        )
        .map_err(|e| e.to_string())?;
    Ok(affected > 0)
}

/// Inserta un movimiento simple y devuelve su UUID en formato string.
#[allow(clippy::too_many_arguments)]
pub fn insert(
    conn: &Connection,
    tipo: &TipoMovimiento,
    monto: f64,
    moneda: &str,
    categoria: &str,
    descripcion: &str,
    fecha: &str, // YYYY-MM-DD
    frase: &str,
) -> Result<String, String> {
    insert_with_account(conn, None, tipo, monto, moneda, categoria, descripcion, fecha, frase)
}

/// Inserta un movimiento con cuenta explícita (o fallback a default si None).
#[allow(clippy::too_many_arguments)]
pub fn insert_with_account(
    conn: &Connection,
    account_id_opt: Option<&[u8; 16]>,
    tipo: &TipoMovimiento,
    monto: f64,
    moneda: &str,
    categoria: &str,
    descripcion: &str,
    fecha: &str,
    frase: &str,
) -> Result<String, String> {
    if monto <= 0.0 {
        return Err("monto debe ser > 0".into());
    }
    if fecha.len() != 10 {
        return Err("fecha debe ser YYYY-MM-DD".into());
    }

    let account_id = match account_id_opt {
        Some(acc) => *acc,
        None => get_default_account_id(conn)?,
    };
    let category_id = get_or_create_category(conn, categoria)?;
    let monto_centavos = (monto * 100.0).round() as i64;
    let tx_type = match tipo {
        TipoMovimiento::Gasto => TransactionType::Expense,
        TipoMovimiento::Ingreso => TransactionType::Income,
    };

    let tx_id = Uuid::now_v7();
    let now = now_ms();

    conn.execute(
        "INSERT INTO transactions (
            id, account_id, category_id, transaction_type, amount, currency,
            notes, date, raw_prompt, created_at, updated_at
         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?10)",
        params![
            tx_id.as_bytes().as_slice(),
            account_id.as_slice(),
            category_id.as_slice(),
            tx_type.as_str(),
            monto_centavos,
            moneda,
            descripcion,
            now,
            frase,
            now,
        ],
    )
    .map_err(|e| e.to_string())?;

    Ok(tx_id.to_string())
}

/// Inserta una transferencia intercuenta, calculando e insertando cotización si son distintas monedas.
#[allow(clippy::too_many_arguments)]
pub fn insert_transfer(
    conn: &Connection,
    from_account_id: &[u8; 16],
    to_account_id: &[u8; 16],
    from_amount: i64,
    to_amount: i64,
    timestamp: i64,
    notes: &str,
) -> Result<[u8; 16], String> {
    if from_amount <= 0 || to_amount <= 0 {
        return Err("montos de transferencia deben ser > 0".into());
    }

    let from_currency: String = conn
        .query_row("SELECT currency FROM accounts WHERE id = ?1", params![from_account_id.as_slice()], |r| r.get(0))
        .map_err(|e| format!("Cuenta origen inexistente: {e}"))?;

    let to_currency: String = conn
        .query_row("SELECT currency FROM accounts WHERE id = ?1", params![to_account_id.as_slice()], |r| r.get(0))
        .map_err(|e| format!("Cuenta destino inexistente: {e}"))?;

    // Cotización implícita automática
    if from_currency != to_currency {
        let rate = (to_amount * FX_SCALE) / from_amount;
        let rate_id = Uuid::now_v7();
        let now = now_ms();
        conn.execute(
            "INSERT INTO exchange_rates (id, base_currency, quote_currency, rate, timestamp, source, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, 'implicit_transfer', ?6, ?6)",
            params![
                rate_id.as_bytes().as_slice(),
                from_currency,
                to_currency,
                rate,
                timestamp,
                now,
            ],
        )
        .map_err(|e| e.to_string())?;
    }

    let tx_id = Uuid::now_v7();
    let now = now_ms();

    conn.execute(
        "INSERT INTO transactions (
            id, account_id, category_id, transaction_type, amount, currency,
            destination_account_id, destination_amount, notes, date, created_at, updated_at
         ) VALUES (?1, ?2, NULL, 'transfer', ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?9)",
        params![
            tx_id.as_bytes().as_slice(),
            from_account_id.as_slice(),
            from_amount,
            from_currency,
            to_account_id.as_slice(),
            to_amount,
            notes,
            timestamp,
            now,
        ],
    )
    .map_err(|e| e.to_string())?;

    Ok(*tx_id.as_bytes())
}

/// Días en un mes específico para cálculo seguro de cierre/vencimiento.
pub fn days_in_month(year: i32, month: i32) -> i32 {
    match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 => {
            let is_leap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
            if is_leap { 29 } else { 28 }
        }
        _ => 30,
    }
}

/// Inserta una compra con tarjeta en N cuotas, desglosando la tabla installments.
#[allow(clippy::too_many_arguments)]
pub fn insert_credit_purchase(
    conn: &Connection,
    card_account_id: &[u8; 16],
    category_id: Option<&[u8; 16]>,
    total_amount: i64,
    installments_count: i32,
    purchase_timestamp: i64,
    start_cycle_year: i32,
    start_cycle_month: i32,
    notes: &str,
    raw_prompt: &str,
) -> Result<[u8; 16], String> {
    if total_amount <= 0 || installments_count <= 0 {
        return Err("monto y cuotas deben ser mayores a 0".into());
    }

    let currency: String = conn
        .query_row(
            "SELECT currency FROM accounts WHERE id = ?1 AND account_type = 'credit_card'",
            params![card_account_id.as_slice()],
            |r| r.get(0),
        )
        .map_err(|e| format!("Cuenta tarjeta no válida: {e}"))?;

    let tx_id = Uuid::now_v7();
    let now = now_ms();

    conn.execute(
        "INSERT INTO transactions (
            id, account_id, category_id, transaction_type, amount, currency,
            notes, date, raw_prompt, created_at, updated_at
         ) VALUES (?1, ?2, ?3, 'expense', ?4, ?5, ?6, ?7, ?8, ?9, ?9)",
        params![
            tx_id.as_bytes().as_slice(),
            card_account_id.as_slice(),
            category_id.map(|c| c.as_slice()),
            total_amount,
            currency,
            notes,
            purchase_timestamp,
            raw_prompt,
            now,
        ],
    )
    .map_err(|e| e.to_string())?;

    // Desglose de cuotas con redondeo exacto de centavos
    let base_amount = total_amount / installments_count as i64;
    let remainder = total_amount % installments_count as i64;

    let mut cur_year = start_cycle_year;
    let mut cur_month = start_cycle_month;

    for i in 1..=installments_count {
        let inst_id = Uuid::now_v7();
        let inst_amount = if i == 1 { base_amount + remainder } else { base_amount };
        let due_date = purchase_timestamp; // simplificado para fecha estimada

        conn.execute(
            "INSERT INTO installments (
                id, transaction_id, account_id, installment_number, total_installments,
                amount, cycle_year, cycle_month, due_date, status, created_at, updated_at
             ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 'pending', ?10, ?10)",
            params![
                inst_id.as_bytes().as_slice(),
                tx_id.as_bytes().as_slice(),
                card_account_id.as_slice(),
                i,
                installments_count,
                inst_amount,
                cur_year,
                cur_month,
                due_date,
                now,
            ],
        )
        .map_err(|e| e.to_string())?;

        // Avanzar mes
        cur_month += 1;
        if cur_month > 12 {
            cur_month = 1;
            cur_year += 1;
        }
    }

    Ok(*tx_id.as_bytes())
}

/// Procesa reglas recurrentes de forma idempotente.
pub fn process_recurring_rules(
    conn: &Connection,
    until_timestamp: i64,
    max_lookback_ms: i64,
) -> Result<usize, String> {
    let mut stmt = conn
        .prepare(
            "SELECT id, account_id, category_id, transaction_type, amount, currency,
                    destination_account_id, frequency, start_date, end_date, auto_apply, last_processed_date
             FROM recurring_rules
             WHERE deleted_at IS NULL AND start_date <= ?1",
        )
        .map_err(|e| e.to_string())?;

    let rules = stmt
        .query_map(params![until_timestamp], |row| {
            let id_raw: Vec<u8> = row.get(0)?;
            let acc_raw: Vec<u8> = row.get(1)?;
            let cat_raw: Option<Vec<u8>> = row.get(2)?;
            let ttype_str: String = row.get(3)?;
            let amount: i64 = row.get(4)?;
            let currency: String = row.get(5)?;
            let dst_raw: Option<Vec<u8>> = row.get(6)?;
            let freq_str: String = row.get(7)?;
            let start_date: i64 = row.get(8)?;
            let end_date: Option<i64> = row.get(9)?;
            let auto_apply: bool = row.get::<_, i64>(10)? == 1;
            let last_processed: Option<i64> = row.get(11)?;

            let mut id = [0u8; 16];
            id.copy_from_slice(&id_raw[..16]);
            let mut account_id = [0u8; 16];
            account_id.copy_from_slice(&acc_raw[..16]);

            Ok(RecurringRule {
                id,
                account_id,
                category_id: cat_raw.map(|b| {
                    let mut a = [0u8; 16];
                    a.copy_from_slice(&b[..16]);
                    a
                }),
                transaction_type: TransactionType::from_str(&ttype_str).unwrap_or(TransactionType::Expense),
                amount,
                currency,
                destination_account_id: dst_raw.map(|b| {
                    let mut a = [0u8; 16];
                    a.copy_from_slice(&b[..16]);
                    a
                }),
                frequency: Frequency::from_str(&freq_str).unwrap_or(Frequency::Monthly),
                day_of_month: None,
                day_of_week: None,
                start_date,
                end_date,
                auto_apply,
                last_processed_date: last_processed,
                created_at: 0,
                updated_at: 0,
                deleted_at: None,
            })
        })
        .map_err(|e| e.to_string())?;

    let mut inserted_count = 0;
    let min_allowed = until_timestamp.saturating_sub(max_lookback_ms);

    for r in rules {
        let rule = r.map_err(|e| e.to_string())?;
        if !rule.auto_apply {
            continue;
        }

        // Programación mensual de ejemplo (intervalo de 30 días aprox en ms)
        let interval_ms: i64 = match rule.frequency {
            Frequency::Daily => 86_400_000,
            Frequency::Weekly => 7 * 86_400_000,
            Frequency::Monthly => 30 * 86_400_000,
            Frequency::Yearly => 365 * 86_400_000,
        };

        let mut sched = rule.start_date;
        if sched < min_allowed {
            // saltar hasta el rango permitido
            let steps = (min_allowed - sched) / interval_ms;
            sched += steps * interval_ms;
        }

        while sched <= until_timestamp {
            if let Some(end) = rule.end_date {
                if sched > end {
                    break;
                }
            }

            let tx_id = Uuid::now_v7();
            let now = now_ms();
            let res = conn.execute(
                "INSERT OR IGNORE INTO transactions (
                    id, account_id, category_id, transaction_type, amount, currency,
                    notes, date, recurring_rule_id, scheduled_date, created_at, updated_at
                 ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, 'Recurrente automático', ?7, ?8, ?7, ?9, ?9)",
                params![
                    tx_id.as_bytes().as_slice(),
                    rule.account_id.as_slice(),
                    rule.category_id.as_ref().map(|c| c.as_slice()),
                    rule.transaction_type.as_str(),
                    rule.amount,
                    rule.currency,
                    sched,
                    rule.id.as_slice(),
                    now,
                ],
            );

            if let Ok(affected) = res {
                if affected > 0 {
                    inserted_count += 1;
                }
            }

            sched += interval_ms;
        }
    }

    Ok(inserted_count)
}

/// Lista los últimos movimientos (más recientes primero) para alimentar la UI.
pub fn list(conn: &Connection, limit: i64) -> Result<Vec<Movement>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT t.id, t.transaction_type, t.amount, t.currency,
                    COALESCE(c.name, 'general'), t.notes, t.date
             FROM transactions t
             LEFT JOIN categories c ON t.category_id = c.id
             WHERE t.deleted_at IS NULL
             ORDER BY t.date DESC, t.created_at DESC, t.rowid DESC
             LIMIT ?1",
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map(params![limit], |row| {
            let id_blob: Vec<u8> = row.get(0)?;
            let id_str = if id_blob.len() == 16 {
                let mut b = [0u8; 16];
                b.copy_from_slice(&id_blob);
                Uuid::from_bytes(b).to_string()
            } else {
                Uuid::now_v7().to_string()
            };

            let ttype: String = row.get(1)?;
            let tipo_ui = match ttype.as_str() {
                "income" | "ingreso" => "ingreso",
                "expense" | "gasto" => "gasto",
                "transfer" | "transferencia" => "transferencia",
                other => other,
            }.to_string();
            let centavos: i64 = row.get(2)?;
            let moneda: String = row.get(3)?;
            let cat: String = row.get(4)?;
            let desc: String = row.get(5)?;
            let date_ms: i64 = row.get(6)?;

            // Convertir timestamp a YYYY-MM-DD
            let secs = (date_ms / 1000) as u64;
            let dt: chrono_mock::NaiveDate = chrono_mock::NaiveDate::from_timestamp_opt(secs);

            Ok(Movement {
                id: id_str,
                tipo: tipo_ui,
                monto: centavos as f64 / 100.0,
                monto_centavos: centavos,
                moneda,
                categoria: cat,
                descripcion: desc,
                fecha: dt.format(),
            })
        })
        .map_err(|e| e.to_string())?;

    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| e.to_string())?);
    }
    Ok(out)
}

/// Balance consolidado por moneda: (moneda, gastos, ingresos).
pub fn balance(conn: &Connection) -> Result<Vec<(String, f64, f64)>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT currency,
                    SUM(CASE WHEN transaction_type IN ('expense', 'gasto') THEN amount ELSE 0 END),
                    SUM(CASE WHEN transaction_type IN ('income', 'ingreso') THEN amount ELSE 0 END)
             FROM transactions
             WHERE deleted_at IS NULL
             GROUP BY currency",
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map([], |row| {
            let moneda: String = row.get(0)?;
            let gastos_cents: i64 = row.get::<_, Option<i64>>(1)?.unwrap_or(0);
            let ingresos_cents: i64 = row.get::<_, Option<i64>>(2)?.unwrap_or(0);
            Ok((
                moneda,
                gastos_cents as f64 / 100.0,
                ingresos_cents as f64 / 100.0,
            ))
        })
        .map_err(|e| e.to_string())?;

    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| e.to_string())?);
    }
    Ok(out)
}

/// Saldo actual de una cuenta en centavos.
pub fn get_account_balance(conn: &Connection, account_id: &[u8; 16]) -> Result<i64, String> {
    let initial: i64 = conn
        .query_row(
            "SELECT initial_balance FROM accounts WHERE id = ?1",
            params![account_id.as_slice()],
            |r| r.get(0),
        )
        .map_err(|e| e.to_string())?;

    let incomes: i64 = conn
        .query_row(
            "SELECT COALESCE(SUM(amount), 0) FROM transactions
             WHERE account_id = ?1 AND transaction_type = 'income' AND deleted_at IS NULL",
            params![account_id.as_slice()],
            |r| r.get(0),
        )
        .unwrap_or(0);

    let expenses: i64 = conn
        .query_row(
            "SELECT COALESCE(SUM(amount), 0) FROM transactions
             WHERE account_id = ?1 AND transaction_type = 'expense' AND deleted_at IS NULL",
            params![account_id.as_slice()],
            |r| r.get(0),
        )
        .unwrap_or(0);

    let transfers_out: i64 = conn
        .query_row(
            "SELECT COALESCE(SUM(amount), 0) FROM transactions
             WHERE account_id = ?1 AND transaction_type = 'transfer' AND deleted_at IS NULL",
            params![account_id.as_slice()],
            |r| r.get(0),
        )
        .unwrap_or(0);

    let transfers_in: i64 = conn
        .query_row(
            "SELECT COALESCE(SUM(destination_amount), 0) FROM transactions
             WHERE destination_account_id = ?1 AND transaction_type = 'transfer' AND deleted_at IS NULL",
            params![account_id.as_slice()],
            |r| r.get(0),
        )
        .unwrap_or(0);

    Ok(initial + incomes - expenses - transfers_out + transfers_in)
}

/// Exporta movimientos para reentrenamiento de Cactus Needle (formato make_dataset.py).
pub fn export_corrections_jsonl(conn: &Connection, tools_json: &str) -> Result<String, String> {
    let mut stmt = conn
        .prepare(
            "SELECT t.transaction_type, t.amount, COALESCE(c.name, 'otros'), t.raw_prompt, t.date
             FROM transactions t
             LEFT JOIN categories c ON t.category_id = c.id
             WHERE t.deleted_at IS NULL AND t.raw_prompt != ''
             ORDER BY t.created_at ASC",
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map([], |row| {
            let ttype: String = row.get(0)?;
            let cents: i64 = row.get(1)?;
            let cat: String = row.get(2)?;
            let phrase: String = row.get(3)?;
            let date_ms: i64 = row.get(4)?;
            let secs = (date_ms / 1000) as u64;
            let dt = chrono_mock::NaiveDate::from_timestamp_opt(secs);

            Ok((
                if ttype == "income" { "ingreso" } else { "gasto" },
                cents as f64 / 100.0,
                cat,
                phrase,
                dt.format(),
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

/// Formateador simple de fecha YYYY-MM-DD sin añadir crates de tiempo pesados.
mod chrono_mock {
    pub struct NaiveDate {
        pub year: i32,
        pub month: u32,
        pub day: u32,
    }

    impl NaiveDate {
        pub fn from_timestamp_opt(epoch_secs: u64) -> Self {
            let days = (epoch_secs / 86400) as i64;
            // Algoritmo de días civiles para calendario Gregoriano
            let z = days + 719468;
            let era = if z >= 0 { z } else { z - 146096 } / 146097;
            let doe = (z - era * 146097) as u32;
            let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
            let y = (yoe as i64) + era * 400;
            let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
            let mp = (5 * doy + 2) / 153;
            let d = doy - (153 * mp + 2) / 5 + 1;
            let m = if mp < 10 { mp + 3 } else { mp - 9 };
            let year = if m <= 2 { y + 1 } else { y };
            NaiveDate {
                year: year as i32,
                month: m,
                day: d,
            }
        }

        pub fn format(&self) -> String {
            format!("{:04}-{:02}-{:02}", self.year, self.month, self.day)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::TipoMovimiento::{Gasto, Ingreso};

    fn mem() -> Connection {
        open_default(":memory:").unwrap()
    }

    #[test]
    fn insert_y_list_relacional() {
        let c = mem();
        let id1 = insert(&c, &Gasto, 5000.0, "ARS", "supermercado", "súper", "2026-09-30", "gasté 5000").unwrap();
        assert!(!id1.is_empty());

        let id2 = insert(&c, &Ingreso, 200000.0, "ARS", "sueldo", "", "2026-09-30", "sueldo").unwrap();
        assert!(!id2.is_empty());

        let all = list(&c, 10).unwrap();
        assert_eq!(all.len(), 2);
        assert_eq!(all[0].monto, 200000.0);
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
        assert_eq!(b[0].1, 5000.0);
        assert_eq!(b[0].2, 200000.0);
        assert_eq!(b[1].0, "USD");
        assert_eq!(b[1].1, 100.0);
    }

    #[test]
    fn transferencias_bimonetarias_con_cotizacion() {
        let c = mem();
        // Crear cuenta USD
        let usd_acc_id = Uuid::now_v7();
        let now = now_ms();
        c.execute(
            "INSERT INTO accounts (id, name, account_type, currency, initial_balance, created_at, updated_at)
             VALUES (?1, 'Ahorros USD', 'bank', 'USD', 0, ?2, ?2)",
            params![usd_acc_id.as_bytes().as_slice(), now],
        )
        .unwrap();

        let default_acc = get_default_account_id(&c).unwrap();

        // Transferir 1.300.000 ARS (130_000_000 cents) -> 1.000 USD (100_000 cents)
        let tx = insert_transfer(
            &c,
            &default_acc,
            usd_acc_id.as_bytes(),
            130_000_000,
            100_000,
            now,
            "Compra MEP",
        )
        .unwrap();
        assert_eq!(tx.len(), 16);

        // Verificar que se insertó la cotización implícita
        let (base, quote, rate): (String, String, i64) = c
            .query_row(
                "SELECT base_currency, quote_currency, rate FROM exchange_rates ORDER BY created_at DESC LIMIT 1",
                [],
                |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
            )
            .unwrap();
        assert_eq!(base, "ARS");
        assert_eq!(quote, "USD");
        assert!(rate > 0);
    }

    #[test]
    fn tarjeta_compras_en_cuotas() {
        let c = mem();
        let card_id = Uuid::now_v7();
        let now = now_ms();
        c.execute(
            "INSERT INTO accounts (id, name, account_type, currency, initial_balance, credit_limit, closing_day, due_day, created_at, updated_at)
             VALUES (?1, 'Visa Santander', 'credit_card', 'ARS', 0, 50000000, 20, 5, ?2, ?2)",
            params![card_id.as_bytes().as_slice(), now],
        )
        .unwrap();

        // Compra de $30.000 (3_000_000 cents) en 3 cuotas
        let tx = insert_credit_purchase(
            &c,
            card_id.as_bytes(),
            None,
            3_000_000,
            3,
            now,
            2026,
            10,
            "Heladera",
            "compré heladera en 3 cuotas",
        )
        .unwrap();
        assert_eq!(tx.len(), 16);

        // Verificar 3 cuotas en tabla installments
        let count: i64 = c
            .query_row(
                "SELECT COUNT(*) FROM installments WHERE transaction_id = ?1",
                params![tx.as_slice()],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(count, 3);

        // Cada cuota debe ser exactamente 1_000_000 centavos ($10.000)
        let amount: i64 = c
            .query_row(
                "SELECT amount FROM installments WHERE transaction_id = ?1 LIMIT 1",
                params![tx.as_slice()],
                |r| r.get(0),
            )
            .unwrap();
        assert_eq!(amount, 1_000_000);
    }

    #[test]
    fn recurrentes_idempotencia() {
        let c = mem();
        let acc_id = get_default_account_id(&c).unwrap();
        let rule_id = Uuid::now_v7();
        let now = now_ms();

        // Regla: $10.000 mensual, auto_apply = 1
        c.execute(
            "INSERT INTO recurring_rules (id, account_id, transaction_type, amount, currency, frequency, start_date, auto_apply, created_at, updated_at)
             VALUES (?1, ?2, 'expense', 1000000, 'ARS', 'monthly', ?3, 1, ?3, ?3)",
            params![rule_id.as_bytes().as_slice(), acc_id.as_slice(), now],
        )
        .unwrap();

        // Ejecutar primer procesamiento
        let inserted1 = process_recurring_rules(&c, now, 86_400_000 * 30).unwrap();
        assert_eq!(inserted1, 1);

        // Reintentar de inmediato: no debe duplicar (idempotente)
        let inserted2 = process_recurring_rules(&c, now, 86_400_000 * 30).unwrap();
        assert_eq!(inserted2, 0);
    }

    #[test]
    fn sqlcipher_cifrado_y_rechazo_clave_invalida() {
        let db_file = "/tmp/moneyneedle_cipher_test.db";
        let _ = std::fs::remove_file(db_file);

        let key = Zeroizing::new("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef".to_string());

        // 1. Crear y escribir con clave válida
        {
            let conn = open(db_file, Some(&key)).unwrap();
            insert(&conn, &Gasto, 1500.0, "ARS", "comida", "almuerzo", "2026-09-30", "almorcé 1500").unwrap();
        }

        // 2. Intentar abrir con clave equivocada -> debe fallar al consultar datos
        {
            let bad_key = Zeroizing::new("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff".to_string());
            let conn = Connection::open(db_file).unwrap();
            conn.execute_batch(&format!("PRAGMA key = \"x'{}'\";", *bad_key)).unwrap();
            let res = conn.execute("SELECT count(*) FROM transactions", []);
            assert!(res.is_err(), "SQLCipher debe rechazar lectura con clave incorrecta");
        }

        // 3. Abrir de nuevo con la clave correcta -> debe funcionar
        {
            let conn = open(db_file, Some(&key)).unwrap();
            let list = list(&conn, 10).unwrap();
            assert_eq!(list.len(), 1);
            assert_eq!(list[0].monto, 1500.0);
        }

        let _ = std::fs::remove_file(db_file);
    }

    #[test]
    fn migracion_automatica_de_base_plana_legacy() {
        let db_file = "/tmp/moneyneedle_legacy_migrate_test.db";
        let _ = std::fs::remove_file(db_file);

        // 1. Crear una base plana como en el PR #5 viejo
        {
            let conn = Connection::open(db_file).unwrap();
            conn.execute_batch(
                "CREATE TABLE movements (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    tipo TEXT NOT NULL,
                    monto REAL NOT NULL,
                    moneda TEXT NOT NULL,
                    categoria TEXT NOT NULL,
                    descripcion TEXT NOT NULL,
                    fecha TEXT NOT NULL,
                    frase TEXT NOT NULL
                );
                INSERT INTO movements (tipo, monto, moneda, categoria, descripcion, fecha, frase)
                VALUES ('ingreso', 100000.0, 'ARS', 'sueldo', 'cubre sueldo', '2026-09-30', 'sueldo');",
            ).unwrap();
        }

        // 2. Abrir con clave SQLCipher: debe detectar base plana, migrar datos y abrir cifrado
        let key = Zeroizing::new("1111222233334444111122223333444411112222333344441111222233334444".to_string());
        {
            let conn = open(db_file, Some(&key)).unwrap();
            let all = list(&conn, 10).unwrap();
            assert_eq!(all.len(), 1);
            assert_eq!(all[0].tipo, "ingreso");
            assert_eq!(all[0].monto, 100000.0);
        }

        // 3. Verificar que el archivo ahora está realmente cifrado (no plano)
        {
            let conn_unencrypted = Connection::open(db_file).unwrap();
            let res = conn_unencrypted.execute("SELECT count(*) FROM transactions", []);
            assert!(res.is_err(), "La base debe haber quedado cifrada con SQLCipher");
        }

        let _ = std::fs::remove_file(db_file);
    }
}
