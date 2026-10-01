//! Módulo de exportación de datos y copias de seguridad cifradas (Fase 6).
//!
//! Soporta:
//! - Exportación de transacciones en CSV estándar RFC 4180.
//! - Exportación completa en JSON plano estructurado.
//! - Copias de seguridad cifradas (.mnbackup) con derivación de clave Argon2id
//!   y cifrado autenticado AES-256-GCM.
//! - Restauración atómica con validación criptográfica previa y transacción SQLite.

use aes_gcm::aead::{Aead, KeyInit, OsRng};
use aes_gcm::aead::rand_core::RngCore;
use aes_gcm::{Aes256Gcm, Nonce};
use argon2::{Algorithm, Argon2, Params, Version};
use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use zeroize::Zeroizing;

// Magic bytes identificadores para archivos .mnbackup: "MNBK"
pub const BACKUP_MAGIC: &[u8; 4] = b"MNBK";
pub const BACKUP_FORMAT_VERSION: u32 = 1;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BackupAccount {
    pub id: String, // 32 hex chars
    pub name: String,
    pub account_type: String,
    pub currency: String,
    pub initial_balance: i64,
    pub color: String,
    pub icon: String,
    pub credit_limit: Option<i64>,
    pub closing_day: Option<i32>,
    pub due_day: Option<i32>,
    pub created_at: i64,
    pub updated_at: i64,
    pub deleted_at: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BackupCategory {
    pub id: String,
    pub name: String,
    pub icon: String,
    pub color: String,
    pub parent_id: Option<String>,
    pub is_system: bool,
    pub created_at: i64,
    pub updated_at: i64,
    pub deleted_at: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BackupTransaction {
    pub id: String,
    pub account_id: String,
    pub category_id: Option<String>,
    pub transaction_type: String,
    pub amount: i64,
    pub currency: String,
    pub destination_account_id: Option<String>,
    pub destination_amount: Option<i64>,
    pub exchange_rate_snapshot: Option<i64>,
    pub notes: String,
    pub date: i64,
    pub raw_prompt: String,
    pub recurring_rule_id: Option<String>,
    pub scheduled_date: Option<i64>,
    pub created_at: i64,
    pub updated_at: i64,
    pub deleted_at: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BackupInstallment {
    pub id: String,
    pub transaction_id: String,
    pub account_id: String,
    pub installment_number: i32,
    pub total_installments: i32,
    pub amount: i64,
    pub cycle_year: i32,
    pub cycle_month: i32,
    pub due_date: i64,
    pub status: String,
    pub created_at: i64,
    pub updated_at: i64,
    pub deleted_at: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BackupRecurringRule {
    pub id: String,
    pub account_id: String,
    pub category_id: Option<String>,
    pub transaction_type: String,
    pub amount: i64,
    pub currency: String,
    pub destination_account_id: Option<String>,
    pub frequency: String,
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

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BackupExchangeRate {
    pub id: String,
    pub base_currency: String,
    pub quote_currency: String,
    pub rate: i64,
    pub timestamp: i64,
    pub source: String,
    pub created_at: i64,
    pub updated_at: i64,
    pub deleted_at: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BackupBudget {
    pub id: String,
    pub category_id: String,
    pub currency: String,
    pub amount: i64,
    pub alert_percentage: i32,
    pub created_at: i64,
    pub updated_at: i64,
    pub deleted_at: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BackupSavingGoal {
    pub id: String,
    pub name: String,
    pub target_amount: i64,
    pub currency: String,
    pub target_date: Option<i64>,
    pub color: String,
    pub icon: String,
    pub current_amount: i64,
    pub status: String,
    pub created_at: i64,
    pub updated_at: i64,
    pub deleted_at: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BackupPayload {
    pub app: String,
    pub schema_version: u32,
    pub exported_at: i64,
    pub accounts: Vec<BackupAccount>,
    pub categories: Vec<BackupCategory>,
    pub transactions: Vec<BackupTransaction>,
    pub installments: Vec<BackupInstallment>,
    pub recurring_rules: Vec<BackupRecurringRule>,
    pub exchange_rates: Vec<BackupExchangeRate>,
    pub budgets: Vec<BackupBudget>,
    pub saving_goals: Vec<BackupSavingGoal>,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct BackupRestoreSummary {
    pub accounts: usize,
    pub categories: usize,
    pub transactions: usize,
    pub installments: usize,
    pub recurring_rules: usize,
    pub exchange_rates: usize,
    pub budgets: usize,
    pub saving_goals: usize,
}

pub fn bytes_to_hex(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        use std::fmt::Write;
        let _ = write!(s, "{:02x}", b);
    }
    s
}

pub fn hex_to_16_bytes(s: &str) -> Result<[u8; 16], String> {
    let trimmed = s.trim();
    if let Ok(u) = uuid::Uuid::parse_str(trimmed) {
        return Ok(*u.as_bytes());
    }
    let cleaned: String = trimmed.chars().filter(|c| *c != '-').collect();
    if cleaned.len() != 32 {
        return Err(format!("Hex inválido para 16 bytes: longitud {}", cleaned.len()));
    }
    let mut out = [0u8; 16];
    for i in 0..16 {
        out[i] = u8::from_str_radix(&cleaned[i * 2..i * 2 + 2], 16)
            .map_err(|e| format!("Byte hex inválido en posición {i}: {e}"))?;
    }
    Ok(out)
}

fn escape_csv_field(val: &str) -> String {
    if val.contains(',') || val.contains('"') || val.contains('\n') || val.contains('\r') {
        format!("\"{}\"", val.replace('"', "\"\""))
    } else {
        val.to_string()
    }
}

/// Extrae todos los datos de la base de datos en una estructura unificada `BackupPayload`.
pub fn extract_backup_data(conn: &Connection) -> Result<BackupPayload, String> {
    // 1. Cuentas
    let mut stmt = conn
        .prepare(
            "SELECT id, name, account_type, currency, initial_balance, color, icon,
                    credit_limit, closing_day, due_day, created_at, updated_at, deleted_at
             FROM accounts ORDER BY created_at ASC",
        )
        .map_err(|e| e.to_string())?;
    let accounts = stmt
        .query_map([], |row| {
            let id_bytes: Vec<u8> = row.get(0)?;
            Ok(BackupAccount {
                id: bytes_to_hex(&id_bytes),
                name: row.get(1)?,
                account_type: row.get(2)?,
                currency: row.get(3)?,
                initial_balance: row.get(4)?,
                color: row.get(5)?,
                icon: row.get(6)?,
                credit_limit: row.get(7)?,
                closing_day: row.get(8)?,
                due_day: row.get(9)?,
                created_at: row.get(10)?,
                updated_at: row.get(11)?,
                deleted_at: row.get(12)?,
            })
        })
        .map_err(|e| e.to_string())?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;

    // 2. Categorías
    let mut stmt = conn
        .prepare(
            "SELECT id, name, icon, color, parent_id, is_system, created_at, updated_at, deleted_at
             FROM categories ORDER BY created_at ASC",
        )
        .map_err(|e| e.to_string())?;
    let categories = stmt
        .query_map([], |row| {
            let id_bytes: Vec<u8> = row.get(0)?;
            let parent_id_bytes: Option<Vec<u8>> = row.get(4)?;
            let is_system_int: i32 = row.get(5)?;
            Ok(BackupCategory {
                id: bytes_to_hex(&id_bytes),
                name: row.get(1)?,
                icon: row.get(2)?,
                color: row.get(3)?,
                parent_id: parent_id_bytes.as_ref().map(|b| bytes_to_hex(b)),
                is_system: is_system_int != 0,
                created_at: row.get(6)?,
                updated_at: row.get(7)?,
                deleted_at: row.get(8)?,
            })
        })
        .map_err(|e| e.to_string())?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;

    // 3. Reglas recurrentes
    let mut stmt = conn
        .prepare(
            "SELECT id, account_id, category_id, transaction_type, amount, currency,
                    destination_account_id, frequency, day_of_month, day_of_week,
                    start_date, end_date, auto_apply, last_processed_date,
                    created_at, updated_at, deleted_at
             FROM recurring_rules ORDER BY created_at ASC",
        )
        .map_err(|e| e.to_string())?;
    let recurring_rules = stmt
        .query_map([], |row| {
            let id_bytes: Vec<u8> = row.get(0)?;
            let acc_bytes: Vec<u8> = row.get(1)?;
            let cat_bytes: Option<Vec<u8>> = row.get(2)?;
            let dest_acc_bytes: Option<Vec<u8>> = row.get(6)?;
            let auto_apply_int: i32 = row.get(12)?;
            Ok(BackupRecurringRule {
                id: bytes_to_hex(&id_bytes),
                account_id: bytes_to_hex(&acc_bytes),
                category_id: cat_bytes.as_ref().map(|b| bytes_to_hex(b)),
                transaction_type: row.get(3)?,
                amount: row.get(4)?,
                currency: row.get(5)?,
                destination_account_id: dest_acc_bytes.as_ref().map(|b| bytes_to_hex(b)),
                frequency: row.get(7)?,
                day_of_month: row.get(8)?,
                day_of_week: row.get(9)?,
                start_date: row.get(10)?,
                end_date: row.get(11)?,
                auto_apply: auto_apply_int != 0,
                last_processed_date: row.get(13)?,
                created_at: row.get(14)?,
                updated_at: row.get(15)?,
                deleted_at: row.get(16)?,
            })
        })
        .map_err(|e| e.to_string())?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;

    // 4. Transacciones
    let mut stmt = conn
        .prepare(
            "SELECT id, account_id, category_id, transaction_type, amount, currency,
                    destination_account_id, destination_amount, exchange_rate_snapshot,
                    notes, date, raw_prompt, recurring_rule_id, scheduled_date,
                    created_at, updated_at, deleted_at
             FROM transactions ORDER BY date ASC, created_at ASC",
        )
        .map_err(|e| e.to_string())?;
    let transactions = stmt
        .query_map([], |row| {
            let id_bytes: Vec<u8> = row.get(0)?;
            let acc_bytes: Vec<u8> = row.get(1)?;
            let cat_bytes: Option<Vec<u8>> = row.get(2)?;
            let dest_acc_bytes: Option<Vec<u8>> = row.get(6)?;
            let rec_bytes: Option<Vec<u8>> = row.get(12)?;
            Ok(BackupTransaction {
                id: bytes_to_hex(&id_bytes),
                account_id: bytes_to_hex(&acc_bytes),
                category_id: cat_bytes.as_ref().map(|b| bytes_to_hex(b)),
                transaction_type: row.get(3)?,
                amount: row.get(4)?,
                currency: row.get(5)?,
                destination_account_id: dest_acc_bytes.as_ref().map(|b| bytes_to_hex(b)),
                destination_amount: row.get(7)?,
                exchange_rate_snapshot: row.get(8)?,
                notes: row.get(9)?,
                date: row.get(10)?,
                raw_prompt: row.get(11)?,
                recurring_rule_id: rec_bytes.as_ref().map(|b| bytes_to_hex(b)),
                scheduled_date: row.get(13)?,
                created_at: row.get(14)?,
                updated_at: row.get(15)?,
                deleted_at: row.get(16)?,
            })
        })
        .map_err(|e| e.to_string())?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;

    // 5. Cuotas
    let mut stmt = conn
        .prepare(
            "SELECT id, transaction_id, account_id, installment_number, total_installments,
                    amount, cycle_year, cycle_month, due_date, status,
                    created_at, updated_at, deleted_at
             FROM installments ORDER BY cycle_year ASC, cycle_month ASC, installment_number ASC",
        )
        .map_err(|e| e.to_string())?;
    let installments = stmt
        .query_map([], |row| {
            let id_bytes: Vec<u8> = row.get(0)?;
            let tx_bytes: Vec<u8> = row.get(1)?;
            let acc_bytes: Vec<u8> = row.get(2)?;
            Ok(BackupInstallment {
                id: bytes_to_hex(&id_bytes),
                transaction_id: bytes_to_hex(&tx_bytes),
                account_id: bytes_to_hex(&acc_bytes),
                installment_number: row.get(3)?,
                total_installments: row.get(4)?,
                amount: row.get(5)?,
                cycle_year: row.get(6)?,
                cycle_month: row.get(7)?,
                due_date: row.get(8)?,
                status: row.get(9)?,
                created_at: row.get(10)?,
                updated_at: row.get(11)?,
                deleted_at: row.get(12)?,
            })
        })
        .map_err(|e| e.to_string())?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;

    // 6. Cotizaciones
    let mut stmt = conn
        .prepare(
            "SELECT id, base_currency, quote_currency, rate, timestamp, source,
                    created_at, updated_at, deleted_at
             FROM exchange_rates ORDER BY timestamp ASC",
        )
        .map_err(|e| e.to_string())?;
    let exchange_rates = stmt
        .query_map([], |row| {
            let id_bytes: Vec<u8> = row.get(0)?;
            Ok(BackupExchangeRate {
                id: bytes_to_hex(&id_bytes),
                base_currency: row.get(1)?,
                quote_currency: row.get(2)?,
                rate: row.get(3)?,
                timestamp: row.get(4)?,
                source: row.get(5)?,
                created_at: row.get(6)?,
                updated_at: row.get(7)?,
                deleted_at: row.get(8)?,
            })
        })
        .map_err(|e| e.to_string())?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;

    // 7. Presupuestos
    let mut stmt = conn
        .prepare(
            "SELECT id, category_id, currency, amount, alert_percentage, created_at, updated_at, deleted_at
             FROM budgets ORDER BY created_at ASC",
        )
        .map_err(|e| e.to_string())?;
    let budgets = stmt
        .query_map([], |row| {
            let id_bytes: Vec<u8> = row.get(0)?;
            let cat_bytes: Vec<u8> = row.get(1)?;
            Ok(BackupBudget {
                id: bytes_to_hex(&id_bytes),
                category_id: bytes_to_hex(&cat_bytes),
                currency: row.get(2)?,
                amount: row.get(3)?,
                alert_percentage: row.get(4)?,
                created_at: row.get(5)?,
                updated_at: row.get(6)?,
                deleted_at: row.get(7)?,
            })
        })
        .map_err(|e| e.to_string())?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;

    // 8. Metas de Ahorro
    let mut stmt = conn
        .prepare(
            "SELECT id, name, target_amount, currency, target_date, color, icon,
                    current_amount, status, created_at, updated_at, deleted_at
             FROM saving_goals ORDER BY created_at ASC",
        )
        .map_err(|e| e.to_string())?;
    let saving_goals = stmt
        .query_map([], |row| {
            let id_bytes: Vec<u8> = row.get(0)?;
            Ok(BackupSavingGoal {
                id: bytes_to_hex(&id_bytes),
                name: row.get(1)?,
                target_amount: row.get(2)?,
                currency: row.get(3)?,
                target_date: row.get(4)?,
                color: row.get(5)?,
                icon: row.get(6)?,
                current_amount: row.get(7)?,
                status: row.get(8)?,
                created_at: row.get(9)?,
                updated_at: row.get(10)?,
                deleted_at: row.get(11)?,
            })
        })
        .map_err(|e| e.to_string())?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| e.to_string())?;

    let now_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0);

    Ok(BackupPayload {
        app: "MoneyNeedle".to_string(),
        schema_version: crate::migrations::SCHEMA_VERSION,
        exported_at: now_ms,
        accounts,
        categories,
        transactions,
        installments,
        recurring_rules,
        exchange_rates,
        budgets,
        saving_goals,
    })
}

/// Exporta las transacciones no borradas a formato CSV estándar.
pub fn export_transactions_csv(conn: &Connection) -> Result<String, String> {
    let mut stmt = conn
        .prepare(
            "SELECT 
                hex(t.id),
                t.date,
                t.transaction_type,
                t.amount,
                t.currency,
                COALESCE(a_orig.name, 'Desconocida'),
                COALESCE(a_dest.name, ''),
                COALESCE(c.name, 'Sin categoría'),
                (SELECT COUNT(*) FROM installments WHERE transaction_id = t.id) AS inst_count,
                t.notes,
                t.raw_prompt
             FROM transactions t
             LEFT JOIN accounts a_orig ON t.account_id = a_orig.id
             LEFT JOIN accounts a_dest ON t.destination_account_id = a_dest.id
             LEFT JOIN categories c ON t.category_id = c.id
             WHERE t.deleted_at IS NULL
             ORDER BY t.date DESC, t.created_at DESC",
        )
        .map_err(|e| e.to_string())?;

    let mut csv = String::from("ID,Fecha,Tipo,Monto,Moneda,Cuenta Origen,Cuenta Destino,Categoría,Cuotas,Notas,Texto Dictado\n");

    let rows = stmt
        .query_map([], |row| {
            let id: String = row.get(0)?;
            let date_ms: i64 = row.get(1)?;
            let ttype: String = row.get(2)?;
            let cents: i64 = row.get(3)?;
            let curr: String = row.get(4)?;
            let orig: String = row.get(5)?;
            let dest: String = row.get(6)?;
            let cat: String = row.get(7)?;
            let inst_count: i32 = row.get(8)?;
            let notes: String = row.get(9)?;
            let prompt: String = row.get(10)?;

            let secs = (date_ms / 1000) as u64;
            let dt = crate::store::format_epoch_date(secs);
            let monto_fmt = format!("{:.2}", (cents as f64) / 100.0);
            let tipo_str = match ttype.as_str() {
                "income" => "ingreso",
                "transfer" => "transferencia",
                _ => "gasto",
            };
            let cuotas_str = if inst_count > 0 {
                inst_count.to_string()
            } else {
                "-".to_string()
            };

            Ok((
                id,
                dt,
                tipo_str.to_string(),
                monto_fmt,
                curr,
                orig,
                dest,
                cat,
                cuotas_str,
                notes,
                prompt,
            ))
        })
        .map_err(|e| e.to_string())?;

    for r in rows {
        let (id, dt, tipo, monto, curr, orig, dest, cat, cuotas, notes, prompt) =
            r.map_err(|e| e.to_string())?;

        csv.push_str(&format!(
            "{},{},{},{},{},{},{},{},{},{},{}\n",
            escape_csv_field(&id),
            escape_csv_field(&dt),
            escape_csv_field(&tipo),
            escape_csv_field(&monto),
            escape_csv_field(&curr),
            escape_csv_field(&orig),
            escape_csv_field(&dest),
            escape_csv_field(&cat),
            escape_csv_field(&cuotas),
            escape_csv_field(&notes),
            escape_csv_field(&prompt),
        ));
    }

    Ok(csv)
}

/// Exporta toda la base de datos a JSON plano legible.
pub fn export_all_data_json(conn: &Connection) -> Result<String, String> {
    let data = extract_backup_data(conn)?;
    serde_json::to_string_pretty(&data).map_err(|e| format!("Error serializando JSON: {e}"))
}

fn derive_backup_kek(passphrase: &str, salt: &[u8]) -> Result<Zeroizing<[u8; 32]>, String> {
    if passphrase.trim().is_empty() {
        return Err("La clave o frase de backup no puede estar vacía".into());
    }
    // Parámetros OWASP para derivación en dispositivos móviles (m=19MB, t=2, p=1)
    let params = Params::new(19456, 2, 1, Some(32))
        .map_err(|e| format!("Parámetros Argon2 inválidos: {e}"))?;
    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);

    let mut kek = [0u8; 32];
    argon2
        .hash_password_into(passphrase.trim().as_bytes(), salt, &mut kek)
        .map_err(|e| format!("Error en derivación Argon2id: {e}"))?;

    Ok(Zeroizing::new(kek))
}

/// Crea una copia de seguridad cifrada autocontenida (.mnbackup).
///
/// Encabezado binario:
/// - [0..4]: `MNBK` (Magic bytes)
/// - [4..8]: Versión de formato `1u32` (big-endian)
/// - [8..24]: Salt de Argon2id (16 bytes)
/// - [24..36]: Nonce de AES-256-GCM (12 bytes)
/// - [36..]: Ciphertext cifrado + Tag de autenticación GCM (16 bytes)
pub fn create_encrypted_backup(conn: &Connection, passphrase: &str) -> Result<Vec<u8>, String> {
    let payload = extract_backup_data(conn)?;
    let json_bytes = serde_json::to_vec(&payload)
        .map_err(|e| format!("Error serializando payload de backup: {e}"))?;

    let mut salt = [0u8; 16];
    OsRng.fill_bytes(&mut salt);

    let kek = derive_backup_kek(passphrase, &salt)?;

    let cipher = Aes256Gcm::new_from_slice(&*kek)
        .map_err(|e| format!("Error inicializando AES-GCM: {e}"))?;

    let mut nonce_bytes = [0u8; 12];
    OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let ciphertext = cipher
        .encrypt(nonce, json_bytes.as_ref())
        .map_err(|e| format!("Error cifrando backup: {e}"))?;

    // Empaquetar el archivo binario final
    let mut out = Vec::with_capacity(4 + 4 + 16 + 12 + ciphertext.len());
    out.extend_from_slice(BACKUP_MAGIC);
    out.extend_from_slice(&BACKUP_FORMAT_VERSION.to_be_bytes());
    out.extend_from_slice(&salt);
    out.extend_from_slice(&nonce_bytes);
    out.extend_from_slice(&ciphertext);

    Ok(out)
}

/// Restaura una copia de seguridad cifrada (.mnbackup) en la base de datos viva.
///
/// Realiza la validación criptográfica y autenticación ANTES de iniciar cualquier cambio en la base.
/// La inserción de datos se ejecuta en una transacción atómica exclusiva.
pub fn restore_encrypted_backup(
    conn: &mut Connection,
    backup_bytes: &[u8],
    passphrase: &str,
) -> Result<BackupRestoreSummary, String> {
    // Encabezado mínimo: 4 magic + 4 version + 16 salt + 12 nonce + 16 min tag = 52 bytes
    if backup_bytes.len() < 52 {
        return Err("Archivo de backup corrupto o demasiado pequeño".into());
    }

    if &backup_bytes[0..4] != BACKUP_MAGIC {
        return Err("Formato de backup inválido (magic bytes incorrectos)".into());
    }

    let version = u32::from_be_bytes([
        backup_bytes[4],
        backup_bytes[5],
        backup_bytes[6],
        backup_bytes[7],
    ]);
    if version != BACKUP_FORMAT_VERSION {
        return Err(format!("Versión de formato no soportada: {version}"));
    }

    let salt = &backup_bytes[8..24];
    let nonce_bytes = &backup_bytes[24..36];
    let ciphertext = &backup_bytes[36..];

    let kek = derive_backup_kek(passphrase, salt)?;

    let cipher = Aes256Gcm::new_from_slice(&*kek)
        .map_err(|e| format!("Error inicializando cipher: {e}"))?;
    let nonce = Nonce::from_slice(nonce_bytes);

    // Desencriptación autenticada (falla atómicamente si el passphrase o el tag son incorrectos)
    let decrypted_bytes = cipher
        .decrypt(nonce, ciphertext)
        .map_err(|_| "Clave/frase de recuperación incorrecta o archivo de backup dañado".to_string())?;

    let payload: BackupPayload = serde_json::from_slice(&decrypted_bytes)
        .map_err(|e| format!("Error parseando estructura de datos restaurada: {e}"))?;

    // Transacción SQLite atómica
    let tx = conn.transaction().map_err(|e| e.to_string())?;

    // 1. Categorías
    for c in &payload.categories {
        let id_bytes = hex_to_16_bytes(&c.id)?;
        let parent_id_bytes = match &c.parent_id {
            Some(p) => Some(hex_to_16_bytes(p)?),
            None => None,
        };
        tx.execute(
            "INSERT OR REPLACE INTO categories (id, name, icon, color, parent_id, is_system, created_at, updated_at, deleted_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            params![
                id_bytes,
                c.name,
                c.icon,
                c.color,
                parent_id_bytes,
                if c.is_system { 1 } else { 0 },
                c.created_at,
                c.updated_at,
                c.deleted_at,
            ],
        )
        .map_err(|e| format!("Error restaurando categoría {}: {e}", c.name))?;
    }

    // 2. Cuentas
    for a in &payload.accounts {
        let id_bytes = hex_to_16_bytes(&a.id)?;
        tx.execute(
            "INSERT OR REPLACE INTO accounts (id, name, account_type, currency, initial_balance, color, icon,
                                             credit_limit, closing_day, due_day, created_at, updated_at, deleted_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)",
            params![
                id_bytes,
                a.name,
                a.account_type,
                a.currency,
                a.initial_balance,
                a.color,
                a.icon,
                a.credit_limit,
                a.closing_day,
                a.due_day,
                a.created_at,
                a.updated_at,
                a.deleted_at,
            ],
        )
        .map_err(|e| format!("Error restaurando cuenta {}: {e}", a.name))?;
    }

    // 3. Reglas recurrentes
    for r in &payload.recurring_rules {
        let id_bytes = hex_to_16_bytes(&r.id)?;
        let acc_bytes = hex_to_16_bytes(&r.account_id)?;
        let cat_bytes = match &r.category_id {
            Some(c) => Some(hex_to_16_bytes(c)?),
            None => None,
        };
        let dest_acc_bytes = match &r.destination_account_id {
            Some(d) => Some(hex_to_16_bytes(d)?),
            None => None,
        };
        tx.execute(
            "INSERT OR REPLACE INTO recurring_rules (id, account_id, category_id, transaction_type, amount, currency,
                                                   destination_account_id, frequency, day_of_month, day_of_week,
                                                   start_date, end_date, auto_apply, last_processed_date,
                                                   created_at, updated_at, deleted_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17)",
            params![
                id_bytes,
                acc_bytes,
                cat_bytes,
                r.transaction_type,
                r.amount,
                r.currency,
                dest_acc_bytes,
                r.frequency,
                r.day_of_month,
                r.day_of_week,
                r.start_date,
                r.end_date,
                if r.auto_apply { 1 } else { 0 },
                r.last_processed_date,
                r.created_at,
                r.updated_at,
                r.deleted_at,
            ],
        )
        .map_err(|e| format!("Error restaurando regla recurrente: {e}"))?;
    }

    // 4. Transacciones
    for t in &payload.transactions {
        let id_bytes = hex_to_16_bytes(&t.id)?;
        let acc_bytes = hex_to_16_bytes(&t.account_id)?;
        let cat_bytes = match &t.category_id {
            Some(c) => Some(hex_to_16_bytes(c)?),
            None => None,
        };
        let dest_acc_bytes = match &t.destination_account_id {
            Some(d) => Some(hex_to_16_bytes(d)?),
            None => None,
        };
        let rec_rule_bytes = match &t.recurring_rule_id {
            Some(r) => Some(hex_to_16_bytes(r)?),
            None => None,
        };

        tx.execute(
            "INSERT OR REPLACE INTO transactions (id, account_id, category_id, transaction_type, amount, currency,
                                                 destination_account_id, destination_amount, exchange_rate_snapshot,
                                                 notes, date, raw_prompt, recurring_rule_id, scheduled_date,
                                                 created_at, updated_at, deleted_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17)",
            params![
                id_bytes,
                acc_bytes,
                cat_bytes,
                t.transaction_type,
                t.amount,
                t.currency,
                dest_acc_bytes,
                t.destination_amount,
                t.exchange_rate_snapshot,
                t.notes,
                t.date,
                t.raw_prompt,
                rec_rule_bytes,
                t.scheduled_date,
                t.created_at,
                t.updated_at,
                t.deleted_at,
            ],
        )
        .map_err(|e| format!("Error restaurando transacción {}: {e}", t.id))?;
    }

    // 5. Cuotas
    for inst in &payload.installments {
        let id_bytes = hex_to_16_bytes(&inst.id)?;
        let tx_bytes = hex_to_16_bytes(&inst.transaction_id)?;
        let acc_bytes = hex_to_16_bytes(&inst.account_id)?;

        tx.execute(
            "INSERT OR REPLACE INTO installments (id, transaction_id, account_id, installment_number, total_installments,
                                                 amount, cycle_year, cycle_month, due_date, status,
                                                 created_at, updated_at, deleted_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)",
            params![
                id_bytes,
                tx_bytes,
                acc_bytes,
                inst.installment_number,
                inst.total_installments,
                inst.amount,
                inst.cycle_year,
                inst.cycle_month,
                inst.due_date,
                inst.status,
                inst.created_at,
                inst.updated_at,
                inst.deleted_at,
            ],
        )
        .map_err(|e| format!("Error restaurando cuota: {e}"))?;
    }

    // 6. Cotizaciones
    for ex in &payload.exchange_rates {
        let id_bytes = hex_to_16_bytes(&ex.id)?;
        tx.execute(
            "INSERT OR REPLACE INTO exchange_rates (id, base_currency, quote_currency, rate, timestamp, source,
                                                  created_at, updated_at, deleted_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            params![
                id_bytes,
                ex.base_currency,
                ex.quote_currency,
                ex.rate,
                ex.timestamp,
                ex.source,
                ex.created_at,
                ex.updated_at,
                ex.deleted_at,
            ],
        )
        .map_err(|e| format!("Error restaurando cotización: {e}"))?;
    }

    // 7. Presupuestos
    for b in &payload.budgets {
        let id_bytes = hex_to_16_bytes(&b.id)?;
        let cat_bytes = hex_to_16_bytes(&b.category_id)?;
        tx.execute(
            "INSERT OR REPLACE INTO budgets (id, category_id, currency, amount, alert_percentage, created_at, updated_at, deleted_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                id_bytes,
                cat_bytes,
                b.currency,
                b.amount,
                b.alert_percentage,
                b.created_at,
                b.updated_at,
                b.deleted_at,
            ],
        )
        .map_err(|e| format!("Error restaurando presupuesto: {e}"))?;
    }

    // 8. Metas de ahorro
    for g in &payload.saving_goals {
        let id_bytes = hex_to_16_bytes(&g.id)?;
        tx.execute(
            "INSERT OR REPLACE INTO saving_goals (id, name, target_amount, currency, target_date,
                                                color, icon, current_amount, status, created_at, updated_at, deleted_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)",
            params![
                id_bytes,
                g.name,
                g.target_amount,
                g.currency,
                g.target_date,
                g.color,
                g.icon,
                g.current_amount,
                g.status,
                g.created_at,
                g.updated_at,
                g.deleted_at,
            ],
        )
        .map_err(|e| format!("Error restaurando meta de ahorro: {e}"))?;
    }

    // Verificar integridad referencial
    let mut check_stmt = tx.prepare("PRAGMA foreign_key_check").map_err(|e| e.to_string())?;
    let mut rows = check_stmt.query([]).map_err(|e| e.to_string())?;
    if let Some(row) = rows.next().map_err(|e| e.to_string())? {
        let table: String = row.get(0).map_err(|e| e.to_string())?;
        return Err(format!("Violación de clave foránea en tabla '{table}' al restaurar backup"));
    }
    drop(rows);
    drop(check_stmt);

    tx.commit().map_err(|e| format!("Error al confirmar transacción de restauración: {e}"))?;

    Ok(BackupRestoreSummary {
        accounts: payload.accounts.len(),
        categories: payload.categories.len(),
        transactions: payload.transactions.len(),
        installments: payload.installments.len(),
        recurring_rules: payload.recurring_rules.len(),
        exchange_rates: payload.exchange_rates.len(),
        budgets: payload.budgets.len(),
        saving_goals: payload.saving_goals.len(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn setup_test_db() -> Connection {
        let mut conn = Connection::open_in_memory().unwrap();
        crate::migrations::run_migrations(&mut conn).unwrap();
        crate::store::ensure_default_accounts_and_categories(&conn).unwrap();
        conn
    }

    #[test]
    fn test_export_transactions_csv_format() {
        let conn = setup_test_db();
        let accounts = crate::store::list_accounts(&conn).unwrap();
        let acc_bytes = hex_to_16_bytes(&accounts[0].id).unwrap();

        // Insertar un movimiento de prueba
        crate::store::insert_with_account(
            &conn,
            Some(&acc_bytes),
            &crate::TipoMovimiento::Gasto,
            1250.0,
            "ARS",
            "supermercado",
            "compra semanal con descuento, frutas",
            "2026-10-01",
            "gasté 1250 en súper",
        )
        .unwrap();

        let csv = export_transactions_csv(&conn).unwrap();
        assert!(csv.contains("ID,Fecha,Tipo,Monto,Moneda,Cuenta Origen,Cuenta Destino,Categoría,Cuotas,Notas,Texto Dictado"));
        assert!(csv.contains("1250.00"));
        assert!(csv.contains("supermercado"));
        assert!(csv.contains("\"compra semanal con descuento, frutas\""));
        assert!(csv.contains("gasté 1250 en súper"));
    }

    #[test]
    fn test_export_all_data_json_structure() {
        let conn = setup_test_db();
        let json_str = export_all_data_json(&conn).unwrap();
        let v: serde_json::Value = serde_json::from_str(&json_str).unwrap();

        assert_eq!(v["app"], "MoneyNeedle");
        assert_eq!(v["schema_version"], 2);
        assert!(v["accounts"].is_array());
        assert!(v["categories"].is_array());
    }

    #[test]
    fn test_create_and_restore_encrypted_backup_flow() {
        let conn_orig = setup_test_db();
        let accounts = crate::store::list_accounts(&conn_orig).unwrap();
        let acc_bytes = hex_to_16_bytes(&accounts[0].id).unwrap();
        let now = crate::store::now_ms();

        // 1. Insertar movimiento
        let _tx_id = crate::store::insert_with_account(
            &conn_orig,
            Some(&acc_bytes),
            &crate::TipoMovimiento::Gasto,
            5000.0,
            "ARS",
            "comida",
            "cena restaurante",
            "2026-10-01",
            "gasté 5000 en cena",
        )
        .unwrap();

        // 2. Insertar presupuesto
        let cat_id = crate::store::get_or_create_category(&conn_orig, "comida").unwrap();
        crate::store::set_category_budget(&conn_orig, &cat_id, "ARS", 1500000, 75).unwrap();

        // 3. Insertar meta de ahorro
        crate::store::create_saving_goal(
            &conn_orig,
            "Vacaciones 2027",
            20000000,
            "ARS",
            Some(now + 86_400_000 * 180),
            "#2196F3",
            "flight",
        )
        .unwrap();

        // 4. Crear backup cifrado
        let passphrase = "correct horse battery staple";
        let backup_bytes = create_encrypted_backup(&conn_orig, passphrase).unwrap();
        assert!(backup_bytes.len() > 100);
        assert_eq!(&backup_bytes[0..4], BACKUP_MAGIC);

        // 5. Restaurar en una base limpia
        let mut conn_clean = Connection::open_in_memory().unwrap();
        crate::migrations::run_migrations(&mut conn_clean).unwrap();

        let summary = restore_encrypted_backup(&mut conn_clean, &backup_bytes, passphrase).unwrap();
        assert!(summary.accounts >= 1);
        assert!(summary.transactions >= 1);
        assert_eq!(summary.budgets, 1);
        assert_eq!(summary.saving_goals, 1);

        // Validar que la transacción restaurada exista y mantenga sus datos
        let movements = crate::store::list(&conn_clean, 10).unwrap();
        assert_eq!(movements.len(), 1);
        assert_eq!(movements[0].monto, 5000.0);
        assert_eq!(movements[0].moneda, "ARS");
        assert_eq!(movements[0].descripcion, "cena restaurante");

        // Validar presupuestos
        let budgets = crate::store::list_budgets_status(
            &conn_clean,
            now - 86_400_000,
            now + 86_400_000,
            "ARS",
        )
        .unwrap();
        assert_eq!(budgets.len(), 1);
        assert_eq!(budgets[0].budget_amount_cents, 1500000);

        // Validar metas
        let goals = crate::store::list_saving_goals(&conn_clean).unwrap();
        assert_eq!(goals.len(), 1);
        assert_eq!(goals[0].name, "Vacaciones 2027");
        assert_eq!(goals[0].target_amount_cents, 20000000);
    }

    #[test]
    fn test_restore_encrypted_backup_wrong_passphrase_fails() {
        let conn = setup_test_db();
        let passphrase = "my-secret-passphrase";
        let backup_bytes = create_encrypted_backup(&conn, passphrase).unwrap();

        let mut conn_target = setup_test_db();
        let err = restore_encrypted_backup(&mut conn_target, &backup_bytes, "wrong-passphrase");
        assert!(err.is_err());
        assert!(err.unwrap_err().contains("Clave/frase de recuperación incorrecta"));
    }

    #[test]
    fn test_restore_encrypted_backup_corrupted_payload_fails() {
        let conn = setup_test_db();
        let passphrase = "password";
        let mut backup_bytes = create_encrypted_backup(&conn, passphrase).unwrap();

        // Corromper el ciphertext
        let len = backup_bytes.len();
        backup_bytes[len - 5] ^= 0xFF;

        let mut conn_target = setup_test_db();
        let err = restore_encrypted_backup(&mut conn_target, &backup_bytes, passphrase);
        assert!(err.is_err());
    }
}
