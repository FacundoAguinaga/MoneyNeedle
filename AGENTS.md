# AGENTS.md — normas para IAs que trabajan en MoneyNeedle

Leé `CONTEXT.md` primero. Acá van las reglas que salieron de romper cosas.

## Comunicación

- Español rioplatense, voseo, conciso. Nada de superlativos ni emojis.
- Responder con hechos verificados (correr código, no suponer).
- Preguntar antes de: cambiar etiquetas del dataset, entrenar (>30 min GPU),
  pushear a remoto, borrar archivos.

## Entorno (fish + uv, NO estándar)

- Shell del usuario: **fish**. Nada de sintaxis bash en comandos sugeridos.
- No existe `pip`/`pip3`. Python siempre vía `.venv/bin/python` o
  `source .venv/bin/activate.fish`. Instalar con `uv pip install ...`.
- Todo corre desde `prototype/` salvo que se diga lo contrario.

## Datos del usuario — sagrados

- **JAMÁS** borrar ni pisar `movimientos_confirmados.jsonl` ni
  `corrections.jsonl`. Ya se perdieron 2 veces por limpiezas de test.
- Tests propios del agente: usar `CHAT_DATA_DIR=/tmp` (chat.py lo soporta)
  y borrar solo lo de `/tmp`.
- No commitear: `data/` (generado), `*.cact`, `*.safetensors`, `checkpoints/`,
  datos del usuario, `.venv/`. (Ver `.gitignore`.)

## Dataset y evaluación — reglas duras

- `test_es.jsonl` es HELD-OUT: prohibido entrenar con él, copiar sus frases
  a `dataset_es.jsonl`, o "arreglar" el modelo mirándolo. Solo `eval.py --data`.
- `dataset_es.jsonl` es gold etiquetado a mano: cada línea nueva debe tener
  `expected` con monto que aparezca LITERAL en `query` (validar con
  `numbers_in_query` de chat.py).
- Frases ambiguas sin verbo (no se sabe si entra/sale plata) NO se etiquetan
  con default: van a confirmación manual o se completan con verbo.
- Las etiquetas del usuario (Facundo) mandan sobre las del agente.
- Cambios en `tools.json`/`chat.py`/`eval.py`/`make_dataset.py` →
  correr `eval.py` en base y tuneado y reportar `Tool+tipo` y `Exacto`.
- Actualizar `docs/baseline.md` cuando haya números nuevos y
  `docs/training.md` si cambia el procedimiento de entreno.

## GPU (GTX 1650 4GB)

- Entrenar solo con GPU libre (~3.5GB, ver con `nvidia-smi`), sin juegos.
- Flags obligatorios: `XLA_PYTHON_CLIENT_PREALLOCATE=false`,
  `XLA_PYTHON_CLIENT_MEM_FRACTION=.9`, `--batch-size 1`, `--val-split 0`.
- Lanzar desacoplado: `setsid nohup env ... > log 2>&1 < /dev/null &`
  (si no, el timeout mata el proceso).
- Compilación JAX tarda minutos; es normal. Mirar progreso con `tail`.

## Git y flujo de trabajo (profesional)

- **`main` es estable y sagrada**: prohibido commitear o pushear directo a `main`
  para cambios sustanciales, features o refactors.
- **Ramas de trabajo**: crear ramas descriptivas a partir de `main`:
  `feat/<nombre>`, `fix/<nombre>`, `chore/<nombre>`, `docs/<nombre>`.
- **Commits profesionales**:
  - Atómicos y autocontenidos (un cambio lógico por commit).
  - Conventional Commits (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`).
  - Mensajes concisos en español o inglés técnico, explicando el *qué* y el *por qué*
    si no es obvio. Cero commits tipo "wip", "cambios", "fix test".
- **Calidad antes de mergear/PR**:
  - `cargo test` debe compilar y pasar sin errores ni warnings críticos si se tocó `core/`.
  - `.venv/bin/python -m unittest` debe pasar si se tocó `prototype/`.
  - Prohibido dejar archivos temporales, dumps de debug o archivos sin trackear no deseados.
- **Siempre preguntar al usuario antes de pushear a remoto o mergear a `main`**.

## Código

- Prototype primero: validar en Python antes de portar a `core/` (Rust).
- Lógica pura de `prototype/` vive en `mn_parse.py` y lleva tests en
  `test_mn_parse.py` (`python -m unittest`). Correrlos antes de commitear
  si se toca el prototype. `cargo test` debe pasar si se toca `core/`.
- No crear archivos innecesarios; preferir editar los existentes.

