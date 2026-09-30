# MoneyNeedle — contexto para continuar el trabajo

Pasale este archivo (o el repo entero) a otra IA para que entienda el proyecto
sin leer todo el historial. Detalle largo en `docs/`.

## Qué es

App de finanzas personal **local-first**: el usuario escribe o dicta movimientos
("gasté 5000 en súper") y **Cactus Needle 3** (modelo tiny on-device, 8-63MB)
los convierte en transacciones estructuradas. 100% offline. Repo greenfield,
dueño: Facundo. Fecha: sep-oct 2026.

## Estado actual (2026-09-29)

- Prototype Python funcional: `prototype/chat.py` (probador interactivo),
  `prototype/eval.py` (mide accuracy), `prototype/make_dataset.py` (genera data).
- Modelo actual: `prototype/data/tuned2.cact` (NO versionado, 63MB) —
  **48% exacto en 50 frases nunca vistas** (base: 16%).
- Probarlo: `cd prototype && .venv/bin/python chat.py --weights data/tuned2.cact`
- La app móvil (Flutter + core Rust) está scaffoldeada (`app/`, `core/`) pero
  vacía: el trabajo hasta ahora fue validar la IA.
- Siguiente paso sugerido: construir la app que use `tuned2.cact` (ver `docs/idea.md`).

## Arquitectura del prototype

```
frase → (sacar moneda) → Needle 3 complete() → tool_call add_transaction
  → guardrails (grounding de monto, keywords de categoría, retry)
  → usuario confirma/edita/descarta → SQLite futuro / hoy JSONL
```

- **Un solo tool** `add_transaction{tipo,monto,categoria}` (`tools.json`).
  Moneda y fecha las pone la app, nunca el modelo.
- Se usa `complete()`, no `run()`; se lee `function_calls` + `suppressed_calls`;
  `stateless=True`; `max_new_tokens=1024`.
- Guardrails en `chat.py`: `numbers_in_query` (k/lucas/mil/palabras),
  `keyword_category` (match por palabra completa), `detect_currency`,
  `for_model` (saca la moneda del prompt porque "usd"→alucina 200000).

## Decisiones clave (detalle en `docs/decisions.md`)

1. Un tool, sin tipo `transferencia` (va como gasto/otros).
2. MVP siempre confirma; se ignora `confidence` (None en LoRA local).
3. Español rioplatense, voseo.
4. Frases ambiguas sin verbo → confirmación manual, nunca default fijo.
5. `test_es.jsonl` es HELD-OUT sagrado: jamás entrenar con él ni copiar sus
   frases a `dataset_es.jsonl` (verificado: 0 duplicados).
6. Dataset sintético llegó a su techo (loss→0.000 = memoriza). Lo próximo es
   dato REAL de `corrections.jsonl` (hoy casi vacío).

## Archivos que importan

- `prototype/chat.py`, `eval.py`, `make_dataset.py`, `tools.json`
- `prototype/dataset_es.jsonl` (140 semillas etiquetadas — gold)
- `prototype/test_es.jsonl` (50 held-out — NO TOCAR para entrenar)
- `prototype/PROMPT_GENERADOR.md` (prompt para generar más frases con otra IA)
- `docs/baseline.md` (tabla de resultados), `docs/training.md` (bitácora +
  comandos de entreno GPU), `docs/decisions.md`, `docs/idea.md`
- `core/` (Rust, solo modelos+tests), `app/` (Flutter scaffold)

## Comandos

```fish
cd prototype
.venv/bin/python chat.py --weights data/tuned2.cact   # probar (tuned.cact = v1 vieja)
.venv/bin/python eval.py --data test_es.jsonl --weights data/tuned2.cact
.venv/bin/python make_dataset.py --num 2000 --out data2.jsonl
tail -n 5 data/train_gpu2.log                        # ver entrenamiento
```

Entrenar (GTX 1650 4GB, cerrar juegos, ver `docs/training.md` por OOMs):
```fish
setsid nohup env NEEDLE_TELEMETRY=0 XLA_PYTHON_CLIENT_PREALLOCATE=false XLA_PYTHON_CLIENT_MEM_FRACTION=.9 \
 .venv/bin/needle finetune data/data2.jsonl --epochs 3 --batch-size 1 --val-split 0 \
 --out data/adapter2.safetensors > data/train_gpu2.log 2>&1 < /dev/null &
NEEDLE_TELEMETRY=0 .venv/bin/needle build --lora data/adapter2.safetensors --out data/tuned2.cact
```
