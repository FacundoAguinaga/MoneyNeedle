# Deuda técnica y bugs conocidos

> Estado 2026-09-30: bugs 1-5, tests, CI, guardrails, módulo compartido y
> decimales RESUELTOS (commit "fix: review otra IA"). Queda pendiente:
> lockfile, variación sintáctica profunda, property-based tests, logging.

Hallazgos de la review de código (2026-09-30). Referencia para cualquier IA
o desarrollador que retome el proyecto.

## Bugs (arreglar antes de portar a app)

### 1. Crash al editar monto — `chat.py` L230

```python
final[campo] = float(nuevo) if campo == "monto" else nuevo
```

`float()` sin `try/except`. Si el usuario tipea texto no numérico, el REPL muere.
RESUELTO: `edit_field()` en chat.py valida y no mata el REPL.

### 2. Parsing de decimales roto — `chat.py` L118

```python
raw = m.group(1).replace(".", "").replace(",", "")
```

Elimina todos los puntos y comas. "10.50" se parsea como 1050.
En Argentina el punto es separador de miles ("35.000" = 35000), así que para
montos locales en pesos funciona. Pero rompe montos con centavos y monedas
extranjeras. Bomba de tiempo.

RESUELTO: `parse_number_token()` en `mn_parse.py` ("35.000"->35000, "10.50"->10.5, "1.200,50"->1200.5). Con tests.

### 3. Inferencia sin protección — `chat.py` L193

RESUELTO: chat.py envuelve `complete()` en try/except con reintento.

### 4. File handles sin cerrar — `chat.py` L167-168

RESUELTO: handles dentro de `with` (se cierran siempre).

### 5. Enum `Transferencia` en Rust inconsistente — `core/src/lib.rs` L11

ADR 2 dice "transferencia no existe como tipo". Pero `TipoMovimiento` tiene
la variante `Transferencia`. RESUELTO: variante eliminada, `cargo test` pasa.

## Testing insuficiente

### Funciones sin tests (candidatas perfectas: puras, sin side effects)

| Función | Archivo | Qué testear |
|---|---|---|
| `words_to_number` | `chat.py` L76 | "cinco mil" → 5000, "doscientos mil" → 200000, edge cases |
| `numbers_in_query` | `chat.py` L114 | "12k" → 12000, "5 lucas" → 5000, "35.000" → 35000, decimales |
| `keyword_category` | `chat.py` L134 | "taxi" → transporte, "gas" no matchea "gaste", "obra social" → salud |
| `detect_currency` | `chat.py` L43 | "usd", "dólares", sin moneda → ARS |
| `for_model` | `chat.py` L51 | Saca "usd"/"dólares" del texto sin romper la frase |

### CI incompleto

RESUELTO: CI compila los 6 archivos y corre `unittest` (19 tests, sin GPU).

## Evaluación parcial

`eval.py` mide el modelo crudo (sin guardrails). No existe una métrica del
pipeline completo (modelo + `for_model` + grounding + keywords). En producción
lo que importa es la exactitud del sistema entero.

RESUELTO: flag `--with-guardrails` agregado.

## `make_dataset.py` — limitaciones del sintético

1. `vary_amount()` solo varía números en dígitos. Frases con números en
   palabras ("cinco mil") se copian idénticas → contribuye al overfitting.
2. L83: `elif suffix.startswith("mil")` debería ser `suffix.startswith("millo")`
   para claridad (ya atrapó `suffix == "mil"` antes).
3. Solo varía montos, no estructura sintáctica. Esto explica el techo de ~48%.

## Duplicación de lógica

`first_call()` (chat.py) y `normalize_call()` (eval.py) hacen lo mismo con
implementaciones distintas. `eval.py` revisa más keys (`calls`, `tool_calls`,
`answers`). RESUELTO: `prototype/mn_parse.py` (KEYWORDS, CURRENCIES, parsing, `extract_call`). chat.py, eval.py y make_dataset.py lo usan.

## Gestión de dependencias informal

- RESUELTO parcial: `pyproject.toml` mínimo + entry points + comentarios uv. PENDIENTE: lockfile.
- Comentarios en `eval.py` y `test.py` dicen "pip install" pero el proyecto
  usa exclusivamente `uv`.
