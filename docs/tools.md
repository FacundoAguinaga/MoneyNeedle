# Diseño de tools para Needle 3

Needle 3 no es chat: es function-calling. La calidad depende de describir bien los tools.

## Tool principal (MVP)

`add_transaction` — ver `prototype/tools.json`. Un solo tool reduce confusión vs 10 tools.

Reglas (de docs Cactus):
1. Formatos en `description`, restricciones en `schema` (enums, required).
2. `monto` solo número, moneda default ARS.
3. `fecha` formato YYYY-MM-DD; "hoy si no se dice" va en descripción.
4. Incluir ejemplos off-topic con `"answers": []` en el futuro dataset, si no el modelo llama al tool para todo.
5. Frases cortas: el español se fragmenta ~1.7x y la ventana efectiva es ~256 tokens con tools pineados.

## Ruteo por confidence
* `>= 0.8`: auto-proponer carga directa.
* `0.5 - 0.8`: mostrar tarjeta "¿Confirmar?" (default MVP).
* `< 0.5` o `None` (LoRA local no entrena head): pedir aclaración, nunca inventar.
* MVP: siempre confirmar, aunque confidence sea alto.

## Futuro dataset (solo si el base no alcanza)
Formato JSONL, 1 objeto por línea:
```json
{"query": "gasté 5000 en súper", "tools": [...], "answers": [{"name": "add_transaction", "arguments": {"tipo": "gasto", "monto": 5000, "categoria": "supermercado"}}], "reasoning": "'gasté' -> tipo=gasto; '5000' -> monto; 'súper' -> categoria=supermercado"}
```
Comandos:
```bash
needle finetune data.jsonl --epochs 10 --out adapter.safetensors
needle build --lora adapter.safetensors --out tuned.cact
```
Local = LoRA rank16 4-bit, `confidence=None`. Plataforma = full 2-bit con head calibrado.
