//! Parsing de montos / categorías / moneda en español.
//! Port de `prototype/mn_parse.py` (cero dependencias). Tests espejan
//! `test_mn_parse.py`: cualquier cambio debe pasar en ambos lados.

fn is_word_char(c: char) -> bool {
    c.is_alphabetic()
}

/// Tokeniza palabras en minúsculas con sus spans de bytes.
fn word_tokens(text: &str) -> Vec<(String, usize, usize)> {
    let mut out = Vec::new();
    let mut start: Option<usize> = None;
    for (i, c) in text.char_indices() {
        if is_word_char(c) {
            if start.is_none() {
                start = Some(i);
            }
        } else if let Some(s) = start.take() {
            out.push((text[s..i].to_lowercase(), s, i));
        }
    }
    if let Some(s) = start {
        out.push((text[s..].to_lowercase(), s, text.len()));
    }
    out
}

fn unit_value(w: &str) -> Option<i64> {
    Some(match w {
        "cero" => 0, "uno" | "un" | "una" => 1, "dos" => 2, "tres" => 3,
        "cuatro" => 4, "cinco" => 5, "seis" => 6, "siete" => 7, "ocho" => 8,
        "nueve" => 9, "diez" => 10, "once" => 11, "doce" => 12, "trece" => 13,
        "catorce" => 14, "quince" => 15, "dieciséis" | "dieciseis" => 16,
        "diecisiete" => 17, "dieciocho" => 18, "diecinueve" => 19,
        "veinte" => 20, "veintiuno" => 21, "veintidos" => 22,
        "veintitres" | "veintitrés" => 23, "veinticuatro" => 24,
        "veinticinco" => 25, "veintiséis" | "veintiseis" => 26,
        "veintisiete" => 27, "veintiocho" => 28, "veintinueve" => 29,
        "treinta" => 30, "cuarenta" => 40, "cincuenta" => 50, "sesenta" => 60,
        "setenta" => 70, "ochenta" => 80, "noventa" => 90, "cien" | "ciento" => 100,
        "doscientos" => 200, "trescientos" => 300, "cuatrocientos" => 400,
        "quinientos" => 500, "seiscientos" => 600, "setecientos" => 700,
        "ochocientos" => 800, "novecientos" => 900,
        _ => return None,
    })
}

fn mult_value(w: &str) -> Option<i64> {
    Some(match w {
        "mil" | "luca" | "lucas" => 1000,
        "millón" | "millon" | "millones" => 1_000_000,
        _ => return None,
    })
}

/// Parseo ar-es: punto con 3 finales (o varios puntos) = miles ("35.000"→35000),
/// si no decimal ("10.50"→10.5). Coma con 2 finales = decimal.
pub fn parse_number_token(raw: &str) -> Result<f64, String> {
    let s = raw.trim();
    if s.is_empty() {
        return Err("vacío".into());
    }
    let parse = |t: &str| t.parse::<f64>().map_err(|_| format!("no numérico: {raw}"));
    if s.contains(',') && s.contains('.') {
        return parse(&s.replace('.', "").replace(',', "."));
    }
    if s.contains(',') {
        let cut = s.rfind(',').unwrap();
        let (head, tail) = (&s[..cut], &s[cut + 1..]);
        if tail.len() == 2 && !head.is_empty() {
            return parse(&format!("{}.{}", head.replace('.', ""), tail));
        }
        return parse(&s.replace([',', '.'], ""));
    }
    if s.contains('.') {
        if s.matches('.').count() > 1 {
            return parse(&s.replace('.', ""));
        }
        let cut = s.find('.').unwrap();
        let (head, tail) = (&s[..cut], &s[cut + 1..]);
        if tail.len() == 3 && !head.is_empty() && head != "0" {
            return parse(&format!("{head}{tail}"));
        }
        return parse(s);
    }
    parse(s)
}

/// Números en palabras con spans: "gaste cinco mil" → [(6, 15, 5000)].
pub fn find_word_numbers(text: &str) -> Vec<(usize, usize, f64)> {
    let mut out = Vec::new();
    let mut acc: i64 = 0;
    let mut current: i64 = 0;
    let mut start: Option<usize> = None;
    let mut hit = false;
    let mut flush = |end: usize, acc: &mut i64, current: &mut i64,
                     start: &mut Option<usize>, hit: &mut bool| {
        if *hit {
            if let Some(s) = start.take() {
                out.push((s, end, (*acc + *current) as f64));
            }
        }
        *acc = 0;
        *current = 0;
        *hit = false;
    };
    for (tok, s, _) in word_tokens(text) {
        if let Some(v) = unit_value(&tok) {
            if start.is_none() {
                start = Some(s);
            }
            current += v;
            hit = true;
        } else if let Some(m) = mult_value(&tok) {
            if start.is_none() {
                start = Some(s);
            }
            current = if current == 0 { m } else { current * m };
            if m == 1000 {
                acc += current;
                current = 0;
            }
            hit = true;
        } else if tok == "y" {
            continue;
        } else {
            flush(s, &mut acc, &mut current, &mut start, &mut hit);
        }
    }
    let len = text.len();
    flush(len, &mut acc, &mut current, &mut start, &mut hit);
    out
}

/// Todos los montos candidatos: dígitos (con k/lucas/mil/millones) + palabras.
pub fn numbers_in_query(query: &str) -> Vec<f64> {
    let mut out = Vec::new();
    let bytes = query.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i].is_ascii_digit() {
            let mut j = i;
            while j < bytes.len() && (bytes[j].is_ascii_digit() || bytes[j] == b'.' || bytes[j] == b',') {
                j += 1;
            }
            let raw = &query[i..j];
            // sufijo opcional: palabra pegada o separada por espacios
            let mut k = j;
            while k < bytes.len() && bytes[k] == b' ' {
                k += 1;
            }
            let mut suffix = String::new();
            if k < bytes.len() && bytes[k].is_ascii_alphabetic() {
                let mut l = k;
                while l < bytes.len() && bytes[l].is_ascii_alphabetic() {
                    l += 1;
                }
                suffix = query[k..l].to_lowercase();
                static SUFS: &[&str] = &["millones", "millón", "millon", "mil", "k", "lucas", "luca"];
                if !SUFS.contains(&suffix.as_str()) {
                    suffix.clear();
                }
            }
            if let Ok(mut val) = parse_number_token(raw) {
                if ["k", "luca", "lucas", "mil"].contains(&suffix.as_str()) {
                    val *= 1000.0;
                } else if suffix.starts_with("millo") {
                    val *= 1_000_000.0;
                }
                out.push(val);
            }
            i = j.max(i + 1);
        } else {
            i += 1;
        }
    }
    for (_, _, v) in find_word_numbers(query) {
        out.push(v);
    }
    out
}

fn has_word(words: &[String], w: &str) -> bool {
    words.iter().any(|x| x == w)
}

/// Match por palabra completa ("gas" no matchea "gaste").
pub fn keyword_category(query: &str) -> Option<&'static str> {
    let q = query.to_lowercase();
    let words: Vec<String> = word_tokens(&q).into_iter().map(|(w, _, _)| w).collect();
    // (categoría, keywords de 1 palabra, frases multi-palabra)
    const CATS: &[(&str, &[&str], &[&str])] = &[
        ("transporte", &["taxi", "uber", "didi", "bondi", "colectivo", "nafta", "gasoil", "subte", "tren", "remis", "estacionamiento", "peaje"], &[]),
        ("comida", &["delivery", "café", "cafe", "cena", "almuerzo", "restaurant", "parrilla", "pizza", "empanada", "helado", "asado", "brunch", "birras", "dietética", "dietetica"], &[]),
        ("supermercado", &["súper", "super", "verdulería", "verduleria", "kiosco", "kiosko", "almacén", "almacen", "chino", "disco", "carnicería", "carniceria", "panadería", "panaderia"], &[]),
        ("alquiler", &["alquiler", "cochera", "expensas", "depto"], &[]),
        ("servicios", &["luz", "gas", "agua", "internet", "tarjeta", "celular", "impuesto", "netflix", "spotify", "prime", "disney", "hbo", "youtube", "streaming", "telecentro", "aysa", "edenor", "metrogas", "patente"], &[]),
        ("salud", &["farmacia", "médico", "medico", "dentista", "psicólogo", "psicologo", "óptica", "optica", "análisis", "analisis", "remedios", "oculista"], &["obra social"]),
        ("sueldo", &["sueldo", "aguinaldo", "salario", "bono", "liquidación", "liquidacion"], &[]),
        ("otros", &["ropa", "zapatilla", "perfume", "peluquería", "peluqueria", "préstamo", "prestamo", "freelance", "banco", "auto", "mecánico", "mecanico", "taller", "ferretería", "ferreteria", "librería", "libreria", "regalo", "veterinaria", "clases"], &[]),
    ];
    for (cat, single, phrases) in CATS {
        if phrases.iter().any(|p| q.contains(p)) {
            return Some(cat);
        }
        if single.iter().any(|w| has_word(&words, w)) {
            return Some(cat);
        }
    }
    None
}

pub fn detect_currency(query: &str) -> &'static str {
    let q = query.to_lowercase();
    let words: Vec<String> = word_tokens(&q).into_iter().map(|(w, _, _)| w).collect();
    for w in ["usd", "dólar", "dolar", "dólares", "dolares"] {
        if has_word(&words, w) {
            return "USD";
        }
    }
    for w in ["eur", "euro", "euros"] {
        if has_word(&words, w) {
            return "EUR";
        }
    }
    // "u$s" no es palabra: substring acotado
    if q.contains("u$s") {
        return "USD";
    }
    "ARS"
}

/// Saca la moneda del prompt (al modelo le alucina montos, ej "usd"→200000).
pub fn for_model(query: &str) -> String {
    let mut q = format!(" {query} ");
    for w in ["usd", "u$s", "dólar", "dolar", "dólares", "dolares", "eur", "euro", "euros"] {
        // reemplazo insensible a mayúsculas por palabra
        let mut out = String::with_capacity(q.len());
        let ql = q.to_lowercase();
        let mut i = 0;
        while let Some(pos) = ql[i..].find(w) {
            let a = i + pos;
            let b = a + w.len();
            let before = q[..a].chars().next_back().map(|c| is_word_char(c)).unwrap_or(false);
            let after = q[b..].chars().next().map(|c| is_word_char(c)).unwrap_or(false);
            if !before && !after {
                out.push_str(&q[i..a]);
                out.push(' ');
                i = b;
            } else {
                out.push_str(&q[i..b]);
                i = b;
            }
        }
        out.push_str(&q[i..]);
        q = out;
    }
    let squished = q.split_whitespace().collect::<Vec<_>>().join(" ");
    if squished.is_empty() { query.to_string() } else { squished }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn has(nums: &[f64], v: f64) -> bool {
        nums.iter().any(|n| (n - v).abs() < 0.01)
    }

    #[test]
    fn miles_y_decimales() {
        assert_eq!(parse_number_token("35.000").unwrap(), 35000.0);
        assert_eq!(parse_number_token("1.200.000").unwrap(), 1200000.0);
        assert!((parse_number_token("10.50").unwrap() - 10.5).abs() < 1e-9);
        assert!((parse_number_token("10,50").unwrap() - 10.5).abs() < 1e-9);
        assert_eq!(parse_number_token("8,400").unwrap(), 8400.0);
    }

    #[test]
    fn numeros_en_frase() {
        assert!(has(&numbers_in_query("taxi 8000 ayer"), 8000.0));
        assert!(has(&numbers_in_query("me pagaron 200k"), 200000.0));
        assert!(has(&numbers_in_query("5 lucas en súper"), 5000.0));
        assert!(has(&numbers_in_query("pague mil en impuestos"), 1000.0));
        assert!(has(&numbers_in_query("compre 200 mil en ropa"), 200000.0));
        assert!(has(&numbers_in_query("pagué 290.000 del alquiler"), 290000.0));
        assert!(has(&numbers_in_query("pagé 10.50 de café"), 10.5));
        assert!(has(&numbers_in_query("doscientos mil del sueldo"), 200000.0));
    }

    #[test]
    fn word_spans() {
        let spans = find_word_numbers("gaste cinco mil en súper");
        assert_eq!(spans.len(), 1);
        assert_eq!(spans[0].2, 5000.0);
        assert!(find_word_numbers("hola qué hora es").is_empty());
    }

    #[test]
    fn keywords_sin_substring() {
        assert_ne!(keyword_category("gaste 1000000 en el auto"), Some("servicios"));
        assert_eq!(keyword_category("pagué el gas"), Some("servicios"));
        assert_eq!(keyword_category("taxi 8000"), Some("transporte"));
        assert_eq!(keyword_category("obra social 5000"), Some("salud"));
        assert_eq!(keyword_category("hola qué tal"), None);
    }

    #[test]
    fn moneda() {
        assert_eq!(detect_currency("perfume de 100 usd"), "USD");
        assert_eq!(detect_currency("gasté 5000"), "ARS");
        assert_eq!(for_model("gaste 100 usd en netflix"), "gaste 100 en netflix");
    }
}
