//! Persistencia SQLite protegida con SQLCipher y modelo relacional completo.
//!
//! Soporta cuentas, categorías dinámicas, transferencias multimoneda,
//! compras en cuotas con tarjeta de crédito, reglas recurrentes idempotentes
//! y exportación para reentrenamiento de Cactus Needle.

use rusqlite::{params, Connection, OptionalExtension};
use std::collections::{BTreeMap, HashMap};
use std::sync::{Mutex, OnceLock};
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
    pub account_id: Option<String>,
    pub account_name: Option<String>,
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

static ACTIVE_HEX_KEYS: OnceLock<Mutex<HashMap<String, Zeroizing<String>>>> = OnceLock::new();

fn active_hex_keys() -> &'static Mutex<HashMap<String, Zeroizing<String>>> {
    ACTIVE_HEX_KEYS.get_or_init(|| Mutex::new(HashMap::new()))
}

pub fn set_active_key_for_path(db_path: &str, key: Option<Zeroizing<String>>) {
    if let Ok(mut lock) = active_hex_keys().lock() {
        match key {
            Some(k) => {
                lock.insert(db_path.to_string(), k);
            }
            None => {
                lock.remove(db_path);
            }
        }
    }
}

pub fn get_active_key_for_path(db_path: &str) -> Option<Zeroizing<String>> {
    active_hex_keys().lock().ok().and_then(|m| m.get(db_path).cloned())
}

/// Abre la conexión utilizando la clave activa de la sesión para la ruta indicada (o None si es :memory: o no hay clave).
pub fn open_default(db_path: &str) -> Result<Connection, String> {
    if db_path == ":memory:" {
        return open(db_path, None);
    }
    let key = get_active_key_for_path(db_path);
    open(db_path, key.as_ref())
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
pub struct CategoryInfo {
    pub id: String,
    pub name: String,
    pub icon: String,
    pub color: String,
    pub is_system: bool,
}

pub fn list_categories(conn: &Connection) -> Result<Vec<CategoryInfo>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT id, name, icon, color, is_system
             FROM categories
             WHERE deleted_at IS NULL
             ORDER BY is_system DESC, name ASC",
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map([], |row| {
            let id_raw: Vec<u8> = row.get(0)?;
            let mut id_bytes = [0u8; 16];
            id_bytes.copy_from_slice(&id_raw);

            let is_sys: i32 = row.get(4)?;

            Ok(CategoryInfo {
                id: Uuid::from_bytes(id_bytes).to_string(),
                name: row.get(1)?,
                icon: row.get(2)?,
                color: row.get(3)?,
                is_system: is_sys != 0,
            })
        })
        .map_err(|e| e.to_string())?;

    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| e.to_string())?);
    }
    Ok(out)
}

pub fn create_category(
    conn: &Connection,
    name: &str,
    icon: &str,
    color: &str,
    parent_id: Option<&[u8; 16]>,
) -> Result<[u8; 16], String> {
    let name_clean = name.trim();
    if name_clean.is_empty() {
        return Err("El nombre de la categoría no puede estar vacío".to_string());
    }
    let id = *Uuid::now_v7().as_bytes();
    let now = now_ms();
    conn.execute(
        "INSERT INTO categories (id, name, icon, color, parent_id, is_system, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, 0, ?6, ?6)",
        params![
            id.as_slice(),
            name_clean,
            icon.trim(),
            color.trim(),
            parent_id.map(|p| p.as_slice()),
            now
        ],
    )
    .map_err(|e| e.to_string())?;
    Ok(id)
}

pub fn update_category(
    conn: &Connection,
    category_id: &[u8; 16],
    name: &str,
    icon: &str,
    color: &str,
) -> Result<bool, String> {
    let name_clean = name.trim();
    if name_clean.is_empty() {
        return Err("El nombre de la categoría no puede estar vacío".to_string());
    }
    let now = now_ms();
    let affected = conn
        .execute(
            "UPDATE categories
             SET name = ?1, icon = ?2, color = ?3, updated_at = ?4
             WHERE id = ?5 AND deleted_at IS NULL",
            params![name_clean, icon.trim(), color.trim(), now, category_id.as_slice()],
        )
        .map_err(|e| e.to_string())?;
    Ok(affected > 0)
}

pub fn delete_category(conn: &Connection, category_id: &[u8; 16]) -> Result<bool, String> {
    let is_sys: i32 = conn
        .query_row(
            "SELECT is_system FROM categories WHERE id = ?1 AND deleted_at IS NULL",
            params![category_id.as_slice()],
            |r| r.get(0),
        )
        .map_err(|e| e.to_string())?;

    if is_sys != 0 {
        return Err("No se pueden eliminar categorías del sistema".to_string());
    }

    let now = now_ms();
    let affected = conn
        .execute(
            "UPDATE categories SET deleted_at = ?1, updated_at = ?1 WHERE id = ?2 AND is_system = 0 AND deleted_at IS NULL",
            params![now, category_id.as_slice()],
        )
        .map_err(|e| e.to_string())?;
    Ok(affected > 0)
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

pub fn update_account(
    conn: &Connection,
    account_id: &[u8; 16],
    name: &str,
    color: &str,
    credit_limit: Option<i64>,
    closing_day: Option<i32>,
    due_day: Option<i32>,
) -> Result<bool, String> {
    let name_clean = name.trim();
    if name_clean.is_empty() {
        return Err("El nombre de la cuenta no puede estar vacío".to_string());
    }
    let now = now_ms();
    let affected = conn
        .execute(
            "UPDATE accounts
             SET name = ?1, color = ?2, credit_limit = ?3, closing_day = ?4, due_day = ?5, updated_at = ?6
             WHERE id = ?7 AND deleted_at IS NULL",
            params![
                name_clean,
                color.trim(),
                credit_limit,
                closing_day,
                due_day,
                now,
                account_id.as_slice()
            ],
        )
        .map_err(|e| e.to_string())?;
    Ok(affected > 0)
}

pub fn update_recurring_rule(
    conn: &Connection,
    rule_id: &[u8; 16],
    amount_cents: i64,
    frequency: &str,
    auto_apply: bool,
) -> Result<bool, String> {
    if amount_cents <= 0 {
        return Err("El monto recurrente debe ser mayor a 0".to_string());
    }
    let now = now_ms();
    let affected = conn
        .execute(
            "UPDATE recurring_rules
             SET amount = ?1, frequency = ?2, auto_apply = ?3, updated_at = ?4
             WHERE id = ?5 AND deleted_at IS NULL",
            params![
                amount_cents,
                frequency,
                if auto_apply { 1 } else { 0 },
                now,
                rule_id.as_slice()
            ],
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

#[derive(Debug, Clone, PartialEq)]
pub struct ExchangeRateRecord {
    pub base_currency: String,
    pub quote_currency: String,
    pub rate: f64,
    pub timestamp: i64,
}

pub fn get_latest_exchange_rate(
    conn: &Connection,
    base_currency: &str,
    quote_currency: &str,
) -> Result<Option<ExchangeRateRecord>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT base_currency, quote_currency, rate, timestamp
             FROM exchange_rates
             WHERE base_currency = ?1 AND quote_currency = ?2 AND deleted_at IS NULL
             ORDER BY timestamp DESC, created_at DESC
             LIMIT 1",
        )
        .map_err(|e| e.to_string())?;

    let res: Option<ExchangeRateRecord> = stmt
        .query_row(params![base_currency, quote_currency], |r| {
            let base: String = r.get(0)?;
            let quote: String = r.get(1)?;
            let raw_rate: i64 = r.get(2)?;
            let ts: i64 = r.get(3)?;
            Ok(ExchangeRateRecord {
                base_currency: base,
                quote_currency: quote,
                rate: raw_rate as f64 / FX_SCALE as f64,
                timestamp: ts,
            })
        })
        .optional()
        .map_err(|e| e.to_string())?;

    Ok(res)
}

pub fn list_exchange_rates(conn: &Connection) -> Result<Vec<ExchangeRateRecord>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT base_currency, quote_currency, rate, timestamp
             FROM exchange_rates
             WHERE deleted_at IS NULL
             ORDER BY timestamp DESC, created_at DESC
             LIMIT 50",
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map([], |r| {
            let base: String = r.get(0)?;
            let quote: String = r.get(1)?;
            let raw_rate: i64 = r.get(2)?;
            let ts: i64 = r.get(3)?;
            Ok(ExchangeRateRecord {
                base_currency: base,
                quote_currency: quote,
                rate: raw_rate as f64 / FX_SCALE as f64,
                timestamp: ts,
            })
        })
        .map_err(|e| e.to_string())?;

    let mut out = Vec::new();
    for row in rows {
        out.push(row.map_err(|e| e.to_string())?);
    }
    Ok(out)
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
                    COALESCE(c.name, 'general'), t.notes, t.date,
                    t.account_id, COALESCE(a.name, 'General')
             FROM transactions t
             LEFT JOIN categories c ON t.category_id = c.id
             LEFT JOIN accounts a ON t.account_id = a.id
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

            let acc_blob: Option<Vec<u8>> = row.get(7)?;
            let acc_id_str = acc_blob.and_then(|b| {
                if b.len() == 16 {
                    let mut arr = [0u8; 16];
                    arr.copy_from_slice(&b);
                    Some(Uuid::from_bytes(arr).to_string())
                } else {
                    None
                }
            });
            let acc_name: Option<String> = row.get(8)?;

            // Convertir timestamp a YYYY-MM-DD
            let secs = (date_ms.max(0) / 1000) as u64;
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
                account_id: acc_id_str,
                account_name: acc_name,
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

        pub fn parse(s: &str) -> Option<Self> {
            let parts: Vec<&str> = s.split('-').collect();
            if parts.len() != 3 {
                return None;
            }
            let year: i32 = parts[0].parse().ok()?;
            let month: u32 = parts[1].parse().ok()?;
            let day: u32 = parts[2].parse().ok()?;
            if !(1..=12).contains(&month) || !(1..=31).contains(&day) {
                return None;
            }
            Some(NaiveDate { year, month, day })
        }

        pub fn to_epoch_secs(&self) -> i64 {
            let y = self.year as i64 - if self.month <= 2 { 1 } else { 0 };
            let era = if y >= 0 { y } else { y - 399 } / 400;
            let yoe = (y - era * 400) as u32;
            let m = if self.month > 2 { self.month - 3 } else { self.month + 9 };
            let doy = (153 * m + 2) / 5 + self.day - 1;
            let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
            let days = era * 146097 + doe as i64 - 719468;
            days * 86400
        }

        pub fn format(&self) -> String {
            format!("{:04}-{:02}-{:02}", self.year, self.month, self.day)
        }
    }
}

pub fn format_epoch_date(epoch_secs: u64) -> String {
    chrono_mock::NaiveDate::from_timestamp_opt(epoch_secs).format()
}

pub fn parse_date_str_to_ms(s: &str) -> Option<i64> {
    chrono_mock::NaiveDate::parse(s).map(|d| d.to_epoch_secs() * 1000)
}

// ============================================================================
// Métricas, Analítica y Reportes (Fase 4)
// ============================================================================

#[derive(Debug, Clone, PartialEq)]
pub struct CategorySpendingItem {
    pub category_id: Option<String>,
    pub name: String,
    pub color: String,
    pub icon: String,
    pub total_cents: i64,
    pub percentage: f64,
    pub transaction_count: i32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CategorySpendingReport {
    pub currency: String,
    pub total_cents: i64,
    pub items: Vec<CategorySpendingItem>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct MonthlyCashflowItem {
    pub year: i32,
    pub month: i32,
    pub income_cents: i64,
    pub expense_cents: i64,
    pub net_cents: i64,
    pub currency: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct InstallmentProjectionItem {
    pub cycle_year: i32,
    pub cycle_month: i32,
    pub total_cents: i64,
    pub count: i32,
    pub currency: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct FinancialKpis {
    pub total_income_cents: i64,
    pub total_expense_cents: i64,
    pub net_savings_cents: i64,
    pub savings_rate: f64,
    pub top_category_name: Option<String>,
    pub top_category_cents: Option<i64>,
}

/// Reporte de gastos desglosados por categoría para un rango de fechas y moneda.
pub fn get_category_spending_report(
    conn: &Connection,
    start_ms: i64,
    end_ms: i64,
    currency: &str,
) -> Result<CategorySpendingReport, String> {
    let mut stmt = conn
        .prepare(
            "SELECT
                t.category_id,
                COALESCE(MAX(c.name), 'Sin categoría'),
                COALESCE(MAX(c.color), '#9E9E9E'),
                COALESCE(MAX(c.icon), 'category'),
                SUM(t.amount) as cat_total,
                COUNT(t.id) as tx_count
             FROM transactions t
             LEFT JOIN categories c ON t.category_id = c.id
             WHERE t.deleted_at IS NULL
               AND t.currency = ?1
               AND t.transaction_type = 'expense'
               AND t.date >= ?2
               AND t.date <= ?3
             GROUP BY t.category_id
             ORDER BY cat_total DESC",
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map(params![currency, start_ms, end_ms], |row| {
            let cat_id_raw: Option<Vec<u8>> = row.get(0)?;
            let cat_id_str = cat_id_raw.and_then(|raw| {
                if raw.len() == 16 {
                    let mut b = [0u8; 16];
                    b.copy_from_slice(&raw);
                    Some(Uuid::from_bytes(b).to_string())
                } else {
                    None
                }
            });
            let name: String = row.get(1)?;
            let color: String = row.get(2)?;
            let icon: String = row.get(3)?;
            let total_cents: i64 = row.get(4)?;
            let count: i32 = row.get(5)?;

            Ok((cat_id_str, name, color, icon, total_cents, count))
        })
        .map_err(|e| e.to_string())?;

    let mut raw_items = Vec::new();
    let mut grand_total: i64 = 0;
    for r in rows {
        let item = r.map_err(|e| e.to_string())?;
        grand_total += item.4;
        raw_items.push(item);
    }

    let items = raw_items
        .into_iter()
        .map(|(id, name, color, icon, cents, count)| {
            let pct = if grand_total > 0 {
                ((cents as f64 / grand_total as f64) * 10000.0).round() / 100.0
            } else {
                0.0
            };
            CategorySpendingItem {
                category_id: id,
                name,
                color,
                icon,
                total_cents: cents,
                percentage: pct,
                transaction_count: count,
            }
        })
        .collect();

    Ok(CategorySpendingReport {
        currency: currency.to_string(),
        total_cents: grand_total,
        items,
    })
}

/// Historial mensual de flujo de caja (ingresos vs gastos) para los últimos `months_limit` meses.
pub fn get_monthly_cashflow(
    conn: &Connection,
    currency: &str,
    months_limit: i32,
) -> Result<Vec<MonthlyCashflowItem>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT transaction_type, amount, date
             FROM transactions
             WHERE deleted_at IS NULL
               AND currency = ?1
               AND transaction_type IN ('expense', 'income')
             ORDER BY date ASC",
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map(params![currency], |row| {
            let ttype: String = row.get(0)?;
            let amount: i64 = row.get(1)?;
            let date_ms: i64 = row.get(2)?;
            Ok((ttype, amount, date_ms))
        })
        .map_err(|e| e.to_string())?;

    let mut month_map: BTreeMap<(i32, i32), (i64, i64)> = BTreeMap::new();

    for r in rows {
        let (ttype, amount, date_ms) = r.map_err(|e| e.to_string())?;
        let secs = (date_ms.max(0) / 1000) as u64;
        let d = chrono_mock::NaiveDate::from_timestamp_opt(secs);
        let entry = month_map.entry((d.year, d.month as i32)).or_insert((0, 0));
        match ttype.as_str() {
            "income" => entry.0 += amount,
            "expense" => entry.1 += amount,
            _ => {}
        }
    }

    let all_items: Vec<MonthlyCashflowItem> = month_map
        .into_iter()
        .map(|((y, m), (inc, exp))| MonthlyCashflowItem {
            year: y,
            month: m,
            income_cents: inc,
            expense_cents: exp,
            net_cents: inc - exp,
            currency: currency.to_string(),
        })
        .collect();

    let limit = months_limit.max(1) as usize;
    if all_items.len() > limit {
        let skip = all_items.len() - limit;
        Ok(all_items.into_iter().skip(skip).collect())
    } else {
        Ok(all_items)
    }
}

/// Proyección de compromisos de cuotas de tarjetas de crédito pendientes agrupadas por ciclo.
pub fn get_installment_projections(
    conn: &Connection,
    currency: &str,
) -> Result<Vec<InstallmentProjectionItem>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT i.cycle_year, i.cycle_month, SUM(i.amount), COUNT(i.id)
             FROM installments i
             JOIN accounts a ON i.account_id = a.id
             WHERE i.deleted_at IS NULL AND i.status = 'pending' AND a.currency = ?1
             GROUP BY i.cycle_year, i.cycle_month
             ORDER BY i.cycle_year ASC, i.cycle_month ASC",
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map(params![currency], |row| {
            let y: i32 = row.get(0)?;
            let m: i32 = row.get(1)?;
            let total: i64 = row.get(2)?;
            let count: i32 = row.get(3)?;
            Ok(InstallmentProjectionItem {
                cycle_year: y,
                cycle_month: m,
                total_cents: total,
                count,
                currency: currency.to_string(),
            })
        })
        .map_err(|e| e.to_string())?;

    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| e.to_string())?);
    }
    Ok(out)
}

/// KPIs financieros del período (ingresos, gastos, superávit/déficit, tasa de ahorro y categoría líder).
pub fn get_financial_kpis(
    conn: &Connection,
    start_ms: i64,
    end_ms: i64,
    currency: &str,
) -> Result<FinancialKpis, String> {
    let mut stmt = conn
        .prepare(
            "SELECT transaction_type, SUM(amount)
             FROM transactions
             WHERE deleted_at IS NULL
               AND currency = ?1
               AND transaction_type IN ('expense', 'income')
               AND date >= ?2
               AND date <= ?3
             GROUP BY transaction_type",
        )
        .map_err(|e| e.to_string())?;

    let mut income = 0i64;
    let mut expense = 0i64;

    let rows = stmt
        .query_map(params![currency, start_ms, end_ms], |row| {
            let ttype: String = row.get(0)?;
            let sum: i64 = row.get(1)?;
            Ok((ttype, sum))
        })
        .map_err(|e| e.to_string())?;

    for r in rows {
        let (ttype, sum) = r.map_err(|e| e.to_string())?;
        match ttype.as_str() {
            "income" => income += sum,
            "expense" => expense += sum,
            _ => {}
        }
    }

    let net = income - expense;
    let savings_rate = if income > 0 {
        ((net as f64 / income as f64) * 10000.0).round() / 100.0
    } else {
        0.0
    };

    let top = conn
        .query_row(
            "SELECT
                COALESCE(MAX(c.name), 'Sin categoría'),
                SUM(t.amount) as cat_total
             FROM transactions t
             LEFT JOIN categories c ON t.category_id = c.id
             WHERE t.deleted_at IS NULL
               AND t.currency = ?1
               AND t.transaction_type = 'expense'
               AND t.date >= ?2
               AND t.date <= ?3
             GROUP BY t.category_id
             ORDER BY cat_total DESC
             LIMIT 1",
            params![currency, start_ms, end_ms],
            |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)),
        )
        .optional()
        .map_err(|e| e.to_string())?;

    let (top_name, top_cents) = match top {
        Some((name, cents)) => (Some(name), Some(cents)),
        None => (None, None),
    };

    Ok(FinancialKpis {
        total_income_cents: income,
        total_expense_cents: expense,
        net_savings_cents: net,
        savings_rate,
        top_category_name: top_name,
        top_category_cents: top_cents,
    })
}

// ============================================================================
// Presupuestos y Metas de Ahorro (Fase 5)
// ============================================================================

#[derive(Debug, Clone, PartialEq)]
pub struct BudgetStatus {
    pub id: String,
    pub category_id: String,
    pub category_name: String,
    pub category_color: String,
    pub category_icon: String,
    pub currency: String,
    pub budget_amount_cents: i64,
    pub spent_amount_cents: i64,
    pub remaining_amount_cents: i64,
    pub spent_percentage: f64,
    pub is_over_budget: bool,
    pub is_warning: bool,
}

/// Define o actualiza el límite presupuestario mensual de una categoría.
pub fn set_category_budget(
    conn: &Connection,
    category_id: &[u8; 16],
    currency: &str,
    amount_cents: i64,
    alert_percentage: i32,
) -> Result<String, String> {
    if amount_cents <= 0 {
        return Err("El monto del presupuesto debe ser mayor a 0".into());
    }
    let now = now_ms();

    let existing_id: Option<Vec<u8>> = conn
        .query_row(
            "SELECT id FROM budgets WHERE category_id = ?1 AND currency = ?2 AND deleted_at IS NULL",
            params![category_id.as_slice(), currency],
            |r| r.get(0),
        )
        .optional()
        .map_err(|e| e.to_string())?;

    if let Some(raw_id) = existing_id {
        conn.execute(
            "UPDATE budgets SET amount = ?1, alert_percentage = ?2, updated_at = ?3 WHERE id = ?4",
            params![amount_cents, alert_percentage, now, raw_id.as_slice()],
        )
        .map_err(|e| e.to_string())?;

        let mut b = [0u8; 16];
        b.copy_from_slice(&raw_id);
        Ok(Uuid::from_bytes(b).to_string())
    } else {
        let budget_id = Uuid::now_v7();
        conn.execute(
            "INSERT INTO budgets (id, category_id, currency, amount, alert_percentage, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)",
            params![
                budget_id.as_bytes().as_slice(),
                category_id.as_slice(),
                currency,
                amount_cents,
                alert_percentage,
                now
            ],
        )
        .map_err(|e| e.to_string())?;
        Ok(budget_id.to_string())
    }
}

/// Consulta el estado de todos los presupuestos activos contra los gastos del período [start_ms, end_ms].
pub fn list_budgets_status(
    conn: &Connection,
    start_ms: i64,
    end_ms: i64,
    currency: &str,
) -> Result<Vec<BudgetStatus>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT b.id, b.category_id, c.name, c.color, c.icon, b.currency, b.amount, b.alert_percentage
             FROM budgets b
             JOIN categories c ON b.category_id = c.id
             WHERE b.deleted_at IS NULL AND b.currency = ?1
             ORDER BY b.amount DESC",
        )
        .map_err(|e| e.to_string())?;

    let budget_rows = stmt
        .query_map(params![currency], |row| {
            let b_id_raw: Vec<u8> = row.get(0)?;
            let c_id_raw: Vec<u8> = row.get(1)?;
            let c_name: String = row.get(2)?;
            let c_color: String = row.get(3)?;
            let c_icon: String = row.get(4)?;
            let curr: String = row.get(5)?;
            let limit: i64 = row.get(6)?;
            let alert_pct: i32 = row.get(7)?;

            let mut b_id = [0u8; 16];
            b_id.copy_from_slice(&b_id_raw);
            let mut c_id = [0u8; 16];
            c_id.copy_from_slice(&c_id_raw);

            Ok((
                Uuid::from_bytes(b_id).to_string(),
                c_id,
                Uuid::from_bytes(c_id).to_string(),
                c_name,
                c_color,
                c_icon,
                curr,
                limit,
                alert_pct,
            ))
        })
        .map_err(|e| e.to_string())?;

    let mut out = Vec::new();
    for r in budget_rows {
        let (bid_str, cid_bytes, cid_str, cname, ccolor, cicon, curr, limit_cents, alert_pct) =
            r.map_err(|e| e.to_string())?;

        let spent: i64 = conn
            .query_row(
                "SELECT COALESCE(SUM(amount), 0)
                 FROM transactions
                 WHERE deleted_at IS NULL
                   AND category_id = ?1
                   AND currency = ?2
                   AND transaction_type = 'expense'
                   AND date >= ?3
                   AND date <= ?4",
                params![cid_bytes.as_slice(), curr, start_ms, end_ms],
                |row| row.get(0),
            )
            .unwrap_or(0);

        let remaining = limit_cents - spent;
        let pct = if limit_cents > 0 {
            ((spent as f64 / limit_cents as f64) * 10000.0).round() / 100.0
        } else {
            0.0
        };

        let is_over = spent > limit_cents;
        let is_warn = pct >= alert_pct as f64;

        out.push(BudgetStatus {
            id: bid_str,
            category_id: cid_str,
            category_name: cname,
            category_color: ccolor,
            category_icon: cicon,
            currency: curr,
            budget_amount_cents: limit_cents,
            spent_amount_cents: spent,
            remaining_amount_cents: remaining,
            spent_percentage: pct,
            is_over_budget: is_over,
            is_warning: is_warn,
        });
    }

    Ok(out)
}

/// Elimina un presupuesto (soft-delete).
pub fn delete_budget(conn: &Connection, budget_id: &[u8; 16]) -> Result<bool, String> {
    let now = now_ms();
    let rows = conn
        .execute(
            "UPDATE budgets SET deleted_at = ?1 WHERE id = ?2 AND deleted_at IS NULL",
            params![now, budget_id.as_slice()],
        )
        .map_err(|e| e.to_string())?;
    Ok(rows > 0)
}

#[derive(Debug, Clone, PartialEq)]
pub struct SavingGoalRecord {
    pub id: String,
    pub name: String,
    pub target_amount_cents: i64,
    pub current_amount_cents: i64,
    pub currency: String,
    pub target_date: Option<i64>,
    pub color: String,
    pub icon: String,
    pub status: String,
}

/// Crea una nueva meta de ahorro.
pub fn create_saving_goal(
    conn: &Connection,
    name: &str,
    target_amount_cents: i64,
    currency: &str,
    target_date: Option<i64>,
    color: &str,
    icon: &str,
) -> Result<String, String> {
    if target_amount_cents <= 0 {
        return Err("El monto objetivo debe ser mayor a 0".into());
    }
    let id = Uuid::now_v7();
    let now = now_ms();
    conn.execute(
        "INSERT INTO saving_goals (id, name, target_amount, currency, target_date, color, icon, current_amount, status, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 0, 'active', ?8, ?8)",
        params![
            id.as_bytes().as_slice(),
            name,
            target_amount_cents,
            currency,
            target_date,
            color,
            icon,
            now,
        ],
    )
    .map_err(|e| e.to_string())?;
    Ok(id.to_string())
}

/// Lista todas las metas de ahorro activas o pausadas.
pub fn list_saving_goals(conn: &Connection) -> Result<Vec<SavingGoalRecord>, String> {
    let mut stmt = conn
        .prepare(
            "SELECT id, name, target_amount, current_amount, currency, target_date, color, icon, status
             FROM saving_goals
             WHERE deleted_at IS NULL
             ORDER BY created_at DESC",
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map([], |row| {
            let id_raw: Vec<u8> = row.get(0)?;
            let mut id_bytes = [0u8; 16];
            id_bytes.copy_from_slice(&id_raw);

            Ok(SavingGoalRecord {
                id: Uuid::from_bytes(id_bytes).to_string(),
                name: row.get(1)?,
                target_amount_cents: row.get(2)?,
                current_amount_cents: row.get(3)?,
                currency: row.get(4)?,
                target_date: row.get(5)?,
                color: row.get(6)?,
                icon: row.get(7)?,
                status: row.get(8)?,
            })
        })
        .map_err(|e| e.to_string())?;

    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| e.to_string())?);
    }
    Ok(out)
}

/// Registra un aporte (positivo o negativo) a una meta de ahorro.
pub fn contribute_to_saving_goal(
    conn: &Connection,
    goal_id: &[u8; 16],
    amount_cents: i64,
) -> Result<i64, String> {
    let now = now_ms();
    let current: i64 = conn
        .query_row(
            "SELECT current_amount FROM saving_goals WHERE id = ?1 AND deleted_at IS NULL",
            params![goal_id.as_slice()],
            |r| r.get(0),
        )
        .map_err(|e| format!("Meta de ahorro no encontrada: {e}"))?;

    let new_amount = (current + amount_cents).max(0);
    let target: i64 = conn
        .query_row(
            "SELECT target_amount FROM saving_goals WHERE id = ?1 AND deleted_at IS NULL",
            params![goal_id.as_slice()],
            |r| r.get(0),
        )
        .unwrap_or(0);

    let status = if new_amount >= target && target > 0 {
        "completed"
    } else {
        "active"
    };

    conn.execute(
        "UPDATE saving_goals SET current_amount = ?1, status = ?2, updated_at = ?3 WHERE id = ?4",
        params![new_amount, status, now, goal_id.as_slice()],
    )
    .map_err(|e| e.to_string())?;

    Ok(new_amount)
}

/// Elimina una meta de ahorro (soft-delete).
pub fn delete_saving_goal(conn: &Connection, goal_id: &[u8; 16]) -> Result<bool, String> {
    let now = now_ms();
    let rows = conn
        .execute(
            "UPDATE saving_goals SET deleted_at = ?1 WHERE id = ?2 AND deleted_at IS NULL",
            params![now, goal_id.as_slice()],
        )
        .map_err(|e| e.to_string())?;
    Ok(rows > 0)
}

// ============================================================================
// Operaciones CRUD y Consultas Avanzadas (Fase 7-9)
// ============================================================================

/// Elimina un movimiento de forma suave (soft-delete) y revierte cuotas asociadas si existen.
pub fn soft_delete_transaction(conn: &Connection, id: &[u8; 16]) -> Result<bool, String> {
    let now = now_ms();
    let affected = conn
        .execute(
            "UPDATE transactions SET deleted_at = ?1, updated_at = ?1 WHERE id = ?2 AND deleted_at IS NULL",
            params![now, id.as_slice()],
        )
        .map_err(|e| e.to_string())?;

    if affected > 0 {
        let _ = conn.execute(
            "UPDATE installments SET deleted_at = ?1, updated_at = ?1 WHERE transaction_id = ?2 AND deleted_at IS NULL",
            params![now, id.as_slice()],
        );
        Ok(true)
    } else {
        Ok(false)
    }
}

/// Restaura un movimiento previamente eliminado (undo de borrado).
pub fn restore_transaction(conn: &Connection, id: &[u8; 16]) -> Result<bool, String> {
    let now = now_ms();
    let affected = conn
        .execute(
            "UPDATE transactions SET deleted_at = NULL, updated_at = ?1 WHERE id = ?2 AND deleted_at IS NOT NULL",
            params![now, id.as_slice()],
        )
        .map_err(|e| e.to_string())?;

    if affected > 0 {
        let _ = conn.execute(
            "UPDATE installments SET deleted_at = NULL, updated_at = ?1 WHERE transaction_id = ?2",
            params![now, id.as_slice()],
        );
        Ok(true)
    } else {
        Ok(false)
    }
}

/// Actualiza un movimiento existente (monto, tipo, categoría, notas, fecha y opcionalmente cuenta).
#[allow(clippy::too_many_arguments)]
pub fn update_transaction(
    conn: &Connection,
    id: &[u8; 16],
    tipo: &str,
    monto_centavos: i64,
    moneda: &str,
    categoria: &str,
    descripcion: &str,
    fecha_ms: i64,
    account_id: Option<&[u8; 16]>,
) -> Result<bool, String> {
    if monto_centavos <= 0 {
        return Err("El monto debe ser mayor a 0".to_string());
    }
    let cat_id = get_or_create_category(conn, categoria)?;
    let now = now_ms();
    let ttype = match tipo {
        "income" | "ingreso" => "income",
        "expense" | "gasto" => "expense",
        "transfer" | "transferencia" => "transfer",
        other => other,
    };

    let affected = if let Some(acc_id) = account_id {
        conn.execute(
            "UPDATE transactions
             SET transaction_type = ?1, amount = ?2, currency = ?3, category_id = ?4,
                 notes = ?5, date = ?6, account_id = ?7, updated_at = ?8
             WHERE id = ?9 AND deleted_at IS NULL",
            params![
                ttype,
                monto_centavos,
                moneda,
                cat_id.as_slice(),
                descripcion,
                fecha_ms,
                acc_id.as_slice(),
                now,
                id.as_slice()
            ],
        )
        .map_err(|e| e.to_string())?
    } else {
        conn.execute(
            "UPDATE transactions
             SET transaction_type = ?1, amount = ?2, currency = ?3, category_id = ?4,
                 notes = ?5, date = ?6, updated_at = ?7
             WHERE id = ?8 AND deleted_at IS NULL",
            params![
                ttype,
                monto_centavos,
                moneda,
                cat_id.as_slice(),
                descripcion,
                fecha_ms,
                now,
                id.as_slice()
            ],
        )
        .map_err(|e| e.to_string())?
    };

    Ok(affected > 0)
}

/// Búsqueda y filtrado multicriterio de movimientos con paginación.
#[allow(clippy::too_many_arguments)]
pub fn search_transactions(
    conn: &Connection,
    query_text: Option<&str>,
    start_date_ms: Option<i64>,
    end_date_ms: Option<i64>,
    category_id: Option<&[u8; 16]>,
    account_id: Option<&[u8; 16]>,
    tipo: Option<&str>,
    limit: i64,
    offset: i64,
) -> Result<Vec<Movement>, String> {
    let mut sql = String::from(
        "SELECT t.id, t.transaction_type, t.amount, t.currency,
                COALESCE(c.name, 'general'), t.notes, t.date,
                t.account_id, COALESCE(a.name, 'General')
         FROM transactions t
         LEFT JOIN categories c ON t.category_id = c.id
         LEFT JOIN accounts a ON t.account_id = a.id
         WHERE t.deleted_at IS NULL",
    );

    let mut params_vec: Vec<Box<dyn rusqlite::ToSql>> = Vec::new();

    if let Some(q) = query_text {
        let trimmed = q.trim();
        if !trimmed.is_empty() {
            let pattern = format!("%{trimmed}%");
            params_vec.push(Box::new(pattern));
            let idx = params_vec.len();
            sql.push_str(&format!(
                " AND (t.notes LIKE ?{idx} OR t.raw_prompt LIKE ?{idx} OR c.name LIKE ?{idx})"
            ));
        }
    }

    if let Some(s) = start_date_ms {
        params_vec.push(Box::new(s));
        let idx = params_vec.len();
        sql.push_str(&format!(" AND t.date >= ?{idx}"));
    }

    if let Some(e) = end_date_ms {
        params_vec.push(Box::new(e));
        let idx = params_vec.len();
        sql.push_str(&format!(" AND t.date <= ?{idx}"));
    }

    if let Some(cat) = category_id {
        params_vec.push(Box::new(cat.to_vec()));
        let idx = params_vec.len();
        sql.push_str(&format!(" AND t.category_id = ?{idx}"));
    }

    if let Some(acc) = account_id {
        params_vec.push(Box::new(acc.to_vec()));
        let idx = params_vec.len();
        sql.push_str(&format!(" AND t.account_id = ?{idx}"));
    }

    if let Some(tp) = tipo {
        let normalized = match tp {
            "income" | "ingreso" => "income",
            "expense" | "gasto" => "expense",
            "transfer" | "transferencia" => "transfer",
            other => other,
        };
        params_vec.push(Box::new(normalized.to_string()));
        let idx = params_vec.len();
        sql.push_str(&format!(" AND t.transaction_type = ?{idx}"));
    }

    sql.push_str(" ORDER BY t.date DESC, t.created_at DESC, t.rowid DESC LIMIT ?");
    params_vec.push(Box::new(limit.max(1)));
    let limit_idx = params_vec.len();

    sql.push_str(&format!(" OFFSET ?{}", limit_idx + 1));
    params_vec.push(Box::new(offset.max(0)));

    let mut stmt = conn.prepare(&sql).map_err(|e| e.to_string())?;

    let param_refs: Vec<&dyn rusqlite::ToSql> = params_vec.iter().map(|p| p.as_ref()).collect();

    let rows = stmt
        .query_map(param_refs.as_slice(), |row| {
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
            }
            .to_string();
            let centavos: i64 = row.get(2)?;
            let moneda: String = row.get(3)?;
            let cat: String = row.get(4)?;
            let desc: String = row.get(5)?;
            let date_ms: i64 = row.get(6)?;

            let acc_blob: Option<Vec<u8>> = row.get(7)?;
            let acc_id_str = acc_blob.and_then(|b| {
                if b.len() == 16 {
                    let mut arr = [0u8; 16];
                    arr.copy_from_slice(&b);
                    Some(Uuid::from_bytes(arr).to_string())
                } else {
                    None
                }
            });
            let acc_name: Option<String> = row.get(8)?;

            let secs = (date_ms.max(0) / 1000) as u64;
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
                account_id: acc_id_str,
                account_name: acc_name,
            })
        })
        .map_err(|e| e.to_string())?;

    let mut out = Vec::new();
    for r in rows {
        out.push(r.map_err(|e| e.to_string())?);
    }
    Ok(out)
}

#[derive(Debug, Clone, PartialEq)]
pub struct HomeSummary {
    pub total_balance: f64,
    pub monthly_expense: f64,
    pub monthly_income: f64,
    pub prev_month_expense: f64,
    pub delta_expense_pct: Option<f64>,
    pub currency: String,
}

/// Resumen financiero para el Home Tab (saldo consolidado por moneda, ingresos/gastos del mes y delta porcentual).
pub fn get_home_summary(conn: &Connection, currency: &str) -> Result<HomeSummary, String> {
    let accounts = list_accounts(conn)?;
    let mut total_balance_cents = 0i64;
    for acc in &accounts {
        if acc.currency.eq_ignore_ascii_case(currency) && acc.account_type != "credit_card" {
            total_balance_cents += (acc.current_balance * 100.0).round() as i64;
        }
    }

    let now = now_ms();
    let now_secs = (now / 1000) as u64;
    let curr_date = chrono_mock::NaiveDate::from_timestamp_opt(now_secs);
    let curr_year = curr_date.year;
    let curr_month = curr_date.month as i32;

    let (prev_year, prev_month) = if curr_month == 1 {
        (curr_year - 1, 12)
    } else {
        (curr_year, curr_month - 1)
    };

    let mut stmt = conn
        .prepare(
            "SELECT transaction_type, amount, date
             FROM transactions
             WHERE deleted_at IS NULL
               AND currency = ?1
               AND transaction_type IN ('expense', 'income')",
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map(params![currency], |row| {
            let ttype: String = row.get(0)?;
            let amt: i64 = row.get(1)?;
            let date_ms: i64 = row.get(2)?;
            Ok((ttype, amt, date_ms))
        })
        .map_err(|e| e.to_string())?;

    let mut monthly_expense_cents = 0i64;
    let mut monthly_income_cents = 0i64;
    let mut prev_month_expense_cents = 0i64;

    for r in rows {
        let (ttype, amt, date_ms) = r.map_err(|e| e.to_string())?;
        let secs = (date_ms.max(0) / 1000) as u64;
        let d = chrono_mock::NaiveDate::from_timestamp_opt(secs);

        if d.year == curr_year && d.month as i32 == curr_month {
            if ttype == "expense" {
                monthly_expense_cents += amt;
            } else if ttype == "income" {
                monthly_income_cents += amt;
            }
        } else if d.year == prev_year && d.month as i32 == prev_month && ttype == "expense" {
            prev_month_expense_cents += amt;
        }
    }

    let delta_expense_pct = if prev_month_expense_cents > 0 {
        let delta = ((monthly_expense_cents - prev_month_expense_cents) as f64
            / prev_month_expense_cents as f64)
            * 100.0;
        Some((delta * 10.0).round() / 10.0)
    } else {
        None
    };

    Ok(HomeSummary {
        total_balance: total_balance_cents as f64 / 100.0,
        monthly_expense: monthly_expense_cents as f64 / 100.0,
        monthly_income: monthly_income_cents as f64 / 100.0,
        prev_month_expense: prev_month_expense_cents as f64 / 100.0,
        delta_expense_pct,
        currency: currency.to_string(),
    })
}

#[derive(Debug, Clone, PartialEq)]
pub struct UsageStreak {
    pub current_streak: i32,
    pub max_streak: i32,
    pub active_today: bool,
}

/// Calcula la racha de días consecutivos con al menos una transacción registrada.
pub fn get_usage_streak(conn: &Connection) -> Result<UsageStreak, String> {
    let mut stmt = conn
        .prepare(
            "SELECT DISTINCT date
             FROM transactions
             WHERE deleted_at IS NULL
             ORDER BY date ASC",
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map([], |row| {
            let date_ms: i64 = row.get(0)?;
            Ok(date_ms)
        })
        .map_err(|e| e.to_string())?;

    let mut days_set = std::collections::BTreeSet::new();
    for r in rows {
        let ms = r.map_err(|e| e.to_string())?;
        let day_idx = ms / 86_400_000;
        days_set.insert(day_idx);
    }

    if days_set.is_empty() {
        return Ok(UsageStreak {
            current_streak: 0,
            max_streak: 0,
            active_today: false,
        });
    }

    let now = now_ms();
    let today_day_idx = now / 86_400_000;
    let active_today = days_set.contains(&today_day_idx);

    let start_check = if active_today {
        today_day_idx
    } else {
        today_day_idx - 1
    };

    let mut current_streak = 0;
    let mut cur = start_check;
    while days_set.contains(&cur) {
        current_streak += 1;
        cur -= 1;
    }

    let mut max_streak = 0;
    let mut temp_streak = 0;
    let mut prev_day: Option<i64> = None;

    for &day in &days_set {
        match prev_day {
            Some(p) if day == p + 1 => {
                temp_streak += 1;
            }
            _ => {
                temp_streak = 1;
            }
        }
        if temp_streak > max_streak {
            max_streak = temp_streak;
        }
        prev_day = Some(day);
    }

    Ok(UsageStreak {
        current_streak,
        max_streak,
        active_today,
    })
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

    #[test]
    fn test_analytics_and_metrics_reports() {
        let conn = mem();
        let accounts = list_accounts(&conn).unwrap();
        let cash = &accounts[0];
        let cash_uuid = Uuid::parse_str(&cash.id).unwrap();
        let cash_bytes = cash_uuid.as_bytes();
        let now = now_ms();
        let start_ms = now - 86400 * 1000;
        let end_ms = now + 86400 * 1000;

        // Categorías
        let cat_super_id = get_or_create_category(&conn, "Supermercado").unwrap();
        let cat_transp_id = get_or_create_category(&conn, "Transporte").unwrap();

        // 1. Ingreso de 500.000 ARS
        insert_with_account(
            &conn,
            Some(cash_bytes),
            &Ingreso,
            500000.0,
            "ARS",
            "sueldo",
            "Sueldo mensual",
            "2026-09-30",
            "sueldo",
        ).unwrap();

        // 2. Gastos categorizados
        let mut conn_mut = conn;
        let tx = conn_mut.transaction().unwrap();
        let tx1_id = Uuid::now_v7();
        tx.execute(
            "INSERT INTO transactions (id, account_id, category_id, transaction_type, amount, currency, notes, date, raw_prompt, created_at, updated_at)
             VALUES (?1, ?2, ?3, 'expense', 5000000, 'ARS', 'Compras coto', ?4, 'coto 50k', ?4, ?4)",
            params![tx1_id.as_bytes().as_slice(), cash_bytes.as_slice(), cat_super_id.as_slice(), now],
        ).unwrap();
        // Gasto 2: 25.000 ARS en Transporte
        let tx2_id = Uuid::now_v7();
        tx.execute(
            "INSERT INTO transactions (id, account_id, category_id, transaction_type, amount, currency, notes, date, raw_prompt, created_at, updated_at)
             VALUES (?1, ?2, ?3, 'expense', 2500000, 'ARS', 'Carga sube', ?4, 'sube 25k', ?4, ?4)",
            params![tx2_id.as_bytes().as_slice(), cash_bytes.as_slice(), cat_transp_id.as_slice(), now],
        ).unwrap();
        tx.commit().unwrap();
        let conn = conn_mut;

        // Test Category Spending Report
        let cat_report = get_category_spending_report(&conn, start_ms, end_ms, "ARS").unwrap();
        assert_eq!(cat_report.currency, "ARS");
        assert_eq!(cat_report.total_cents, 7500000);
        assert_eq!(cat_report.items.len(), 2);
        assert_eq!(cat_report.items[0].name, "supermercado");
        assert_eq!(cat_report.items[0].total_cents, 5000000);
        assert_eq!(cat_report.items[0].percentage, 66.67);
        assert_eq!(cat_report.items[1].name, "transporte");
        assert_eq!(cat_report.items[1].total_cents, 2500000);
        assert_eq!(cat_report.items[1].percentage, 33.33);

        // Test KPIs
        let kpis = get_financial_kpis(&conn, start_ms, end_ms, "ARS").unwrap();
        assert_eq!(kpis.total_income_cents, 50000000);
        assert_eq!(kpis.total_expense_cents, 7500000);
        assert_eq!(kpis.net_savings_cents, 42500000);
        assert_eq!(kpis.savings_rate, 85.0);
        assert_eq!(kpis.top_category_name.as_deref(), Some("supermercado"));
        assert_eq!(kpis.top_category_cents, Some(5000000));

        // Test Monthly Cashflow
        let cashflow = get_monthly_cashflow(&conn, "ARS", 6).unwrap();
        assert!(!cashflow.is_empty());
        let last_cf = cashflow.last().unwrap();
        assert_eq!(last_cf.income_cents, 50000000);
        assert_eq!(last_cf.expense_cents, 7500000);
        assert_eq!(last_cf.net_cents, 42500000);

        // Test Installments Projection con tarjeta de crédito
        let card_id_str = create_account(
            &conn,
            "Visa Test",
            &AccountType::CreditCard,
            "ARS",
            0,
            Some(100000000),
            Some(20),
            Some(10),
            "#000000",
            "credit_card",
        ).unwrap();
        let card_uuid = Uuid::parse_str(&card_id_str).unwrap();

        insert_credit_purchase(
            &conn,
            card_uuid.as_bytes(),
            Some(&cat_super_id),
            3000000, // 30.000 ARS en 3 cuotas de 10.000
            3,
            now,
            2026,
            10,
            "Super en 3 cuotas",
            "super 3 cuotas",
        ).unwrap();

        let proj = get_installment_projections(&conn, "ARS").unwrap();
        assert_eq!(proj.len(), 3);
        assert_eq!(proj[0].cycle_year, 2026);
        assert_eq!(proj[0].cycle_month, 10);
        assert_eq!(proj[0].total_cents, 1000000);
        assert_eq!(proj[1].cycle_month, 11);
        assert_eq!(proj[1].total_cents, 1000000);
        assert_eq!(proj[2].cycle_month, 12);
        assert_eq!(proj[2].total_cents, 1000000);
    }

    #[test]
    fn test_budgets_and_saving_goals_flow() {
        let conn = mem();
        let accounts = list_accounts(&conn).unwrap();
        let cash = &accounts[0];
        let cash_uuid = Uuid::parse_str(&cash.id).unwrap();
        let cash_bytes = cash_uuid.as_bytes();
        let now = now_ms();
        let start_ms = now - 86400 * 1000;
        let end_ms = now + 86400 * 1000;

        let cat_super_id = get_or_create_category(&conn, "Supermercado").unwrap();

        // 1. Presupuesto
        let b_id_str = set_category_budget(
            &conn,
            &cat_super_id,
            "ARS",
            10000000, // $100.000 ARS
            80,
        ).unwrap();
        let b_uuid = Uuid::parse_str(&b_id_str).unwrap();

        // Inicial: 0 gastado
        let status1 = list_budgets_status(&conn, start_ms, end_ms, "ARS").unwrap();
        assert_eq!(status1.len(), 1);
        assert_eq!(status1[0].budget_amount_cents, 10000000);
        assert_eq!(status1[0].spent_amount_cents, 0);
        assert_eq!(status1[0].remaining_amount_cents, 10000000);
        assert_eq!(status1[0].is_warning, false);
        assert_eq!(status1[0].is_over_budget, false);

        // Gasto de $85.000 (85%)
        let mut conn_mut = conn;
        let tx = conn_mut.transaction().unwrap();
        let tx1_id = Uuid::now_v7();
        tx.execute(
            "INSERT INTO transactions (id, account_id, category_id, transaction_type, amount, currency, notes, date, raw_prompt, created_at, updated_at)
             VALUES (?1, ?2, ?3, 'expense', 8500000, 'ARS', 'Gasto súper', ?4, 'super 85k', ?4, ?4)",
            params![tx1_id.as_bytes().as_slice(), cash_bytes.as_slice(), cat_super_id.as_slice(), now],
        ).unwrap();
        tx.commit().unwrap();
        let conn = conn_mut;

        let status2 = list_budgets_status(&conn, start_ms, end_ms, "ARS").unwrap();
        assert_eq!(status2[0].spent_amount_cents, 8500000);
        assert_eq!(status2[0].remaining_amount_cents, 1500000);
        assert_eq!(status2[0].spent_percentage, 85.0);
        assert_eq!(status2[0].is_warning, true);
        assert_eq!(status2[0].is_over_budget, false);

        // Borrar presupuesto
        assert!(delete_budget(&conn, b_uuid.as_bytes()).unwrap());
        let status3 = list_budgets_status(&conn, start_ms, end_ms, "ARS").unwrap();
        assert_eq!(status3.len(), 0);

        // 2. Metas de ahorro
        let goal_id_str = create_saving_goal(
            &conn,
            "Vacaciones Japón",
            200000000, // $2.000.000
            "ARS",
            Some(now + 86400 * 30 * 1000),
            "#2196F3",
            "flight",
        ).unwrap();
        let goal_uuid = Uuid::parse_str(&goal_id_str).unwrap();

        let goals = list_saving_goals(&conn).unwrap();
        assert_eq!(goals.len(), 1);
        assert_eq!(goals[0].name, "Vacaciones Japón");
        assert_eq!(goals[0].current_amount_cents, 0);
        assert_eq!(goals[0].status, "active");

        // Aporte parcial: $1.200.000
        let new_bal1 = contribute_to_saving_goal(&conn, goal_uuid.as_bytes(), 120000000).unwrap();
        assert_eq!(new_bal1, 120000000);
        let goals2 = list_saving_goals(&conn).unwrap();
        assert_eq!(goals2[0].current_amount_cents, 120000000);
        assert_eq!(goals2[0].status, "active");

        // Completar meta: $900.000 más ($2.100.000)
        let new_bal2 = contribute_to_saving_goal(&conn, goal_uuid.as_bytes(), 90000000).unwrap();
        assert_eq!(new_bal2, 210000000);
        let goals3 = list_saving_goals(&conn).unwrap();
        assert_eq!(goals3[0].status, "completed");

        // Borrar meta
        assert!(delete_saving_goal(&conn, goal_uuid.as_bytes()).unwrap());
        assert_eq!(list_saving_goals(&conn).unwrap().len(), 0);
    }

    #[test]
    fn test_crud_movements_soft_delete_and_restore() {
        let conn = mem();
        let id_str = insert(&conn, &Gasto, 1500.0, "ARS", "comida", "almuerzo", "2026-10-01", "gaste 1500").unwrap();
        let uuid = Uuid::parse_str(&id_str).unwrap();

        let initial_list = list(&conn, 10).unwrap();
        assert_eq!(initial_list.len(), 1);
        assert_eq!(initial_list[0].monto, 1500.0);

        // Soft delete
        let deleted = soft_delete_transaction(&conn, uuid.as_bytes()).unwrap();
        assert!(deleted);

        // Ya no aparece en list
        let after_delete = list(&conn, 10).unwrap();
        assert_eq!(after_delete.len(), 0);

        // Restore
        let restored = restore_transaction(&conn, uuid.as_bytes()).unwrap();
        assert!(restored);

        let after_restore = list(&conn, 10).unwrap();
        assert_eq!(after_restore.len(), 1);
    }

    #[test]
    fn test_crud_movements_update_and_search() {
        let conn = mem();
        let id_str = insert(&conn, &Gasto, 5000.0, "ARS", "supermercado", "coto", "2026-10-01", "gaste 5000").unwrap();
        let uuid = Uuid::parse_str(&id_str).unwrap();

        // Update
        let updated = update_transaction(
            &conn,
            uuid.as_bytes(),
            "gasto",
            650000, // 6500.00
            "ARS",
            "supermercado",
            "coto semanal",
            now_ms(),
            None,
        ).unwrap();
        assert!(updated);

        let all = list(&conn, 10).unwrap();
        assert_eq!(all[0].monto, 6500.0);
        assert_eq!(all[0].descripcion, "coto semanal");

        // Search by text
        let search_res = search_transactions(&conn, Some("semanal"), None, None, None, None, None, 10, 0).unwrap();
        assert_eq!(search_res.len(), 1);
        assert_eq!(search_res[0].id, id_str);

        let no_match = search_transactions(&conn, Some("inexistente"), None, None, None, None, None, 10, 0).unwrap();
        assert_eq!(no_match.len(), 0);
    }

    #[test]
    fn test_custom_categories_crud() {
        let conn = mem();
        let cat_id = create_category(&conn, "Mascotas", "pets", "#FF9800", None).unwrap();
        let cat_uuid = Uuid::from_bytes(cat_id);

        let cats = list_categories(&conn).unwrap();
        let found = cats.iter().find(|c| c.id == cat_uuid.to_string()).unwrap();
        assert_eq!(found.name, "Mascotas");
        assert_eq!(found.icon, "pets");
        assert!(!found.is_system);

        // Update
        assert!(update_category(&conn, &cat_id, "Veterinaria", "local_hospital", "#E91E63").unwrap());
        let cats2 = list_categories(&conn).unwrap();
        let found2 = cats2.iter().find(|c| c.id == cat_uuid.to_string()).unwrap();
        assert_eq!(found2.name, "Veterinaria");
        assert_eq!(found2.icon, "local_hospital");

        // Delete
        assert!(delete_category(&conn, &cat_id).unwrap());
        let cats3 = list_categories(&conn).unwrap();
        assert!(cats3.iter().find(|c| c.id == cat_uuid.to_string()).is_none());
    }

    #[test]
    fn test_home_summary_and_usage_streak() {
        let conn = mem();
        insert(&conn, &Ingreso, 100000.0, "ARS", "sueldo", "sueldo", "2026-10-01", "sueldo").unwrap();
        insert(&conn, &Gasto, 20000.0, "ARS", "comida", "cena", "2026-10-01", "cena").unwrap();

        let summary = get_home_summary(&conn, "ARS").unwrap();
        assert_eq!(summary.currency, "ARS");
        assert_eq!(summary.monthly_income, 100000.0);
        assert_eq!(summary.monthly_expense, 20000.0);

        let streak = get_usage_streak(&conn).unwrap();
        assert!(streak.active_today);
        assert_eq!(streak.current_streak, 1);
        assert_eq!(streak.max_streak, 1);
    }
}


