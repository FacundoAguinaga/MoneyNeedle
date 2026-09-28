"""Genera data.jsonl para finetune local a partir de tus casos reales.

Fuentes (en orden de calidad):
  1. corrections.jsonl   — tus confirmaciones/ediciones del chat (peso x3)
  2. dataset_es.jsonl    — set manual de 30 frases

Estrategia offline (sin API key): por cada semilla se generan variantes
cambiando el monto por otros realistas. El grounding queda garantizado
porque el número nuevo se escribe en la frase y en la respuesta.

Uso:
  .venv/bin/python make_dataset.py --num 800
  .venv/bin/python make_dataset.py --num 800 --out data.jsonl --seed 42

Después:
  uv pip install "cactus-needle[train]"
  .venv/bin/needle finetune data/data.jsonl --epochs 10 --out data/adapter.safetensors
"""
import argparse
import json
import pathlib
import random
import re

BASE = pathlib.Path(__file__).parent
DATA = BASE / "data"

NUM_RE = re.compile(r"(\d[\d\.,]*)\s*(millones|millón|millon|mil|k|lucas?)?", re.IGNORECASE)

OFF_TOPIC = [
    "hola qué hora es", "contame un chiste", "cómo está el clima mañana",
    "qué día es hoy", "llamame un taxi", "poné música",
    "cuánto es 2 más 2", "gracias", "chau",
]

# montos realistas redondos para variar
AMOUNTS = [500, 800, 1000, 1500, 2500, 3000, 5000, 6500, 8000, 9500, 12000,
           15000, 18000, 25000, 30000, 45000, 80000, 150000, 200000, 300000]


def load_seeds() -> tuple[list[dict], list[str]]:
    seeds, off = [], []
    d = BASE / "dataset_es.jsonl"
    if d.exists():
        for line in d.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            r = json.loads(line)
            exp = r["expected"]
            if exp.get("tipo") is None:
                off.append(r["query"])
            else:
                seeds.append({"query": r["query"], **exp, "weight": 1})
    c = BASE / "corrections.jsonl"
    if c.exists():
        for line in c.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            r = json.loads(line)
            a = (r.get("answers") or [{}])[0]
            args = a.get("arguments", {})
            name = a.get("name", "add_transaction")
            tipo = args.get("tipo") or {"add_gasto": "gasto", "add_ingreso": "ingreso"}.get(name)
            if tipo and args.get("monto"):
                seeds.append({"query": r["query"], "tipo": tipo,
                              "monto": args["monto"],
                              "categoria": args.get("categoria", "otros"),
                              "weight": 3})  # tus casos valen triple
    return seeds, off


def vary_amount(seed: dict, rng: random.Random) -> dict | None:
    m = NUM_RE.search(seed["query"])
    if not m:
        return None
    suffix = (m.group(2) or "").lower()
    if suffix.startswith("k"):
        new = rng.randint(2, 900)
        monto, new_txt = float(new * 1000), f"{new}k"
    elif suffix.startswith("luca") or suffix == "mil":
        new = rng.randint(1, 500)
        monto, new_txt = float(new * 1000), f"{new} {m.group(2)}"
    elif suffix.startswith("mil"):
        new = rng.randint(1, 50)
        monto, new_txt = float(new * 1_000_000), f"{new} millones"
    else:
        new = rng.choice(AMOUNTS)
        monto, new_txt = float(new), f"{new}"
    query = seed["query"][:m.start()] + new_txt + seed["query"][m.end():]
    return {"query": query, "tipo": seed["tipo"], "monto": monto, "categoria": seed["categoria"]}


def reasoning_for(ex: dict) -> str:
    return (f"'{ex['query']}' -> tipo={ex['tipo']}; "
            f"monto={ex['monto']:g} presente en la frase; categoria={ex['categoria']}")


def main(num: int, out: str, seed: int):
    rng = random.Random(seed)
    seeds, off = load_seeds()
    if not seeds:
        print("Sin semillas: cargá movimientos con chat.py primero.")
        return
    tools = json.loads((BASE / "tools.json").read_text(encoding="utf-8"))

    pool: list[dict] = []
    for s in seeds:
        pool.extend([s] * s.get("weight", 1))  # correcciones pesan más
    n_off = max(1, num // 8)
    n_pos = num - n_off
    rows = []
    for _ in range(n_pos):
        s = rng.choice(pool)
        v = vary_amount(s, rng) or s
        rows.append({
            "query": v["query"], "tools": tools,
            "answers": [{"name": "add_transaction", "arguments": {
                "tipo": v["tipo"], "monto": v["monto"], "categoria": v["categoria"]}}],
            "reasoning": reasoning_for(v),
        })
    off_all = (off + OFF_TOPIC) or OFF_TOPIC
    for _ in range(n_off):
        rows.append({"query": rng.choice(off_all), "tools": tools,
                     "answers": [],
                     "reasoning": "sin herramienta aplicable, respuesta vacía"})
    rng.shuffle(rows)

    DATA.mkdir(exist_ok=True)
    path = DATA / out
    path.write_text("\n".join(json.dumps(r, ensure_ascii=False) for r in rows), encoding="utf-8")
    print(f"Semillas: {len(seeds)} ({sum(1 for s in seeds if s.get('weight',1)>1)} tuyas) + {len(off_all)} off-topic")
    print(f"Escribí {len(rows)} ejemplos -> {path} ({n_pos} positivos, {n_off} vacíos)")
    print("Siguiente: uv pip install \"cactus-needle[train]\" && .venv/bin/needle finetune data/data.jsonl --epochs 10 --out data/adapter.safetensors")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--num", type=int, default=800)
    ap.add_argument("--out", default="data.jsonl")
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args()
    main(a.num, a.out, a.seed)
