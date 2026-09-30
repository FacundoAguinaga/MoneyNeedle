# MoneyNeedle — contexto para continuar el trabajo

Pasale este archivo (o el repo entero) a otra IA para que entienda el proyecto
sin leer todo el historial. Detalle largo en `docs/`.

## Qué es

App de finanzas personal **local-first**: el usuario escribe o dicta movimientos
("gasté 5000 en súper") y **Cactus Needle 3** (modelo tiny on-device, 8-63MB)
los convierte en transacciones estructuradas. 100% offline. Repo greenfield,
dueño: Facundo. Fecha: sep-oct 2026.

## Estado actual (2026-09-30, noche)

- **App Android funcional en hardware**: voz/texto → tuned2 on-device →
  confirmar → SQLite. Instalada (debug) en el teléfono de Facundo.
- Prototype Python: `chat.py`, `eval.py`, `make_dataset.py` (sigue para
  entrenar y medir; el chat Rust se descartó a propósito).
- Modelo: `tuned2.cact` (48% exacto held-out). Corre en el teléfono a
  ~1248 tps prefill / 303 decode, 129MB RAM.
- `main` al día (PRs #2-#5). Ramas de features borradas tras mergear.
- Siguiente paso: construir la app con el stack definido (ver abajo y `docs/stack.md`).

## Stack definido (2026-09-30)

```
Flutter (Dart)  ── solo UI, nada de lógica ──→ flutter_rust_bridge
     ↕ platform channels (STT nativo)             ↓
                                            Rust (moneyneedle-core)
                                              ├─ lógica de negocio
                                              ├─ C API Cactus Needle
                                              └─ SQLite (rusqlite)
```

- **Flutter** para cross-platform (Android + iOS). Detalle en `docs/stack.md`.
- **Rust core** tiene TODA la lógica: parsing, grounding, keywords, moneda,
  validación, y bridge a Cactus Needle via C API.
- **STT**: platform channels al STT nativo de cada OS (fase 1). sherpa-onnx
  via C API en Rust si el nativo no alcanza (fase 2).
- **Persistencia**: SQLite en device (reemplaza los JSONL del prototype).
- **ADRs 9-12** en `docs/decisions.md` documentan el porqué de cada elección.

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
7. Dart es solo UI. Toda la lógica de negocio vive en Rust.

## Deuda técnica conocida

Ver `docs/tech-debt.md` para la lista completa. Los más importantes:
- Bugs en `chat.py`: crash al editar monto, parsing de decimales roto,
  inferencia sin try/except.
- Cero tests unitarios para las funciones puras de Python.
- CI no compila los archivos principales.
- `eval.py` solo mide modelo crudo, no el pipeline con guardrails.

## Archivos que importan

- `prototype/chat.py`, `eval.py`, `make_dataset.py`, `tools.json`
- `prototype/dataset_es.jsonl` (140 semillas etiquetadas — gold)
- `prototype/test_es.jsonl` (50 held-out — NO TOCAR para entrenar)
- `prototype/PROMPT_GENERADOR.md` (prompt para generar más frases con otra IA)
- `docs/baseline.md` (tabla de resultados), `docs/training.md` (bitácora +
  comandos de entreno GPU), `docs/decisions.md`, `docs/idea.md`
- `docs/stack.md` (arquitectura del stack y alternativas evaluadas)
- `docs/tech-debt.md` (bugs conocidos, gaps de testing, deuda técnica)
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
