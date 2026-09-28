"""Eval Fase 0: corre dataset_es.jsonl contra Needle 3 base y mide accuracy.

Uso:
  pip install -r requirements.txt
  python eval.py
  python eval.py --limit 10
"""
import argparse
import json
import pathlib

BASE = pathlib.Path(__file__).parent
TOOLS_DEFAULT = json.loads((BASE / "tools.json").read_text(encoding="utf-8"))

# Mapeo para variante 2-tools: nombre tool -> tipo implicado
TOOL_TIPO = {"add_gasto": "gasto", "add_ingreso": "ingreso", "add_transaction": None}


def normalize_call(result) -> dict | None:
    """Extrae el primer tool_call. Incluye suppressed_calls porque el base
    local no tiene head calibrado y todo cae ahí (ver docs/tools.md)."""
    if result is None:
        return None
    if isinstance(result, list) and result:
        first = result[0]
        if isinstance(first, dict) and "name" in first:
            return first
    if isinstance(result, dict):
        for key in ("function_calls", "suppressed_calls", "calls", "tool_calls", "answers"):
            if isinstance(result.get(key), list) and result[key]:
                return result[key][0]
        if "name" in result and "arguments" in result:
            return result
    return None


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


def main(limit: int, tools_file: str):
    try:
        import needle
    except ImportError:
        print("cactus-needle no instalado. Corré: pip install -r requirements.txt")
        return

    TOOLS = json.loads((BASE / tools_file).read_text(encoding="utf-8"))
    print(f"Tools: {tools_file} ({[t['name'] for t in TOOLS]})")

    rows = [json.loads(l) for l in (BASE / "dataset_es.jsonl").read_text(encoding="utf-8").splitlines() if l.strip()]
    if limit:
        rows = rows[:limit]

    agent = needle.Needle(tools=TOOLS, stateless=True)
    n_tool = n_full = 0
    for r in rows:
        try:
            res = agent.complete(r["query"], max_new_tokens=1024)
        except Exception as e:  # noqa: BLE001
            print(f"FAIL '{r['query']}': {e}")
            continue
        call = normalize_call(res)
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


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--tools", default="tools.json")
    args = ap.parse_args()
    main(args.limit, args.tools)
