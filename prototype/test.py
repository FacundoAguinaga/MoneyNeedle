"""Prototipo Fase 0: validar Needle 3 base con tools de finanzas, sin fine-tune.

Uso:
  uv pip install -r requirements.txt
  python test.py --phrase "gasté 5000 en supermercado ayer"
  python test.py --file ../docs/test-phrases.md  # (próximo: batch eval)
"""
import argparse
import json
import pathlib

TOOLS = json.loads(pathlib.Path(__file__).with_name("tools.json").read_text(encoding="utf-8"))


def run(phrase: str):
    try:
        import needle
    except ImportError:
        print("cactus-needle no instalado. Corré: pip install -r requirements.txt")
        print(f"TOOLS que se usarían: {json.dumps(TOOLS, ensure_ascii=False)}")
        print(f"PHRASE: {phrase}")
        return
    agent = needle.Needle(tools=TOOLS)
    result = agent.run(phrase)
    print(json.dumps(result, ensure_ascii=False, indent=2, default=str))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--phrase", default="gasté 5000 en supermercado ayer")
    args = ap.parse_args()
    run(args.phrase)
