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
    account_id: Option<String>,
) -> anyhow::Result<String> {
    let t = match tipo.as_str() {
        "gasto" => TipoMovimiento::Gasto,
        "ingreso" => TipoMovimiento::Ingreso,
        other => anyhow::bail!("tipo inválido: {other}"),
    };
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let acc_bytes = match account_id {
        Some(s) if !s.trim().is_empty() => {
            let u = uuid::Uuid::parse_str(&s).map_err(|e| anyhow::anyhow!("{e}"))?;
            Some(*u.as_bytes())
        }
        _ => None,
    };
    store::insert_with_account(
        &conn,
        acc_bytes.as_ref(),
        &t,
        monto,
        &moneda,
        &categoria,
        &descripcion,
        &fecha,
        &frase,
    )
    .map_err(|e| anyhow::anyhow!("{e}"))
}

/// Inserta una compra con tarjeta de crédito en N cuotas.
#[allow(clippy::too_many_arguments)]
pub fn confirm_credit_purchase(
    db_path: String,
    card_account_id: String,
    monto: f64,
    cuotas: i32,
    categoria: String,
    descripcion: String,
    start_cycle_year: i32,
    start_cycle_month: i32,
) -> anyhow::Result<String> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let card_uuid = uuid::Uuid::parse_str(&card_account_id).map_err(|e| anyhow::anyhow!("{e}"))?;
    let cat_id = store::get_or_create_category(&conn, &categoria).map_err(|e| anyhow::anyhow!("{e}"))?;
    let monto_centavos = (monto * 100.0).round() as i64;
    let now = store::now_ms();
    let tx_bytes = store::insert_credit_purchase(
        &conn,
        card_uuid.as_bytes(),
        Some(&cat_id),
        monto_centavos,
        cuotas,
        now,
        start_cycle_year,
        start_cycle_month,
        &descripcion,
        &descripcion,
    )
    .map_err(|e| anyhow::anyhow!("{e}"))?;
    Ok(uuid::Uuid::from_bytes(tx_bytes).to_string())
}

/// DTO para cuentas y saldos en UI.
#[derive(Debug, Clone)]
pub struct AccountDto {
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

impl From<store::AccountWithBalance> for AccountDto {
    fn from(a: store::AccountWithBalance) -> Self {
        AccountDto {
            id: a.id,
            name: a.name,
            account_type: a.account_type,
            currency: a.currency,
            initial_balance: a.initial_balance,
            current_balance: a.current_balance,
            color: a.color,
            icon: a.icon,
            credit_limit: a.credit_limit,
            closing_day: a.closing_day,
            due_day: a.due_day,
        }
    }
}

/// Lista todas las cuentas activas con su saldo calculado.
pub fn list_accounts(db_path: String) -> anyhow::Result<Vec<AccountDto>> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    Ok(store::list_accounts(&conn)
        .map_err(|e| anyhow::anyhow!("{e}"))?
        .into_iter()
        .map(AccountDto::from)
        .collect())
}

/// Crea una nueva cuenta financiera.
#[allow(clippy::too_many_arguments)]
pub fn create_account(
    db_path: String,
    name: String,
    account_type: String,
    currency: String,
    initial_balance: f64,
    credit_limit: Option<f64>,
    closing_day: Option<i32>,
    due_day: Option<i32>,
    color: String,
    icon: String,
) -> anyhow::Result<String> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let atype = match account_type.to_lowercase().as_str() {
        "bank" | "banco" => store::AccountType::Bank,
        "wallet" | "billetera" => store::AccountType::Wallet,
        "credit_card" | "credit" | "tarjeta" => store::AccountType::CreditCard,
        "investment" | "inversion" => store::AccountType::Investment,
        _ => store::AccountType::Cash,
    };
    let init_cents = (initial_balance * 100.0).round() as i64;
    let limit_cents = credit_limit.map(|l| (l * 100.0).round() as i64);

    store::create_account(
        &conn,
        &name,
        &atype,
        &currency,
        init_cents,
        limit_cents,
        closing_day,
        due_day,
        &color,
        &icon,
    )
    .map_err(|e| anyhow::anyhow!("{e}"))
}

/// Elimina (soft-delete) una cuenta.
pub fn delete_account(db_path: String, account_id: String) -> anyhow::Result<bool> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let u = uuid::Uuid::parse_str(&account_id).map_err(|e| anyhow::anyhow!("{e}"))?;
    store::delete_account(&conn, u.as_bytes()).map_err(|e| anyhow::anyhow!("{e}"))
}

/// Cuota de resumen de tarjeta.
#[derive(Debug, Clone)]
pub struct CardStatementItemDto {
    pub installment_id: String,
    pub transaction_id: String,
    pub installment_number: i32,
    pub total_installments: i32,
    pub amount: f64,
    pub description: String,
    pub status: String,
}

/// Resumen de tarjeta para un ciclo mensual.
#[derive(Debug, Clone)]
pub struct CardStatementDto {
    pub card_id: String,
    pub cycle_year: i32,
    pub cycle_month: i32,
    pub total_due: f64,
    pub items: Vec<CardStatementItemDto>,
}

/// Obtiene el resumen de tarjeta para un ciclo determinado.
pub fn get_card_statement(
    db_path: String,
    card_id: String,
    cycle_year: i32,
    cycle_month: i32,
) -> anyhow::Result<CardStatementDto> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let uuid = uuid::Uuid::parse_str(&card_id).map_err(|e| anyhow::anyhow!("{e}"))?;
    let stmt = store::get_card_statement(&conn, uuid.as_bytes(), cycle_year, cycle_month)
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    Ok(CardStatementDto {
        card_id: stmt.card_id,
        cycle_year: stmt.cycle_year,
        cycle_month: stmt.cycle_month,
        total_due: stmt.total_due,
        items: stmt
            .items
            .into_iter()
            .map(|i| CardStatementItemDto {
                installment_id: i.installment_id,
                transaction_id: i.transaction_id,
                installment_number: i.installment_number,
                total_installments: i.total_installments,
                amount: i.amount,
                description: i.description,
                status: i.status,
            })
            .collect(),
    })
}

/// Vista DTO de una suscripción o regla recurrente.
#[derive(Debug, Clone)]
pub struct RecurringRuleDto {
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

/// Lista todas las reglas recurrentes activas.
pub fn list_recurring_rules(db_path: String) -> anyhow::Result<Vec<RecurringRuleDto>> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let rules = store::list_recurring_rules(&conn).map_err(|e| anyhow::anyhow!("{e}"))?;
    Ok(rules
        .into_iter()
        .map(|r| RecurringRuleDto {
            id: r.id,
            account_id: r.account_id,
            account_name: r.account_name,
            transaction_type: r.transaction_type,
            amount: r.amount,
            currency: r.currency,
            frequency: r.frequency,
            start_date: r.start_date,
            auto_apply: r.auto_apply,
        })
        .collect())
}

/// Crea una nueva suscripción o regla recurrente.
pub fn create_recurring_rule(
    db_path: String,
    account_id: String,
    transaction_type: String,
    amount: f64,
    currency: String,
    frequency: String,
    auto_apply: bool,
) -> anyhow::Result<String> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let acc_uuid = uuid::Uuid::parse_str(&account_id).map_err(|e| anyhow::anyhow!("{e}"))?;
    let ttype = match transaction_type.as_str() {
        "income" | "ingreso" => store::TransactionType::Income,
        _ => store::TransactionType::Expense,
    };
    let freq = match frequency.to_lowercase().as_str() {
        "daily" | "diario" => store::Frequency::Daily,
        "weekly" | "semanal" => store::Frequency::Weekly,
        "yearly" | "anual" => store::Frequency::Yearly,
        _ => store::Frequency::Monthly,
    };
    let cents = (amount * 100.0).round() as i64;
    store::create_recurring_rule(
        &conn,
        acc_uuid.as_bytes(),
        &ttype,
        cents,
        &currency,
        &freq,
        auto_apply,
    )
    .map_err(|e| anyhow::anyhow!("{e}"))
}

/// Elimina una regla recurrente.
pub fn delete_recurring_rule(db_path: String, rule_id: String) -> anyhow::Result<bool> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let u = uuid::Uuid::parse_str(&rule_id).map_err(|e| anyhow::anyhow!("{e}"))?;
    store::delete_recurring_rule(&conn, u.as_bytes()).map_err(|e| anyhow::anyhow!("{e}"))
}

/// Procesa las reglas recurrentes vencidas hasta hoy.
pub fn process_recurring_rules(db_path: String) -> anyhow::Result<i32> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let now = store::now_ms();
    let count = store::process_recurring_rules(&conn, now, 86_400_000 * 30)
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    Ok(count as i32)
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

    #[test]
    fn api_cuentas_tarjetas_recurrentes_flow() {
        let db_path = format!("/tmp/test_api_{}.db", store::now_ms());
        let _ = std::fs::remove_file(&db_path);

        init_database(db_path.clone(), None).unwrap();

        // 1. Cuentas
        let accs_init = list_accounts(db_path.clone()).unwrap();
        assert_eq!(accs_init.len(), 1); // Cuenta por defecto "Efectivo"

        let card_id = create_account(
            db_path.clone(),
            "Visa Santander".into(),
            "credit_card".into(),
            "ARS".into(),
            0.0,
            Some(500_000.0),
            Some(20),
            Some(5),
            "#1976D2".into(),
            "credit_card".into(),
        )
        .unwrap();

        let accs_after = list_accounts(db_path.clone()).unwrap();
        assert_eq!(accs_after.len(), 2);

        // 2. Compra en cuotas con tarjeta
        let tx_id = confirm_credit_purchase(
            db_path.clone(),
            card_id.clone(),
            60_000.0,
            3,
            "electro".into(),
            "Microondas".into(),
            2026,
            10,
        )
        .unwrap();
        assert!(!tx_id.is_empty());

        let statement = get_card_statement(db_path.clone(), card_id.clone(), 2026, 10).unwrap();
        assert_eq!(statement.items.len(), 1);
        assert_eq!(statement.total_due, 20_000.0);

        // 3. Reglas recurrentes
        let rule_id = create_recurring_rule(
            db_path.clone(),
            card_id.clone(),
            "gasto".into(),
            5_000.0,
            "ARS".into(),
            "monthly".into(),
            true,
        )
        .unwrap();

        let rules = list_recurring_rules(db_path.clone()).unwrap();
        assert_eq!(rules.len(), 1);
        assert_eq!(rules[0].id, rule_id);

        let processed = process_recurring_rules(db_path.clone()).unwrap();
        assert!(processed >= 1);

        assert!(delete_recurring_rule(db_path.clone(), rule_id).unwrap());
        assert_eq!(list_recurring_rules(db_path.clone()).unwrap().len(), 0);

        // 4. Confirm movement con cuenta
        let mov_id = confirm_movement(
            db_path.clone(),
            "gasto".into(),
            1200.0,
            "ARS".into(),
            "comida".into(),
            "Almuerzo".into(),
            "2026-10-01".into(),
            "almorcé 1200".into(),
            Some(accs_init[0].id.clone()),
        )
        .unwrap();
        assert!(!mov_id.is_empty());

        // 5. Delete account
        assert!(delete_account(db_path.clone(), card_id).unwrap());
        let accs_final = list_accounts(db_path.clone()).unwrap();
        assert_eq!(accs_final.len(), 1);

        let _ = std::fs::remove_file(&db_path);
    }
}
