use rusqlite::Connection;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use crate::store::{self, days_in_month};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FinancialInsight {
    pub title: String,
    pub message: String,
    pub insight_type: String, // "projection", "tip", "info", "warning"
    pub safe_to_spend_daily: Option<f64>,
    pub projected_month_expense: f64,
    pub top_increasing_category: Option<String>,
    pub top_increasing_percentage: Option<f64>,
}

/// Genera insights financieros accionables para el usuario.
pub fn generate_financial_insights(
    conn: &Connection,
    currency: &str,
) -> Result<Vec<FinancialInsight>, String> {
    let now = store::now_ms();
    let now_secs = (now / 1000) as u64;
    let curr_date = store::chrono_mock::NaiveDate::from_timestamp_opt(now_secs);
    let year = curr_date.year;
    let month = curr_date.month as i32;
    let day = curr_date.day as i32;

    let total_days = days_in_month(year, month);
    let days_elapsed = day.max(1);
    let days_remaining = (total_days.saturating_sub(day) + 1).max(1);

    let summary = store::get_home_summary(conn, currency)?;
    let monthly_expense = summary.monthly_expense;
    let monthly_income = summary.monthly_income;

    // 1. Proyección a fin de mes
    let projected_month_expense = if days_elapsed > 0 {
        (monthly_expense / days_elapsed as f64) * total_days as f64
    } else {
        monthly_expense
    };
    let projected_month_expense = (projected_month_expense * 100.0).round() / 100.0;

    // 2. Gasto diario disponible (Safe to spend)
    let total_budget_cents: i64 = conn
        .query_row(
            "SELECT COALESCE(SUM(amount), 0) FROM budgets WHERE deleted_at IS NULL AND currency = ?1",
            rusqlite::params![currency],
            |row| row.get(0),
        )
        .unwrap_or(0);
    let total_budget = total_budget_cents as f64 / 100.0;

    let safe_to_spend_daily = if total_budget > 0.0 {
        let available = (total_budget - monthly_expense).max(0.0);
        Some(((available / days_remaining as f64) * 100.0).round() / 100.0)
    } else if monthly_income > 0.0 {
        let available = (monthly_income - monthly_expense).max(0.0);
        Some(((available / days_remaining as f64) * 100.0).round() / 100.0)
    } else {
        None
    };

    // 3. Categoría con mayor incremento vs mes anterior
    let (prev_year, prev_month) = if month == 1 {
        (year - 1, 12)
    } else {
        (year, month - 1)
    };

    let mut stmt = conn
        .prepare(
            "SELECT c.name, t.amount, t.date
             FROM transactions t
             JOIN categories c ON t.category_id = c.id
             WHERE t.deleted_at IS NULL
               AND t.currency = ?1
               AND t.transaction_type = 'expense'",
        )
        .map_err(|e| e.to_string())?;

    let rows = stmt
        .query_map(rusqlite::params![currency], |row| {
            let cat_name: String = row.get(0)?;
            let amt: i64 = row.get(1)?;
            let date_ms: i64 = row.get(2)?;
            Ok((cat_name, amt, date_ms))
        })
        .map_err(|e| e.to_string())?;

    let mut curr_cat_expense: HashMap<String, i64> = HashMap::new();
    let mut prev_cat_expense: HashMap<String, i64> = HashMap::new();

    for r in rows {
        let (cat, amt, date_ms) = r.map_err(|e| e.to_string())?;
        let secs = (date_ms.max(0) / 1000) as u64;
        let d = store::chrono_mock::NaiveDate::from_timestamp_opt(secs);
        if d.year == year && d.month as i32 == month {
            *curr_cat_expense.entry(cat).or_insert(0) += amt;
        } else if d.year == prev_year && d.month as i32 == prev_month {
            *prev_cat_expense.entry(cat).or_insert(0) += amt;
        }
    }

    let mut top_increasing_category: Option<String> = None;
    let mut top_increasing_percentage: Option<f64> = None;
    let mut max_delta_pct: f64 = 0.0;

    for (cat, curr_amt) in &curr_cat_expense {
        if let Some(&prev_amt) = prev_cat_expense.get(cat) {
            if prev_amt > 0 && *curr_amt > prev_amt {
                let pct = ((*curr_amt - prev_amt) as f64 / prev_amt as f64) * 100.0;
                if pct > max_delta_pct {
                    max_delta_pct = pct;
                    top_increasing_category = Some(cat.clone());
                    top_increasing_percentage = Some((pct * 10.0).round() / 10.0);
                }
            }
        }
    }

    // Armar lista de insights
    let mut insights = Vec::new();

    // Insight 1: Proyección
    if projected_month_expense > monthly_income && monthly_income > 0.0 {
        insights.push(FinancialInsight {
            title: "Proyección superior a ingresos".into(),
            message: format!(
                "Al ritmo actual proyectás gastar ${:.0} {}, superando tus ingresos registrados (${:.0} {}).",
                projected_month_expense, currency, monthly_income, currency
            ),
            insight_type: "warning".into(),
            safe_to_spend_daily,
            projected_month_expense,
            top_increasing_category: top_increasing_category.clone(),
            top_increasing_percentage,
        });
    } else if monthly_expense > 0.0 {
        insights.push(FinancialInsight {
            title: "Proyección a fin de mes".into(),
            message: format!(
                "Al ritmo actual de gasto proyectás cerrar el mes en ${:.0} {}.",
                projected_month_expense, currency
            ),
            insight_type: "projection".into(),
            safe_to_spend_daily,
            projected_month_expense,
            top_increasing_category: top_increasing_category.clone(),
            top_increasing_percentage,
        });
    } else {
        insights.push(FinancialInsight {
            title: "Inicio de mes en balance".into(),
            message: "Aún no registraste gastos significativos este mes. Mantené el registro diario para proyectar con precisión.".into(),
            insight_type: "info".into(),
            safe_to_spend_daily,
            projected_month_expense,
            top_increasing_category: top_increasing_category.clone(),
            top_increasing_percentage,
        });
    }

    // Insight 2: Gasto diario disponible
    if let Some(safe) = safe_to_spend_daily {
        insights.push(FinancialInsight {
            title: "Gasto diario sugerido".into(),
            message: format!(
                "Tenés disponible hasta ${:.0} {} por día durante los próximos {} días.",
                safe, currency, days_remaining
            ),
            insight_type: "tip".into(),
            safe_to_spend_daily: Some(safe),
            projected_month_expense,
            top_increasing_category: top_increasing_category.clone(),
            top_increasing_percentage,
        });
    }

    // Insight 3: Rubro con mayor aumento
    if let Some(ref cat) = top_increasing_category {
        if let Some(pct) = top_increasing_percentage {
            insights.push(FinancialInsight {
                title: "Rubro con mayor aumento".into(),
                message: format!(
                    "El gasto en '{}' aumentó un {:.0}% en comparación con el mes pasado.",
                    cat, pct
                ),
                insight_type: "info".into(),
                safe_to_spend_daily,
                projected_month_expense,
                top_increasing_category: Some(cat.clone()),
                top_increasing_percentage: Some(pct),
            });
        }
    }

    Ok(insights)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::TipoMovimiento::{Gasto, Ingreso};

    #[test]
    fn test_generate_financial_insights_flow() {
        let conn = store::open_default(":memory:").unwrap();

        // Ingreso de $100.000 ARS y Gasto de $20.000 ARS en el mes
        store::insert(
            &conn,
            &Ingreso,
            100_000.0,
            "ARS",
            "sueldo",
            "Sueldo",
            "2026-10-01",
            "Sueldo 100k",
        )
        .unwrap();

        store::insert(
            &conn,
            &Gasto,
            20_000.0,
            "ARS",
            "supermercado",
            "Super",
            "2026-10-01",
            "Super 20k",
        )
        .unwrap();

        let insights = generate_financial_insights(&conn, "ARS").unwrap();
        assert!(!insights.is_empty());

        let proj = insights
            .iter()
            .find(|i| i.insight_type == "projection" || i.insight_type == "warning");
        assert!(proj.is_some());
        let tip = insights.iter().find(|i| i.insight_type == "tip");
        assert!(tip.is_some());
        assert!(tip.unwrap().safe_to_spend_daily.is_some());
    }
}
