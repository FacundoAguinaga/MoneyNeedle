"""Probador interactivo MoneyNeedle.

Escribís movimientos como le hablarías a la app y Needle 3 propone la carga.
Vos confirmás / editás / descartás. Todo queda guardado:
  - movimientos_confirmados.jsonl  (tu registro)
  - corrections.jsonl              (futuro data.jsonl para finetune)

Uso:
  .venv/bin/python chat.py [--tools tools.json] [--weights data/tuned2.cact]

Comandos dentro del chat: /resumen /salir
"""
import argparse
import datetime
import json
import os
import pathlib
import sys

from mn_parse import (detect_currency, extract_call, for_model,
                      keyword_category, numbers_in_query, parse_number_token)

BASE = pathlib.Path(__file__).parent
# Directorio de datos del usuario (correcciones y movimientos).
# Los tests usan CHAT_DATA_DIR=/tmp para no tocar datos reales.
DATA_DIR = pathlib.Path(os.environ.get("CHAT_DATA_DIR", BASE))


def edit_field(final: dict, campo: str, nuevo: str) -> None:
    """Aplica una edición del usuario sin matar el REPL ante input inválido."""
    if not nuevo:
        return
    if campo == "monto":
        try:
            final[campo] = parse_number_token(nuevo)
        except ValueError:
            print(f"  ! '{nuevo}' no es un número, queda {final.get(campo)}")
    elif campo == "tipo":
        if nuevo in ("gasto", "ingreso"):
            final[campo] = nuevo
        else:
            print("  ! tipo debe ser gasto o ingreso")
    else:
        final[campo] = nuevo


def main(tools_file: str = "tools.json", weights: str | None = None):
    try:
        import needle
    except ImportError:
        print("Falta cactus-needle. Corré: uv pip install cactus-needle (ya hay .venv creado)")
        sys.exit(1)

    tools = json.loads((BASE / tools_file).read_text(encoding="utf-8"))
    agent = needle.Needle(tools=tools, stateless=True, **({"weights": weights} if weights else {}))
    movimientos: list[dict] = []
    print("MoneyNeedle probador — escribí un movimiento, /resumen, /salir")
    print("Atajos ante propuesta: [Enter] confirmar | e editar | d descartar\n")

    with (DATA_DIR / "movimientos_confirmados.jsonl").open("a", encoding="utf-8") as log_mov, \
         (DATA_DIR / "corrections.jsonl").open("a", encoding="utf-8") as log_corr:
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

            call = None
            for _ in range(2):  # reintento ante respuesta vacía transitoria
                try:
                    call = extract_call(agent.complete(for_model(q), max_new_tokens=1024))
                except Exception as e:  # noqa: BLE001 - el REPL no debe morir
                    print(f"  ! falló la inferencia ({e}), reintento...")
                    continue
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
            monto_txt = f"{args['monto']:g}" if isinstance(args.get("monto"), (int, float)) else "?"
            print(f"  IA propone: {args.get('tipo')} ${monto_txt} {moneda} [{args.get('categoria')}] grounded={'sí' if grounded else 'NO'}")

            acc = input("  [Enter]/e/d> ").strip().lower()
            if acc == "d":
                print("  descartado.\n")
                continue
            final = dict(args)
            if acc == "e":
                for campo in ("tipo", "monto", "categoria"):
                    edit_field(final, campo, input(f"  {campo} ({final.get(campo)})> ").strip())
            final.setdefault("fecha", datetime.date.today().isoformat())
            final["moneda"] = moneda
            final["frase"] = q
            movimientos.append(final)
            log_mov.write(json.dumps(final, ensure_ascii=False) + "\n")
            # formato finetune para el futuro
            corr = {
                "query": q,
                "tools": tools,
                "answers": [{"name": call.get("name"), "arguments": {k: final[k] for k in ("tipo", "monto", "categoria") if k in final} if call.get("name") == "add_transaction" else {k: final[k] for k in ("monto", "categoria") if k in final}}],
                "reasoning": f"corrección usuario {datetime.date.today().isoformat()}",
            }
            log_corr.write(json.dumps(corr, ensure_ascii=False) + "\n")
            print("  guardado ✓\n")

    print("Chau! Tus datos están en movimientos_confirmados.jsonl y corrections.jsonl")


def cli():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tools", default="tools.json")
    ap.add_argument("--weights", default=None, help="ruta a tuned.cact")
    args = ap.parse_args()
    main(args.tools, args.weights)


if __name__ == "__main__":
    cli()
