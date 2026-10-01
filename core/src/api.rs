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
    pub account_id: Option<String>,
    pub account_name: Option<String>,
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
            account_id: m.account_id,
            account_name: m.account_name,
        }
    }
}

/// Inicializa la base de datos con clave SQLCipher opcional (hex crudo) y la guarda para la sesión activa.
pub fn init_database(db_path: String, raw_key_hex: Option<String>) -> anyhow::Result<bool> {
    let zero_key = raw_key_hex.map(zeroize::Zeroizing::new);
    let _conn = store::open(&db_path, zero_key.as_ref())
        .map_err(|e| anyhow::anyhow!("init_database: {e}"))?;
    store::set_active_key_for_path(&db_path, zero_key);
    Ok(true)
}

/// Cierra y borra de memoria la clave activa de la sesión de base de datos para la ruta indicada.
pub fn lock_database(db_path: String) -> anyhow::Result<bool> {
    store::set_active_key_for_path(&db_path, None);
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

/// DTO con cotización histórica o implícita entre monedas.
#[derive(Debug, Clone)]
pub struct ExchangeRateDto {
    pub base_currency: String,
    pub quote_currency: String,
    pub rate: f64,
    pub timestamp: i64,
}

impl From<store::ExchangeRateRecord> for ExchangeRateDto {
    fn from(r: store::ExchangeRateRecord) -> Self {
        ExchangeRateDto {
            base_currency: r.base_currency,
            quote_currency: r.quote_currency,
            rate: r.rate,
            timestamp: r.timestamp,
        }
    }
}

/// Registra una transferencia entre cuentas (misma moneda o con cambio de divisa).
pub fn create_transfer(
    db_path: String,
    from_account_id: String,
    to_account_id: String,
    from_amount: f64,
    to_amount: f64,
    notes: String,
) -> anyhow::Result<String> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let from_uuid = uuid::Uuid::parse_str(&from_account_id).map_err(|e| anyhow::anyhow!("{e}"))?;
    let to_uuid = uuid::Uuid::parse_str(&to_account_id).map_err(|e| anyhow::anyhow!("{e}"))?;
    let from_cents = (from_amount * 100.0).round() as i64;
    let to_cents = (to_amount * 100.0).round() as i64;
    let now = store::now_ms();

    let tx_bytes = store::insert_transfer(
        &conn,
        from_uuid.as_bytes(),
        to_uuid.as_bytes(),
        from_cents,
        to_cents,
        now,
        &notes,
    )
    .map_err(|e| anyhow::anyhow!("{e}"))?;

    Ok(uuid::Uuid::from_bytes(tx_bytes).to_string())
}

/// Consulta la última cotización registrada entre dos monedas.
pub fn get_latest_exchange_rate(
    db_path: String,
    base_currency: String,
    quote_currency: String,
) -> anyhow::Result<Option<ExchangeRateDto>> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let rate = store::get_latest_exchange_rate(&conn, &base_currency, &quote_currency)
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    Ok(rate.map(ExchangeRateDto::from))
}

/// Lista el historial de cotizaciones registradas.
pub fn list_exchange_rates(db_path: String) -> anyhow::Result<Vec<ExchangeRateDto>> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let rates = store::list_exchange_rates(&conn).map_err(|e| anyhow::anyhow!("{e}"))?;
    Ok(rates.into_iter().map(ExchangeRateDto::from).collect())
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

/// Actualiza una cuenta existente.
pub fn update_account(
    db_path: String,
    account_id: String,
    name: String,
    color: String,
    credit_limit: Option<f64>,
    closing_day: Option<i32>,
    due_day: Option<i32>,
) -> anyhow::Result<bool> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let u = uuid::Uuid::parse_str(&account_id).map_err(|e| anyhow::anyhow!("{e}"))?;
    let limit_cents = credit_limit.map(|c| (c * 100.0).round() as i64);
    store::update_account(&conn, u.as_bytes(), &name, &color, limit_cents, closing_day, due_day)
        .map_err(|e| anyhow::anyhow!("{e}"))
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

/// Actualiza una regla recurrente existente.
pub fn update_recurring_rule(
    db_path: String,
    rule_id: String,
    amount: f64,
    frequency: String,
    auto_apply: bool,
) -> anyhow::Result<bool> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let u = uuid::Uuid::parse_str(&rule_id).map_err(|e| anyhow::anyhow!("{e}"))?;
    let amount_cents = (amount * 100.0).round() as i64;
    store::update_recurring_rule(&conn, u.as_bytes(), amount_cents, &frequency, auto_apply)
        .map_err(|e| anyhow::anyhow!("{e}"))
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

/// Elimina un movimiento de forma suave (soft-delete).
pub fn delete_movement(db_path: String, movement_id: String) -> anyhow::Result<bool> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let u = uuid::Uuid::parse_str(&movement_id).map_err(|e| anyhow::anyhow!("{e}"))?;
    store::soft_delete_transaction(&conn, u.as_bytes()).map_err(|e| anyhow::anyhow!("{e}"))
}

/// Restaura un movimiento eliminado previamente (Deshacer borrado).
pub fn restore_movement(db_path: String, movement_id: String) -> anyhow::Result<bool> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let u = uuid::Uuid::parse_str(&movement_id).map_err(|e| anyhow::anyhow!("{e}"))?;
    store::restore_transaction(&conn, u.as_bytes()).map_err(|e| anyhow::anyhow!("{e}"))
}

/// Actualiza los datos de un movimiento confirmado.
#[allow(clippy::too_many_arguments)]
pub fn update_movement(
    db_path: String,
    movement_id: String,
    tipo: String,
    monto: f64,
    moneda: String,
    categoria: String,
    descripcion: String,
    fecha: String,
    account_id: Option<String>,
) -> anyhow::Result<bool> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let u = uuid::Uuid::parse_str(&movement_id).map_err(|e| anyhow::anyhow!("{e}"))?;
    let monto_cents = (monto * 100.0).round() as i64;
    let fecha_ms = store::parse_date_str_to_ms(&fecha).unwrap_or_else(store::now_ms);

    let acc_bytes = match account_id {
        Some(s) if !s.trim().is_empty() => {
            let acc_u = uuid::Uuid::parse_str(&s).map_err(|e| anyhow::anyhow!("{e}"))?;
            Some(*acc_u.as_bytes())
        }
        _ => None,
    };

    store::update_transaction(
        &conn,
        u.as_bytes(),
        &tipo,
        monto_cents,
        &moneda,
        &categoria,
        &descripcion,
        fecha_ms,
        acc_bytes.as_ref(),
    )
    .map_err(|e| anyhow::anyhow!("{e}"))
}

/// Busca y filtra movimientos de forma multicriterio con paginación.
#[allow(clippy::too_many_arguments)]
pub fn search_movements(
    db_path: String,
    query: Option<String>,
    start_date_ms: Option<i64>,
    end_date_ms: Option<i64>,
    category_id: Option<String>,
    account_id: Option<String>,
    tipo: Option<String>,
    limit: i64,
    offset: i64,
) -> anyhow::Result<Vec<MovementDto>> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;

    let cat_bytes = match category_id {
        Some(s) if !s.trim().is_empty() => {
            let u = uuid::Uuid::parse_str(&s).map_err(|e| anyhow::anyhow!("{e}"))?;
            Some(*u.as_bytes())
        }
        _ => None,
    };

    let acc_bytes = match account_id {
        Some(s) if !s.trim().is_empty() => {
            let u = uuid::Uuid::parse_str(&s).map_err(|e| anyhow::anyhow!("{e}"))?;
            Some(*u.as_bytes())
        }
        _ => None,
    };

    Ok(store::search_transactions(
        &conn,
        query.as_deref(),
        start_date_ms,
        end_date_ms,
        cat_bytes.as_ref(),
        acc_bytes.as_ref(),
        tipo.as_deref(),
        limit,
        offset,
    )
    .map_err(|e| anyhow::anyhow!("{e}"))?
    .into_iter()
    .map(MovementDto::from)
    .collect())
}

// ============================================================================
// Métricas, Analítica y Reportes (Fase 4)
// ============================================================================

#[derive(Debug, Clone)]
pub struct CategorySpendingDto {
    pub category_id: Option<String>,
    pub name: String,
    pub color: String,
    pub icon: String,
    pub total_amount: f64,
    pub percentage: f64,
    pub transaction_count: i32,
}

#[derive(Debug, Clone)]
pub struct CategoryReportDto {
    pub currency: String,
    pub total_amount: f64,
    pub items: Vec<CategorySpendingDto>,
}

#[derive(Debug, Clone)]
pub struct CashflowItemDto {
    pub year: i32,
    pub month: i32,
    pub income_amount: f64,
    pub expense_amount: f64,
    pub net_amount: f64,
    pub currency: String,
}

#[derive(Debug, Clone)]
pub struct InstallmentProjectionDto {
    pub cycle_year: i32,
    pub cycle_month: i32,
    pub total_amount: f64,
    pub count: i32,
    pub currency: String,
}

#[derive(Debug, Clone)]
pub struct FinancialKpisDto {
    pub total_income: f64,
    pub total_expense: f64,
    pub net_savings: f64,
    pub savings_rate: f64,
    pub top_category_name: Option<String>,
    pub top_category_amount: Option<f64>,
}

/// Reporte de gastos por categoría en un rango de fechas.
pub fn get_category_spending_report(
    db_path: String,
    start_date_ms: i64,
    end_date_ms: i64,
    currency: String,
) -> anyhow::Result<CategoryReportDto> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let report = store::get_category_spending_report(&conn, start_date_ms, end_date_ms, &currency)
        .map_err(|e| anyhow::anyhow!("{e}"))?;

    Ok(CategoryReportDto {
        currency: report.currency,
        total_amount: report.total_cents as f64 / 100.0,
        items: report
            .items
            .into_iter()
            .map(|i| CategorySpendingDto {
                category_id: i.category_id,
                name: i.name,
                color: i.color,
                icon: i.icon,
                total_amount: i.total_cents as f64 / 100.0,
                percentage: i.percentage,
                transaction_count: i.transaction_count,
            })
            .collect(),
    })
}

/// Historial de flujo de caja mensual (ingresos vs gastos).
pub fn get_monthly_cashflow_history(
    db_path: String,
    currency: String,
    months_limit: i32,
) -> anyhow::Result<Vec<CashflowItemDto>> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let items = store::get_monthly_cashflow(&conn, &currency, months_limit)
        .map_err(|e| anyhow::anyhow!("{e}"))?;

    Ok(items
        .into_iter()
        .map(|i| CashflowItemDto {
            year: i.year,
            month: i.month,
            income_amount: i.income_cents as f64 / 100.0,
            expense_amount: i.expense_cents as f64 / 100.0,
            net_amount: i.net_cents as f64 / 100.0,
            currency: i.currency,
        })
        .collect())
}

/// Proyección de compromisos futuros de cuotas en tarjetas de crédito.
pub fn get_installment_commitments(
    db_path: String,
    currency: String,
) -> anyhow::Result<Vec<InstallmentProjectionDto>> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let items = store::get_installment_projections(&conn, &currency)
        .map_err(|e| anyhow::anyhow!("{e}"))?;

    Ok(items
        .into_iter()
        .map(|i| InstallmentProjectionDto {
            cycle_year: i.cycle_year,
            cycle_month: i.cycle_month,
            total_amount: i.total_cents as f64 / 100.0,
            count: i.count,
            currency: i.currency,
        })
        .collect())
}

/// Indicadores financieros clave (KPIs) para un período dado.
pub fn get_financial_kpis(
    db_path: String,
    start_date_ms: i64,
    end_date_ms: i64,
    currency: String,
) -> anyhow::Result<FinancialKpisDto> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let k = store::get_financial_kpis(&conn, start_date_ms, end_date_ms, &currency)
        .map_err(|e| anyhow::anyhow!("{e}"))?;

    Ok(FinancialKpisDto {
        total_income: k.total_income_cents as f64 / 100.0,
        total_expense: k.total_expense_cents as f64 / 100.0,
        net_savings: k.net_savings_cents as f64 / 100.0,
        savings_rate: k.savings_rate,
        top_category_name: k.top_category_name,
        top_category_amount: k.top_category_cents.map(|c| c as f64 / 100.0),
    })
}

// ============================================================================
// Presupuestos y Metas de Ahorro (Fase 5)
// ============================================================================

#[derive(Debug, Clone)]
pub struct BudgetStatusDto {
    pub id: String,
    pub category_id: String,
    pub category_name: String,
    pub category_color: String,
    pub category_icon: String,
    pub currency: String,
    pub budget_amount: f64,
    pub spent_amount: f64,
    pub remaining_amount: f64,
    pub spent_percentage: f64,
    pub is_over_budget: bool,
    pub is_warning: bool,
}

#[derive(Debug, Clone)]
pub struct SavingGoalDto {
    pub id: String,
    pub name: String,
    pub target_amount: f64,
    pub current_amount: f64,
    pub progress_percentage: f64,
    pub currency: String,
    pub target_date: Option<i64>,
    pub color: String,
    pub icon: String,
    pub status: String,
}

/// Define o actualiza el límite mensual de una categoría.
pub fn set_category_budget(
    db_path: String,
    category_id: String,
    currency: String,
    amount: f64,
    alert_percentage: i32,
) -> anyhow::Result<String> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let u = uuid::Uuid::parse_str(&category_id).map_err(|e| anyhow::anyhow!("{e}"))?;
    let cents = (amount * 100.0).round() as i64;
    store::set_category_budget(&conn, u.as_bytes(), &currency, cents, alert_percentage)
        .map_err(|e| anyhow::anyhow!("{e}"))
}

/// Consulta el estado de todos los presupuestos activos contra los consumos del período.
pub fn list_budgets_status(
    db_path: String,
    start_date_ms: i64,
    end_date_ms: i64,
    currency: String,
) -> anyhow::Result<Vec<BudgetStatusDto>> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let list = store::list_budgets_status(&conn, start_date_ms, end_date_ms, &currency)
        .map_err(|e| anyhow::anyhow!("{e}"))?;

    Ok(list
        .into_iter()
        .map(|b| BudgetStatusDto {
            id: b.id,
            category_id: b.category_id,
            category_name: b.category_name,
            category_color: b.category_color,
            category_icon: b.category_icon,
            currency: b.currency,
            budget_amount: b.budget_amount_cents as f64 / 100.0,
            spent_amount: b.spent_amount_cents as f64 / 100.0,
            remaining_amount: b.remaining_amount_cents as f64 / 100.0,
            spent_percentage: b.spent_percentage,
            is_over_budget: b.is_over_budget,
            is_warning: b.is_warning,
        })
        .collect())
}

/// Elimina un presupuesto.
pub fn delete_budget(db_path: String, budget_id: String) -> anyhow::Result<bool> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let u = uuid::Uuid::parse_str(&budget_id).map_err(|e| anyhow::anyhow!("{e}"))?;
    store::delete_budget(&conn, u.as_bytes()).map_err(|e| anyhow::anyhow!("{e}"))
}

/// Crea una nueva meta de ahorro.
pub fn create_saving_goal(
    db_path: String,
    name: String,
    target_amount: f64,
    currency: String,
    target_date: Option<i64>,
    color: String,
    icon: String,
) -> anyhow::Result<String> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let cents = (target_amount * 100.0).round() as i64;
    store::create_saving_goal(&conn, &name, cents, &currency, target_date, &color, &icon)
        .map_err(|e| anyhow::anyhow!("{e}"))
}

/// Lista todas las metas de ahorro.
pub fn list_saving_goals(db_path: String) -> anyhow::Result<Vec<SavingGoalDto>> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let list = store::list_saving_goals(&conn).map_err(|e| anyhow::anyhow!("{e}"))?;

    Ok(list
        .into_iter()
        .map(|g| {
            let target = g.target_amount_cents as f64 / 100.0;
            let current = g.current_amount_cents as f64 / 100.0;
            let pct = if target > 0.0 {
                ((current / target) * 10000.0).round() / 100.0
            } else {
                0.0
            };
            SavingGoalDto {
                id: g.id,
                name: g.name,
                target_amount: target,
                current_amount: current,
                progress_percentage: pct,
                currency: g.currency,
                target_date: g.target_date,
                color: g.color,
                icon: g.icon,
                status: g.status,
            }
        })
        .collect())
}

/// Aporta una cantidad (o deduce) a una meta de ahorro.
pub fn contribute_to_saving_goal(
    db_path: String,
    goal_id: String,
    amount: f64,
) -> anyhow::Result<f64> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let u = uuid::Uuid::parse_str(&goal_id).map_err(|e| anyhow::anyhow!("{e}"))?;
    let cents = (amount * 100.0).round() as i64;
    let new_cents = store::contribute_to_saving_goal(&conn, u.as_bytes(), cents)
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    Ok(new_cents as f64 / 100.0)
}

/// Elimina una meta de ahorro.
pub fn delete_saving_goal(db_path: String, goal_id: String) -> anyhow::Result<bool> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let u = uuid::Uuid::parse_str(&goal_id).map_err(|e| anyhow::anyhow!("{e}"))?;
    store::delete_saving_goal(&conn, u.as_bytes()).map_err(|e| anyhow::anyhow!("{e}"))
}

#[derive(Debug, Clone)]
pub struct CategoryDto {
    pub id: String,
    pub name: String,
    pub icon: String,
    pub color: String,
    pub is_system: bool,
}

/// Lista todas las categorías activas.
pub fn list_categories(db_path: String) -> anyhow::Result<Vec<CategoryDto>> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let list = store::list_categories(&conn).map_err(|e| anyhow::anyhow!("{e}"))?;
    Ok(list
        .into_iter()
        .map(|c| CategoryDto {
            id: c.id,
            name: c.name,
            icon: c.icon,
            color: c.color,
            is_system: c.is_system,
        })
        .collect())
}

/// Crea una nueva categoría personalizada.
pub fn create_category(
    db_path: String,
    name: String,
    icon: String,
    color: String,
    parent_id: Option<String>,
) -> anyhow::Result<String> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let parent_bytes = match parent_id {
        Some(s) if !s.trim().is_empty() => {
            let u = uuid::Uuid::parse_str(&s).map_err(|e| anyhow::anyhow!("{e}"))?;
            Some(*u.as_bytes())
        }
        _ => None,
    };
    let id_bytes = store::create_category(&conn, &name, &icon, &color, parent_bytes.as_ref())
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    Ok(uuid::Uuid::from_bytes(id_bytes).to_string())
}

/// Actualiza una categoría existente.
pub fn update_category(
    db_path: String,
    category_id: String,
    name: String,
    icon: String,
    color: String,
) -> anyhow::Result<bool> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let u = uuid::Uuid::parse_str(&category_id).map_err(|e| anyhow::anyhow!("{e}"))?;
    store::update_category(&conn, u.as_bytes(), &name, &icon, &color)
        .map_err(|e| anyhow::anyhow!("{e}"))
}

/// Elimina una categoría custom (no del sistema).
pub fn delete_category(db_path: String, category_id: String) -> anyhow::Result<bool> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let u = uuid::Uuid::parse_str(&category_id).map_err(|e| anyhow::anyhow!("{e}"))?;
    store::delete_category(&conn, u.as_bytes()).map_err(|e| anyhow::anyhow!("{e}"))
}

#[derive(Debug, Clone)]
pub struct HomeSummaryDto {
    pub total_balance: f64,
    pub monthly_expense: f64,
    pub monthly_income: f64,
    pub prev_month_expense: f64,
    pub delta_expense_pct: Option<f64>,
    pub currency: String,
}

impl From<store::HomeSummary> for HomeSummaryDto {
    fn from(s: store::HomeSummary) -> Self {
        HomeSummaryDto {
            total_balance: s.total_balance,
            monthly_expense: s.monthly_expense,
            monthly_income: s.monthly_income,
            prev_month_expense: s.prev_month_expense,
            delta_expense_pct: s.delta_expense_pct,
            currency: s.currency,
        }
    }
}

/// Devuelve el resumen financiero para el Home Tab.
pub fn get_home_summary(db_path: String, currency: String) -> anyhow::Result<HomeSummaryDto> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    Ok(store::get_home_summary(&conn, &currency)
        .map_err(|e| anyhow::anyhow!("{e}"))?
        .into())
}

#[derive(Debug, Clone)]
pub struct StreakDto {
    pub current_streak: i32,
    pub max_streak: i32,
    pub active_today: bool,
}

impl From<store::UsageStreak> for StreakDto {
    fn from(s: store::UsageStreak) -> Self {
        StreakDto {
            current_streak: s.current_streak,
            max_streak: s.max_streak,
            active_today: s.active_today,
        }
    }
}

/// Calcula la racha de días consecutivos de registro de gastos.
pub fn get_usage_streak(db_path: String) -> anyhow::Result<StreakDto> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    Ok(store::get_usage_streak(&conn)
        .map_err(|e| anyhow::anyhow!("{e}"))?
        .into())
}

// ============================================================================
// Exportación de Datos y Backups Cifrados (Fase 6)
// ============================================================================

#[derive(Debug, Clone, Default)]
pub struct BackupRestoreSummaryDto {
    pub accounts: usize,
    pub categories: usize,
    pub transactions: usize,
    pub installments: usize,
    pub recurring_rules: usize,
    pub exchange_rates: usize,
    pub budgets: usize,
    pub saving_goals: usize,
}

impl From<crate::backup::BackupRestoreSummary> for BackupRestoreSummaryDto {
    fn from(s: crate::backup::BackupRestoreSummary) -> Self {
        Self {
            accounts: s.accounts,
            categories: s.categories,
            transactions: s.transactions,
            installments: s.installments,
            recurring_rules: s.recurring_rules,
            exchange_rates: s.exchange_rates,
            budgets: s.budgets,
            saving_goals: s.saving_goals,
        }
    }
}

/// Exporta las transacciones a formato CSV estándar RFC 4180.
pub fn export_transactions_csv(db_path: String) -> anyhow::Result<String> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    crate::backup::export_transactions_csv(&conn).map_err(|e| anyhow::anyhow!("{e}"))
}

/// Exporta todas las tablas relacionales en un JSON plano legible.
pub fn export_all_data_json(db_path: String) -> anyhow::Result<String> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    crate::backup::export_all_data_json(&conn).map_err(|e| anyhow::anyhow!("{e}"))
}

/// Exporta movimientos para reentrenamiento de Needle 3 (formato make_dataset.py).
pub fn export_corrections_for_training(db_path: String) -> anyhow::Result<String> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    store::export_corrections_jsonl(&conn, TOOLS).map_err(|e| anyhow::anyhow!("{e}"))
}

/// Genera una copia de seguridad cifrada (.mnbackup) con la contraseña o frase provista.
pub fn create_encrypted_backup(db_path: String, passphrase: String) -> anyhow::Result<Vec<u8>> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    crate::backup::create_encrypted_backup(&conn, &passphrase).map_err(|e| anyhow::anyhow!("{e}"))
}

/// Restaura una copia de seguridad cifrada (.mnbackup) en la base de datos viva.
/// Realiza un respaldo físico previo en disco antes de aplicar los cambios en una transacción atómica.
pub fn restore_encrypted_backup(
    db_path: String,
    backup_bytes: Vec<u8>,
    passphrase: String,
) -> anyhow::Result<BackupRestoreSummaryDto> {
    // Zero-Loss: Copia de seguridad física previa antes de restaurar
    if db_path != ":memory:" && !db_path.is_empty() {
        let _ = crate::migrations::backup_database_file(&db_path);
    }
    let mut conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let summary = crate::backup::restore_encrypted_backup(&mut conn, &backup_bytes, &passphrase)
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    Ok(BackupRestoreSummaryDto::from(summary))
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct FinancialInsightDto {
    pub title: String,
    pub message: String,
    pub insight_type: String, // "projection", "tip", "info", "warning"
    pub safe_to_spend_daily: Option<f64>,
    pub projected_month_expense: f64,
    pub top_increasing_category: Option<String>,
    pub top_increasing_percentage: Option<f64>,
}

impl From<crate::insights::FinancialInsight> for FinancialInsightDto {
    fn from(i: crate::insights::FinancialInsight) -> Self {
        Self {
            title: i.title,
            message: i.message,
            insight_type: i.insight_type,
            safe_to_spend_daily: i.safe_to_spend_daily,
            projected_month_expense: i.projected_month_expense,
            top_increasing_category: i.top_increasing_category,
            top_increasing_percentage: i.top_increasing_percentage,
        }
    }
}

/// Genera recomendaciones y métricas predictivas automáticas para el usuario.
pub fn get_financial_insights(
    db_path: String,
    currency: String,
) -> anyhow::Result<Vec<FinancialInsightDto>> {
    let conn = store::open_default(&db_path).map_err(|e| anyhow::anyhow!("{e}"))?;
    let list = crate::insights::generate_financial_insights(&conn, &currency)
        .map_err(|e| anyhow::anyhow!("{e}"))?;
    Ok(list.into_iter().map(FinancialInsightDto::from).collect())
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

    #[test]
    fn api_sqlcipher_active_key_session_test() {
        let db_path = format!("/tmp/test_api_cipher_{}.db", store::now_ms());
        let _ = std::fs::remove_file(&db_path);

        let master_key = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef".to_string();

        // 1. Inicializar con clave SQLCipher
        init_database(db_path.clone(), Some(master_key)).unwrap();

        // 2. Operaciones subsecuentes deben usar la clave activa sin fallar
        let accs = list_accounts(db_path.clone()).unwrap();
        assert_eq!(accs.len(), 1);

        let new_id = create_account(
            db_path.clone(),
            "Banco Galicia".into(),
            "bank".into(),
            "ARS".into(),
            100_000.0,
            None,
            None,
            None,
            "#FF0000".into(),
            "bank".into(),
        )
        .unwrap();
        assert!(!new_id.is_empty());

        let accs2 = list_accounts(db_path.clone()).unwrap();
        assert_eq!(accs2.len(), 2);

        // 3. Al bloquear (olvidar clave de sesión), abrir de nuevo debe fallar
        lock_database(db_path.clone()).unwrap();
        let res = list_accounts(db_path.clone());
        assert!(res.is_err(), "Sin la clave de sesión, la base cifrada debe rechazar la apertura");

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn api_transferencias_y_cotizaciones_test() {
        let db_path = format!("/tmp/test_api_transfer_{}.db", store::now_ms());
        let _ = std::fs::remove_file(&db_path);

        init_database(db_path.clone(), None).unwrap();

        // 1. Crear cuenta origen en ARS y destino en USD
        let ars_id = create_account(
            db_path.clone(),
            "Galicia ARS".into(),
            "bank".into(),
            "ARS".into(),
            2_000_000.0,
            None,
            None,
            None,
            "#FF9800".into(),
            "bank".into(),
        )
        .unwrap();

        let usd_id = create_account(
            db_path.clone(),
            "Galicia USD".into(),
            "bank".into(),
            "USD".into(),
            100.0,
            None,
            None,
            None,
            "#4CAF50".into(),
            "bank".into(),
        )
        .unwrap();

        // 2. Transferencia bimonetaria: compra de 1.000 USD con 1.200.000 ARS (cotización 1 USD = 1200 ARS)
        let tx_id = create_transfer(
            db_path.clone(),
            ars_id.clone(),
            usd_id.clone(),
            1_200_000.0,
            1_000.0,
            "Compra dólar MEP".into(),
        )
        .unwrap();
        assert!(!tx_id.is_empty());

        // 3. Verificar saldos actualizados
        let accs = list_accounts(db_path.clone()).unwrap();
        let ars_acc = accs.iter().find(|a| a.id == ars_id).unwrap();
        let usd_acc = accs.iter().find(|a| a.id == usd_id).unwrap();

        assert_eq!(ars_acc.current_balance, 800_000.0);
        assert_eq!(usd_acc.current_balance, 1_100.0);

        // 4. Verificar cotización implícita guardada
        let rate_opt = get_latest_exchange_rate(db_path.clone(), "ARS".into(), "USD".into()).unwrap();
        assert!(rate_opt.is_some());
        let r = rate_opt.unwrap();
        assert_eq!(r.base_currency, "ARS");
        assert_eq!(r.quote_currency, "USD");
        // rate = 1000 / 1200000 = 0.0008333333333333334
        assert!((r.rate - (1_000.0 / 1_200_000.0)).abs() < 1e-6);

        // 5. Verificar lista de cotizaciones
        let all_rates = list_exchange_rates(db_path.clone()).unwrap();
        assert_eq!(all_rates.len(), 1);

        // 6. Verificar que la lista de movimientos muestra la transferencia
        let movs = list_movements(db_path.clone(), 10).unwrap();
        assert!(movs.iter().any(|m| m.tipo == "transferencia" && m.monto == 1_200_000.0));

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn api_analytics_reports_test() {
        let db_path = format!("/tmp/test_api_analytics_{}.db", store::now_ms());
        let _ = std::fs::remove_file(&db_path);

        init_database(db_path.clone(), None).unwrap();
        let accs = list_accounts(db_path.clone()).unwrap();
        let cash_id = accs[0].id.clone();

        let now = store::now_ms();
        let start_ms = now - 86400 * 1000;
        let end_ms = now + 86400 * 1000;

        // 1. Ingreso
        confirm_movement(
            db_path.clone(),
            "ingreso".into(),
            200_000.0,
            "ARS".into(),
            "sueldo".into(),
            "Sueldo".into(),
            "2026-10-01".into(),
            "sueldo 200k".into(),
            Some(cash_id.clone()),
        ).unwrap();

        // 2. Gastos
        confirm_movement(
            db_path.clone(),
            "gasto".into(),
            30_000.0,
            "ARS".into(),
            "supermercado".into(),
            "Compras".into(),
            "2026-10-01".into(),
            "gasto 30k super".into(),
            Some(cash_id.clone()),
        ).unwrap();

        confirm_movement(
            db_path.clone(),
            "gasto".into(),
            10_000.0,
            "ARS".into(),
            "transporte".into(),
            "Nafta".into(),
            "2026-10-01".into(),
            "nafta 10k".into(),
            Some(cash_id.clone()),
        ).unwrap();

        // 3. Category Report
        let cat_rep = get_category_spending_report(db_path.clone(), start_ms, end_ms, "ARS".into()).unwrap();
        assert_eq!(cat_rep.total_amount, 40_000.0);
        assert_eq!(cat_rep.items.len(), 2);
        assert_eq!(cat_rep.items[0].name, "supermercado");
        assert_eq!(cat_rep.items[0].total_amount, 30_000.0);
        assert_eq!(cat_rep.items[0].percentage, 75.0);

        // 4. Financial KPIs
        let kpis = get_financial_kpis(db_path.clone(), start_ms, end_ms, "ARS".into()).unwrap();
        assert_eq!(kpis.total_income, 200_000.0);
        assert_eq!(kpis.total_expense, 40_000.0);
        assert_eq!(kpis.net_savings, 160_000.0);
        assert_eq!(kpis.savings_rate, 80.0);
        assert_eq!(kpis.top_category_name.as_deref(), Some("supermercado"));
        assert_eq!(kpis.top_category_amount, Some(30_000.0));

        // 5. Monthly Cashflow
        let cashflow = get_monthly_cashflow_history(db_path.clone(), "ARS".into(), 6).unwrap();
        assert!(!cashflow.is_empty());
        let last_cf = cashflow.last().unwrap();
        assert_eq!(last_cf.income_amount, 200_000.0);
        assert_eq!(last_cf.expense_amount, 40_000.0);
        assert_eq!(last_cf.net_amount, 160_000.0);

        // 6. Tarjeta y proyección de cuotas
        let card_id = create_account(
            db_path.clone(),
            "Mastercard".into(),
            "credit_card".into(),
            "ARS".into(),
            0.0,
            Some(500_000.0),
            Some(25),
            Some(5),
            "#111111".into(),
            "credit_card".into(),
        ).unwrap();

        confirm_credit_purchase(
            db_path.clone(),
            card_id,
            30_000.0,
            3,
            "hogar".into(),
            "Mesa".into(),
            2026,
            11,
        ).unwrap();

        let commitments = get_installment_commitments(db_path.clone(), "ARS".into()).unwrap();
        assert_eq!(commitments.len(), 3);
        assert_eq!(commitments[0].cycle_month, 11);
        assert_eq!(commitments[0].total_amount, 10_000.0);
        assert_eq!(commitments[1].cycle_month, 12);
        assert_eq!(commitments[1].total_amount, 10_000.0);

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn api_budgets_and_saving_goals_test() {
        let db_path = format!("/tmp/test_api_budgets_{}.db", store::now_ms());
        let _ = std::fs::remove_file(&db_path);

        init_database(db_path.clone(), None).unwrap();
        let accs = list_accounts(db_path.clone()).unwrap();
        let cash_id = accs[0].id.clone();

        let now = store::now_ms();
        let start_ms = now - 86400 * 1000;
        let end_ms = now + 86400 * 1000;

        // Categoría y presupuesto
        confirm_movement(
            db_path.clone(),
            "gasto".into(),
            75_000.0,
            "ARS".into(),
            "supermercado".into(),
            "Super".into(),
            "2026-10-01".into(),
            "super 75k".into(),
            Some(cash_id.clone()),
        ).unwrap();

        // Obtener el category_id a través de la categoría creada
        let cat_rep = get_category_spending_report(db_path.clone(), start_ms, end_ms, "ARS".into()).unwrap();
        let cat_id = cat_rep.items[0].category_id.clone().unwrap();

        let b_id = set_category_budget(
            db_path.clone(),
            cat_id.clone(),
            "ARS".into(),
            100_000.0,
            80,
        ).unwrap();
        assert!(!b_id.is_empty());

        let budgets = list_budgets_status(db_path.clone(), start_ms, end_ms, "ARS".into()).unwrap();
        assert_eq!(budgets.len(), 1);
        assert_eq!(budgets[0].budget_amount, 100_000.0);
        assert_eq!(budgets[0].spent_amount, 75_000.0);
        assert_eq!(budgets[0].remaining_amount, 25_000.0);
        assert_eq!(budgets[0].spent_percentage, 75.0);
        assert_eq!(budgets[0].is_warning, false);

        // Metas de ahorro
        let goal_id = create_saving_goal(
            db_path.clone(),
            "Fondo Emergencia".into(),
            500_000.0,
            "ARS".into(),
            None,
            "#4CAF50".into(),
            "shield".into(),
        ).unwrap();

        let goals = list_saving_goals(db_path.clone()).unwrap();
        assert_eq!(goals.len(), 1);
        assert_eq!(goals[0].target_amount, 500_000.0);
        assert_eq!(goals[0].current_amount, 0.0);

        let new_curr = contribute_to_saving_goal(db_path.clone(), goal_id.clone(), 250_000.0).unwrap();
        assert_eq!(new_curr, 250_000.0);

        let goals_up = list_saving_goals(db_path.clone()).unwrap();
        assert_eq!(goals_up[0].progress_percentage, 50.0);

        assert!(delete_saving_goal(db_path.clone(), goal_id).unwrap());
        assert_eq!(list_saving_goals(db_path.clone()).unwrap().len(), 0);

        assert!(delete_budget(db_path.clone(), b_id).unwrap());
        assert_eq!(list_budgets_status(db_path.clone(), start_ms, end_ms, "ARS".into()).unwrap().len(), 0);

        let _ = std::fs::remove_file(&db_path);
    }

    #[test]
    fn api_export_and_backup_flow_test() {
        let db_path = format!("/tmp/test_api_backup_{}.db", store::now_ms());
        let _ = std::fs::remove_file(&db_path);

        init_database(db_path.clone(), None).unwrap();
        let accs = list_accounts(db_path.clone()).unwrap();
        let acc_id = accs[0].id.clone();

        confirm_movement(
            db_path.clone(),
            "gasto".into(),
            7500.0,
            "ARS".into(),
            "supermercado".into(),
            "Supermercado día".into(),
            "2026-10-01".into(),
            "gasté 7500 en super".into(),
            Some(acc_id),
        ).unwrap();

        // 1. Probar CSV
        let csv = export_transactions_csv(db_path.clone()).unwrap();
        assert!(csv.contains("7500.00"));
        assert!(csv.contains("supermercado"));

        // 2. Probar JSON
        let json = export_all_data_json(db_path.clone()).unwrap();
        assert!(json.contains("\"MoneyNeedle\""));

        // 3. Probar JSONL para training
        let jsonl = export_corrections_for_training(db_path.clone()).unwrap();
        assert!(jsonl.contains("add_transaction"));
        assert!(jsonl.contains("supermercado"));

        // 4. Probar Backup cifrado y restauración
        let pass = "test-secret-phrase";
        let backup_bytes = create_encrypted_backup(db_path.clone(), pass.into()).unwrap();
        assert!(backup_bytes.len() > 50);

        let restore_db = format!("/tmp/test_api_restore_{}.db", store::now_ms());
        let _ = std::fs::remove_file(&restore_db);
        init_database(restore_db.clone(), None).unwrap();

        let summary = restore_encrypted_backup(restore_db.clone(), backup_bytes, pass.into()).unwrap();
        assert!(summary.transactions >= 1);

        let movs = list_movements(restore_db.clone(), 10).unwrap();
        assert_eq!(movs.len(), 1);
        assert_eq!(movs[0].monto, 7500.0);

        let _ = std::fs::remove_file(&db_path);
        let _ = std::fs::remove_file(&restore_db);
    }

    #[test]
    fn api_crud_flow_test() {
        let db_path = format!("/tmp/test_api_crud_{}.db", store::now_ms());
        let _ = std::fs::remove_file(&db_path);

        init_database(db_path.clone(), None).unwrap();
        let accs = list_accounts(db_path.clone()).unwrap();
        let acc_id = accs[0].id.clone();

        // 1. Confirmar movimiento
        let mov_id = confirm_movement(
            db_path.clone(),
            "gasto".into(),
            4500.0,
            "ARS".into(),
            "comida".into(),
            "pizza".into(),
            "2026-10-01".into(),
            "pizza 4500".into(),
            Some(acc_id.clone()),
        ).unwrap();

        // 2. Buscar movimientos
        let search_res = search_movements(
            db_path.clone(),
            Some("pizza".into()),
            None,
            None,
            None,
            None,
            None,
            10,
            0,
        ).unwrap();
        assert_eq!(search_res.len(), 1);
        assert_eq!(search_res[0].id, mov_id);

        // 3. Editar movimiento
        let updated = update_movement(
            db_path.clone(),
            mov_id.clone(),
            "gasto".into(),
            5000.0,
            "ARS".into(),
            "comida".into(),
            "pizza grande".into(),
            "2026-10-01".into(),
            Some(acc_id.clone()),
        ).unwrap();
        assert!(updated);

        let list_after_up = list_movements(db_path.clone(), 10).unwrap();
        assert_eq!(list_after_up[0].monto, 5000.0);
        assert_eq!(list_after_up[0].descripcion, "pizza grande");

        // 4. Soft-delete y Restore
        assert!(delete_movement(db_path.clone(), mov_id.clone()).unwrap());
        assert_eq!(list_movements(db_path.clone(), 10).unwrap().len(), 0);

        assert!(restore_movement(db_path.clone(), mov_id.clone()).unwrap());
        assert_eq!(list_movements(db_path.clone(), 10).unwrap().len(), 1);

        // 5. Home Summary y Streak
        let summary = get_home_summary(db_path.clone(), "ARS".into()).unwrap();
        assert_eq!(summary.monthly_expense, 5000.0);

        let streak = get_usage_streak(db_path.clone()).unwrap();
        assert_eq!(streak.current_streak, 1);

        // 6. Categorías custom
        let cat_id = create_category(
            db_path.clone(),
            "Suscripciones".into(),
            "subscriptions".into(),
            "#9C27B0".into(),
            None,
        ).unwrap();
        assert!(!cat_id.is_empty());

        assert!(update_category(
            db_path.clone(),
            cat_id.clone(),
            "Streaming".into(),
            "tv".into(),
            "#673AB7".into(),
        ).unwrap());

        assert!(delete_category(db_path.clone(), cat_id).unwrap());

        // 7. Insights financieros
        let insights = get_financial_insights(db_path.clone(), "ARS".into()).unwrap();
        assert!(!insights.is_empty());

        let _ = std::fs::remove_file(&db_path);
    }
}
