# Baseline Needle 3 base (sin fine-tune) — 2026-09-28

Dataset: `prototype/dataset_es.jsonl` (30 frases, 3 off-topic).
Método: `Needle(tools, stateless=True).complete(q, max_new_tokens=1024)`,
se aceptan `function_calls` + `suppressed_calls` (el base local no calibra
confidence y todo cae en suppressed).

## Resultados

| Variante | Tool+tipo | Exacto (tipo+monto+cat) |
|---|---|---|
| 1 tool `add_transaction` base (30 frases) | 73% (22/30) | 27% (8/30) |
| 2 tools `add_gasto` / `add_ingreso` base (30 frases) | 77% (23/30) | 30% (9/30) |
| 1 tool base, tools slim (112 frases) | 62% (70/112) | 21% (24/112) |
| **1 tool FINETUNE 3 epochs, 1500 ej. (112 frases)** | **98% (110/112)** | **75% (84/112)** |

OJO: el 75% es sobre las semillas de entrenamiento (optimista). Falta medir
generalización con frases nuevas no vistas. Errores que quedan: confusión
salud↔servicios (luz/gas→salud), "N lucas" a veces x10 de más
("50 lucas"→100000), supermercado por defecto en ropa/banco.

## Hallazgos

1. **Montos bien** cuando hay dígitos (15000, 200k=200000 OK tras documentar k/lucas en description).
   Mal con números en palabras ("doscientos mil" -> 2000/50000) y a veces alucina
   ("uber 4500" -> 15000, "café 2500" -> 2500000 en variante 2-tools).
2. **Tipo**: el modelo sesga a `gasto`. 2 tools lo mejoran (tool selection > enum grounding,
   como dice la doc de Cactus) pero "aguinaldo"/"me transfirieron" siguen fallando.
3. **Categoría**: casi siempre `supermercado`. Enum de 8 valores en español le queda grande.
4. **Off-topic**: 2/3 bien; a veces alucina llamada con monto inventado (150000/5000).
5. **Truncation**: con `max_new_tokens=512` + descriptions largas hay `token budget exhausted`.
   Usar 1024. Schema chico (sin `moneda`/`fecha`, defaults en core) rinde mejor.
6. **Importante**: usar `complete()`, no `run()` (run intenta ejecutar funciones Python
   y falla con schemas JSON). `stateless=True` entre frases independientes.

## Decisión

El base **no alcanza para auto-carga** (30% exacto), pero **sí como proponente**
con UI de confirmación + guardrails en core:

* Grounding check: el monto debe aparecer en el texto (normalizando k/lucas/puntos).
* Sin dígitos en la query -> rechazar (corta alucinaciones off-topic).
* Categoría con fallback de keywords en core (taxi/uber/bondi/nafta->transporte, etc.)
  hasta que haya datos para finetune.
* MVP siempre confirma, ignora confidence.

Para auto-carga (>90% exacto): finetune LoRA local con 500-1000 ejemplos
`query/tools/answers/reasoning` — la doc dice que grounding necesita miles con
reasoning lines. Cada corrección del usuario ya es un futuro ejemplo.
