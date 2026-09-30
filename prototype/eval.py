"""Eval: corre un dataset JSONL contra Needle 3 y mide accuracy.

Uso:
  uv pip install -r requirements.txt
  python eval.py
  python eval.py --limit 10
"""
import argparse
import json
import pathlib

from mn_parse import extract_call, for_model, keyword_category, numbers_in_query

BASE = pathlib.Path(__file__).parent
TOOLS_DEFAULT = json.loads((BASE / "tools.json").read_text(encoding="utf-8"))

# Mapeo para variante 2-tools: nombre tool -> tipo implicado
TOOL_TIPO = {"add_gasto": "gasto", "add_ingreso": "ingreso", "add_transaction": None}


def normalize_call(result) -> dict | None:
    return extract_call(result)


def apply_guardrails(query: str, call: dict | None) -> tuple[dict | None, bool]:
    """Replica el pipeline real: for_model + grounding + keywords.

    Devuelve (call_post_guardrails, grounded). Si el monto no está en el
    texto, se descarta la llamada (como haría el usuario con 'd').
    """
    if call is None:
        return None, False
    args = dict(call.get("arguments") or {})
    if call.get("name") == "add_gasto":
        args["tipo"] = "gasto"
    elif call.get("name") == "add_ingreso":
        args["tipo"] = "ingreso"
    grounded = any(abs(args.get("monto", -1) - n) < 0.01 for n in numbers_in_query(query))
    if not grounded:
        return None, False
    sug = keyword_category(query)
    if sug:
        args["categoria"] = sug
    return {"name": call.get("name"), "arguments": args}, True


def score(expected: dict, call: dict | None) -> tuple[bool, bool, str]:
    if expected.get("tipo") is None:
        # off-topic: debe dar vacío
        ok = call is None
        return (ok, ok, "off-topic ok" if ok else f"debió ser vacío, dio {call}")
    if call is None:
        return (False, False, "no hubo llamada")
    args = call.get("arguments", {}) if isinstance(call, dict) else {}
    name = call.get("name")
    if name in TOOL_TIPO and TOOL_TIPO[name] is not None:
        args = {**args, "tipo": TOOL_TIPO[name]}  # tipo implicado por el tool
    tool_ok = name in ("add_transaction", "add_gasto", "add_ingreso")
    tipo_ok = args.get("tipo") == expected.get("tipo")
    monto_ok = args.get("monto") == expected.get("monto")
    cat_ok = args.get("categoria") == expected.get("categoria")
    detail = f"tipo:{args.get('tipo')} monto:{args.get('monto')} cat:{args.get('categoria')}"
    return (tool_ok and tipo_ok, tool_ok and tipo_ok and monto_ok and cat_ok, detail)


def main(limit: int = 0, tools_file: str = "tools.json", weights: str | None = None,
         data_file: str = "dataset_es.jsonl", guardrails: bool = False):
    try:
        import needle
    except ImportError:
        print("cactus-needle no instalado. Corré: uv pip install -r requirements.txt")
        return

    TOOLS = json.loads((BASE / tools_file).read_text(encoding="utf-8"))
    print(f"Tools: {tools_file} | weights: {weights or 'base'} | guardrails: {guardrails}")

    rows = [json.loads(l) for l in (BASE / data_file).read_text(encoding="utf-8").splitlines() if l.strip()]
    if limit:
        rows = rows[:limit]

    agent = needle.Needle(tools=TOOLS, stateless=True, **({"weights": weights} if weights else {}))
    n_tool = n_full = 0
    for r in rows:
        try:
            res = agent.complete(for_model(r["query"]) if guardrails else r["query"],
                                 max_new_tokens=1024)
        except Exception as e:  # noqa: BLE001
            print(f"FAIL '{r['query']}': {e}")
            continue
        call = normalize_call(res)
        if guardrails:
            call, _ = apply_guardrails(r["query"], call)
        tool_ok, full_ok, detail = score(r["expected"], call)
        n_tool += tool_ok
        n_full += full_ok
        mark = "OK " if full_ok else ("PART" if tool_ok else "FAIL")
        args = (call.get("arguments", {}) if isinstance(call, dict) else {})
        print(f"[{mark}] '{r['query']}' -> {detail} | args={json.dumps(args, ensure_ascii=False)}")

    n = len(rows)
    print(f"\nTool+tipo: {n_tool}/{n} = {n_tool/n:.0%}")
    print(f"Exacto (tipo+monto+cat): {n_full}/{n} = {n_full/n:.0%}")
    if n_full / n >= 0.9:
        print("Base alcanza. No hace falta finetune todavía.")
    elif n_tool / n >= 0.8:
        print("Tool ok pero grounding flojo -> candidato a finetune con 500-1000 ejemplos + reasoning.")
    else:
        print("Hay que rediseñar tools/descripciones antes de pensar en finetune.")


def cli():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--tools", default="tools.json")
    ap.add_argument("--weights", default=None, help="ruta a tuned.cact")
    ap.add_argument("--data", default="dataset_es.jsonl", help="archivo de frases a evaluar")
    ap.add_argument("--with-guardrails", action="store_true",
                    help="mide el pipeline real (for_model + grounding + keywords)")
    args = ap.parse_args()
    main(args.limit, args.tools, args.weights, args.data, args.with_guardrails)


if __name__ == "__main__":
    cli()
