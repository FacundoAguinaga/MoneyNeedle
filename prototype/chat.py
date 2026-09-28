"""Probador interactivo MoneyNeedle — Fase 0.

Escribís movimientos como le hablarías a la app y Needle 3 propone la carga.
Vos confirmás / editás / descartás. Todo queda guardado:
  - movimientos_confirmados.jsonl  (tu registro)
  - corrections.jsonl              (futuro data.jsonl para finetune)

Uso:
  .venv/bin/python chat.py [--tools tools.json]

Comandos dentro del chat: /resumen /salir
"""
import argparse
import datetime
import json
import pathlib
import re
import sys

BASE = pathlib.Path(__file__).parent

# --- keywords fallback para categoría (hasta que haya finetune) ---
KEYWORDS = {
    "transporte": ["taxi", "uber", "bondi", "colectivo", "nafta", "subte", "tren", "remis", "estacionamiento"],
    "comida": ["delivery", "café", "cafe", "cena", "almuerzo", "restaurant", "parrilla", "pizza", "empanada", "helado", "asado"],
    "supermercado": ["súper", "super", "verdulería", "verduleria", "kiosco", "kiosko", "almacén", "almacen", "chino"],
    "alquiler": ["alquiler"],
    "servicios": ["luz", "gas", "agua", "internet", "tarjeta", "expensas", "celular", "impuesto", "netflix", "spotify", "prime", "disney", "hbo", "youtube", "streaming"],
    "salud": ["farmacia", "médico", "medico", "dentista", "obra social"],
    "sueldo": ["sueldo", "aguinaldo", "salario"],
    "otros": ["ropa", "zapatilla", "perfume", "peluquería", "peluqueria", "préstamo", "prestamo", "freelance", "banco", "auto", "mecánico", "mecanico", "taller"],
}

CURRENCIES = [
    ("USD", ["usd", "u$s", "dólar", "dolar", "dólares", "dolares"]),
    ("EUR", ["eur", "euro", "euros"]),
]


def detect_currency(query: str) -> str:
    q = query.lower()
    for code, words in CURRENCIES:
        if any(w in q for w in words):
            return code
    return "ARS"


def for_model(query: str) -> str:
    """Saca tokens que confunden al modelo (monedas -> números fantasma).
    La moneda la detecta la app por separado."""
    q = query
    for _, words in CURRENCIES:
        for w in words:
            q = re.sub(rf"\b{re.escape(w)}\b", "", q, flags=re.IGNORECASE)
    return re.sub(r"\s+", " ", q).strip() or query

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


def words_to_number(text: str) -> list[float]:
    """Extrae números en palabras: 'cinco mil' -> 5000, 'doscientos mil' -> 200000."""
    out = []
    tokens = re.findall(r"[a-záéíóúñ]+", text.lower())
    acc = 0
    current = 0
    hit = False
    for t in tokens:
        if t in UNITS:
            current += UNITS[t]
            hit = True
        elif t == "mil":
            current = (current or 1) * 1000
            acc += current
            current = 0
            hit = True
        elif t in ("millón", "millon", "millones"):
            current = (current or 1) * 1_000_000
            acc += current
            current = 0
            hit = True
        elif t in ("luca", "lucas"):
            current = (current or 1) * 1000
            acc += current
            current = 0
            hit = True
        elif t == "y":
            continue
        else:
            if hit:
                out.append(float(acc + current))
                acc = current = 0
                hit = False
    if hit:
        out.append(float(acc + current))
    return out


def numbers_in_query(query: str) -> list[float]:
    """Todos los montos candidatos mencionados en el texto."""
    out = []
    for m in re.finditer(r"(\d[\d\.,]*)\s*(millones|millón|millon|mil|k|lucas?)?", query.lower()):
        raw = m.group(1).replace(".", "").replace(",", "")
        try:
            val = float(raw)
        except ValueError:
            continue
        suffix = m.group(2) or ""
        if suffix.startswith("k") or suffix.startswith("luca"):
            val *= 1000
        elif suffix.startswith("mil"):
            # "mil", "millón", "millones" (mil solo ya es x1000: "200 mil")
            val *= 1000 if suffix == "mil" else 1_000_000
        out.append(val)
    out.extend(words_to_number(query))
    return out


def keyword_category(query: str) -> str | None:
    # match por palabra completa: "gas" no debe matchear "gaste".
    # Las frases multi-palabra ("obra social") van por substring, es seguro.
    q = query.lower()
    words = set(re.findall(r"[a-záéíóúñ]+", q))
    for cat, kws in KEYWORDS.items():
        for kw in kws:
            if " " in kw:
                if kw in q:
                    return cat
            elif kw in words:
                return cat
    return None


def first_call(result: dict) -> dict | None:
    for key in ("function_calls", "suppressed_calls"):
        calls = result.get(key) or []
        if calls:
            return calls[0]
    return None


def main(tools_file: str):
    try:
        import needle
    except ImportError:
        print("Falta cactus-needle. Corré: uv pip install cactus-needle (ya hay .venv creado)")
        sys.exit(1)

    tools = json.loads((BASE / tools_file).read_text(encoding="utf-8"))
    agent = needle.Needle(tools=tools, stateless=True)
    movimientos: list[dict] = []
    log_mov = (BASE / "movimientos_confirmados.jsonl").open("a", encoding="utf-8")
    log_corr = (BASE / "corrections.jsonl").open("a", encoding="utf-8")
    print("MoneyNeedle probador — escribí un movimiento, /resumen, /salir")
    print("Atajos ante propuesta: [Enter] confirmar | e editar | d descartar\n")

    while True:
        try:
            q = input("vos> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break
        if not q:
            continue
        if q == "/salir":
            break
        if q == "/resumen":
            print(f"  {len(movimientos)} movimientos")
            for mon in sorted({m.get("moneda", "ARS") for m in movimientos}):
                gastos = sum(m["monto"] for m in movimientos if m["tipo"] == "gasto" and m.get("moneda", "ARS") == mon)
                ingresos = sum(m["monto"] for m in movimientos if m["tipo"] == "ingreso" and m.get("moneda", "ARS") == mon)
                print(f"  {mon}: gastos ${gastos:g} | ingresos ${ingresos:g} | balance ${ingresos-gastos:g}")
            continue

        res = None
        call = None
        for _ in range(2):  # reintento ante respuesta vacía transitoria
            res = agent.complete(for_model(q), max_new_tokens=1024)
            call = first_call(res)
            if call is not None:
                break
        if call is None:
            print("  IA: no detecté un movimiento (off-topic o confusión). Probá de nuevo.\n")
            continue
        args = dict(call.get("arguments") or {})
        if call.get("name") == "add_gasto":
            args["tipo"] = "gasto"
        elif call.get("name") == "add_ingreso":
            args["tipo"] = "ingreso"

        # guardrail 1: monto debe estar en el texto
        nums = numbers_in_query(q)
        grounded = any(abs(args.get("monto", -1) - n) < 0.01 for n in nums)
        # guardrail 2: sugerencia de categoría por keywords
        sug = keyword_category(q)
        if sug and args.get("categoria") != sug:
            print(f"  ! categoría modelo={args.get('categoria')} vs regla={sug}")
            args["categoria"] = sug  # la regla manda hasta el finetune
        if not grounded:
            print(f"  ! monto ${args.get('monto')} NO aparece en tu frase (posible alucinación). Revisá con e.")
        moneda = detect_currency(q)
        if moneda != "ARS":
            print(f"  moneda detectada: {moneda}")
        print(f"  IA propone: {args.get('tipo')} ${args.get('monto', '?'):g} {moneda} [{args.get('categoria')}] grounded={'sí' if grounded else 'NO'}")

        acc = input("  [Enter]/e/d> ").strip().lower()
        if acc == "d":
            print("  descartado.\n")
            continue
        final = dict(args)
        if acc == "e":
            for campo in ("tipo", "monto", "categoria"):
                nuevo = input(f"  {campo} ({final.get(campo)})> ").strip()
                if nuevo:
                    final[campo] = float(nuevo) if campo == "monto" else nuevo
        final.setdefault("fecha", datetime.date.today().isoformat())
        final["moneda"] = moneda
        final["frase"] = q
        movimientos.append(final)
        log_mov.write(json.dumps(final, ensure_ascii=False) + "\n")
        log_mov.flush()
        # formato finetune para el futuro
        corr = {
            "query": q,
            "tools": tools,
            "answers": [{"name": call.get("name"), "arguments": {k: final[k] for k in ("tipo", "monto", "categoria") if k in final} if call.get("name") == "add_transaction" else {k: final[k] for k in ("monto", "categoria") if k in final}}],
            "reasoning": f"corrección usuario {datetime.date.today().isoformat()}",
        }
        log_corr.write(json.dumps(corr, ensure_ascii=False) + "\n")
        log_corr.flush()
        print("  guardado ✓\n")

    print("Chau! Tus datos están en movimientos_confirmados.jsonl y corrections.jsonl")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--tools", default="tools.json")
    main(ap.parse_args().tools)
