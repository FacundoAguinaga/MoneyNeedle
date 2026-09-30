"""Lógica pura compartida de MoneyNeedle (sin I/O, sin modelo).

La usan chat.py, eval.py y make_dataset.py. Todo lo de acá tiene tests
en test_mn_parse.py que corren en milisegundos sin GPU.
"""
import re

KEYWORDS = {
    "transporte": ["taxi", "uber", "didi", "bondi", "colectivo", "nafta",
                   "gasoil", "subte", "tren", "remis", "estacionamiento",
                   "peaje"],
    "comida": ["delivery", "café", "cafe", "cena", "almuerzo", "restaurant",
               "parrilla", "pizza", "empanada", "helado", "asado", "brunch",
               "birras", "dietética", "dietetica"],
    "supermercado": ["súper", "super", "verdulería", "verduleria", "kiosco",
                     "kiosko", "almacén", "almacen", "chino", "disco",
                     "carnicería", "carniceria", "panadería", "panaderia"],
    "alquiler": ["alquiler", "cochera", "expensas", "depto"],
    "servicios": ["luz", "gas", "agua", "internet", "tarjeta", "celular",
                  "impuesto", "netflix", "spotify", "prime", "disney",
                  "hbo", "youtube", "streaming", "telecentro", "aysa",
                  "edenor", "metrogas", "patente"],
    "salud": ["farmacia", "médico", "medico", "dentista", "obra social",
              "psicólogo", "psicologo", "óptica", "optica", "análisis",
              "analisis", "remedios", "oculista"],
    "sueldo": ["sueldo", "aguinaldo", "salario", "bono", "liquidación",
               "liquidacion"],
    "otros": ["ropa", "zapatilla", "perfume", "peluquería", "peluqueria",
              "préstamo", "prestamo", "freelance", "banco", "auto",
              "mecánico", "mecanico", "taller", "ferretería", "ferreteria",
              "librería", "libreria", "regalo", "veterinaria", "clases"],
}

CURRENCIES = [
    ("USD", ["usd", "u$s", "dólar", "dolar", "dólares", "dolares"]),
    ("EUR", ["eur", "euro", "euros"]),
]

UNITS = {
    "cero": 0, "uno": 1, "un": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4,
    "cinco": 5, "seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10,
    "once": 11, "doce": 12, "trece": 13, "catorce": 14, "quince": 15,
    "dieciséis": 16, "dieciseis": 16, "diecisiete": 17, "dieciocho": 18,
    "diecinueve": 19, "veinte": 20, "veintiuno": 21, "veintidos": 22,
    "veintitres": 23, "veintitrés": 23, "veinticuatro": 24, "veinticinco": 25,
    "veintiséis": 26, "veintiseis": 26, "veintisiete": 27, "veintiocho": 28,
    "veintinueve": 29, "treinta": 30, "cuarenta": 40, "cincuenta": 50,
    "sesenta": 60, "setenta": 70, "ochenta": 80, "noventa": 90, "cien": 100,
    "ciento": 100, "doscientos": 200, "trescientos": 300, "cuatrocientos": 400,
    "quinientos": 500, "seiscientos": 600, "setecientos": 700,
    "ochocientos": 800, "novecientos": 900,
}

MULT_WORDS = {"mil": 1000, "millón": 1_000_000, "millon": 1_000_000,
              "millones": 1_000_000, "luca": 1000, "lucas": 1000}

NUM_RE = re.compile(r"(\d[\d\.,]*)\s*(millones|millón|millon|mil|k|lucas?)?",
                    re.IGNORECASE)


def parse_number_token(raw: str) -> float:
    """Parsea un token numérico con heurística ar-es.

    Punto con exactamente 3 dígitos finales (o varios puntos) = miles:
    "35.000"->35000, "1.200.000"->1200000. Si no, decimal: "10.50"->10.5.
    Coma con 2 finales = decimal ("10,50"->10.5); con 3 = miles ("8,400"->8400).
    """
    s = raw.strip()
    if "," in s and "." in s:
        # "1.200,50": puntos miles, coma decimal
        return float(s.replace(".", "").replace(",", "."))
    if "," in s:
        head, _, tail = s.rpartition(",")
        if len(tail) == 2 and head:
            return float(f"{head.replace('.', '')}.{tail}")
        return float(s.replace(",", "").replace(".", ""))
    if "." in s:
        if s.count(".") > 1:
            return float(s.replace(".", ""))
        head, _, tail = s.partition(".")
        if len(tail) == 3 and head and head != "0":
            return float(head + tail)  # miles: 35.000
        return float(s)  # decimal: 10.50
    return float(s)


def words_to_number(text: str) -> list[float]:
    """Extrae números en palabras: 'cinco mil' -> 5000."""
    return [v for _, _, v in find_word_numbers(text)]


def find_word_numbers(text: str) -> list[tuple[int, int, float]]:
    """Como words_to_number pero con spans (inicio, fin, valor).

    Sirve para sustituir el número en palabras por otro monto.
    """
    out = []
    tokens = [(m.group(0).lower(), m.start(), m.end())
              for m in re.finditer(r"[a-záéíóúñ]+", text.lower())]
    acc = current = 0
    start = None
    hit = False

    def flush(end: int):
        nonlocal acc, current, start, hit
        if hit and start is not None:
            out.append((start, end, float(acc + current)))
        acc = current = 0
        start = None
        hit = False

    for tok, s, e in tokens:
        if tok in UNITS:
            if start is None:
                start = s
            current += UNITS[tok]
            hit = True
        elif tok in MULT_WORDS:
            if start is None:
                start = s
            current = (current or 1) * MULT_WORDS[tok]
            if tok in ("mil", "luca", "lucas"):
                acc += current
                current = 0
            hit = True
        elif tok == "y":
            continue
        else:
            flush(s)
    flush(len(text))
    return out


def numbers_in_query(query: str) -> list[float]:
    """Todos los montos candidatos mencionados en el texto."""
    out = []
    for m in NUM_RE.finditer(query):
        try:
            val = parse_number_token(m.group(1))
        except ValueError:
            continue
        suffix = (m.group(2) or "").lower()
        if suffix in ("k", "luca", "lucas", "mil"):
            val *= 1000
        elif suffix.startswith("millo"):  # millón / millones
            val *= 1_000_000
        out.append(val)
    out.extend(words_to_number(query))
    return out


def keyword_category(query: str) -> str | None:
    """Match por palabra completa ('gas' no matchea 'gaste')."""
    q = query.lower()
    words = set(re.findall(r"[a-záéíóúñ]+", q))
    for cat, kws in KEYWORDS.items():
        for kw in kws:
            if " " in kw:  # frase multi-palabra: substring es seguro
                if kw in q:
                    return cat
            elif kw in words:
                return cat
    return None


def detect_currency(query: str) -> str:
    q = query.lower()
    for code, words in CURRENCIES:
        if any(w in q for w in words):
            return code
    return "ARS"


def for_model(query: str) -> str:
    """Saca la moneda del prompt (al modelo le alucina montos, ej 'usd'->200000)."""
    q = query
    for _, words in CURRENCIES:
        for w in words:
            q = re.sub(rf"\b{re.escape(w)}\b", "", q, flags=re.IGNORECASE)
    return re.sub(r"\s+", " ", q).strip() or query


def extract_call(result: dict | list | None) -> dict | None:
    """Primer tool_call, incluyendo suppressed_calls (confianza no calibrada)."""
    if result is None:
        return None
    if isinstance(result, list) and result:
        first = result[0]
        if isinstance(first, dict) and "name" in first:
            return first
    if isinstance(result, dict):
        for key in ("function_calls", "suppressed_calls", "calls",
                    "tool_calls", "answers"):
            if isinstance(result.get(key), list) and result[key]:
                return result[key][0]
        if "name" in result and "arguments" in result:
            return result
    return None
