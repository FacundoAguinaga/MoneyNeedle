# Stack y arquitectura — MoneyNeedle

Referencia para entender por qué se eligió cada pieza. Fecha: 2026-09-30.

## Diagrama general

```
┌─────────────────────────────────────────────────┐
│  Flutter (Dart) — UI                            │
│  Jetpack-style: campo de texto, mic, tarjeta    │
│  de confirmación, lista de movimientos, balance  │
├─────────────────────────────────────────────────┤
│  flutter_rust_bridge (bindings auto-generados)  │
├─────────────────────────────────────────────────┤
│  Rust — moneyneedle-core (cdylib + rlib)        │
│  Lógica de negocio pura:                        │
│  - parsing de montos (k, lucas, mil, palabras)  │
│  - detección de moneda                          │
│  - keyword fallback de categoría                │
│  - grounding check                              │
│  - validación de Transaction                    │
│  - persistencia (rusqlite/drift → SQLite)       │
│  - bridge a Cactus Needle C API                 │
│  - bridge a STT (sherpa-onnx o nativo)          │
├─────────────────────────────────────────────────┤
│  C APIs nativas                                 │
│  - Cactus Needle 3 (.cact, ~63MB)              │
│  - STT (platform channel → nativo, o sherpa)    │
└─────────────────────────────────────────────────┘
│           SQLite (local, en device)             │
└─────────────────────────────────────────────────┘
```

## Decisiones de stack

### App: Flutter (Dart)

**Por qué Flutter y no otra cosa:**

Se evaluaron 5 opciones:

| Opción | Veredicto | Razón |
|---|---|---|
| **Flutter** | ✅ Elegido | Cross-platform real (Android + iOS). `flutter_rust_bridge` es maduro y genera bindings Dart↔Rust automáticamente. UI declarativa, hot reload. |
| Kotlin nativo (Android) | Descartado | FFI más simple (JNI directo), pero no cumple el requisito de multiplataforma. Sería ideal si solo se apuntara a Android. |
| KMP + Compose Multiplatform | Descartado | Cross-platform viable pero FFI a Rust/C hay que escribirlo a mano por plataforma (JNI Android, cinterop iOS). Más glue manual que Flutter. |
| React Native | Descartado | FFI es un infierno. Performance insuficiente para inferencia on-device. No apto para este caso. |
| Swift (iOS only) | Descartado | Swift→C es trivial, pero Argentina es ~85% Android. Arrancar por iOS no tiene sentido comercial. |

**Qué hace Flutter en este proyecto (y qué NO):**

Flutter es **solo la capa de presentación**. NO tiene lógica de negocio.

- ✅ UI: campo de texto, botón de mic, tarjeta de confirmación, lista, balance
- ✅ Platform channels para STT nativo (Android `SpeechRecognizer`, iOS `SFSpeechRecognizer`)
- ✅ Llamadas a `moneyneedle-core` via `flutter_rust_bridge`
- ❌ NO parsea montos, NO detecta moneda, NO clasifica categorías, NO llama a Needle directamente

### Core: Rust (moneyneedle-core)

**Por qué Rust:**

- Compila a `cdylib` (.so Android, .dylib iOS) consumible desde Flutter via `flutter_rust_bridge`.
- Performance nativa para parsing y validación.
- Memory safety sin GC, ideal para mobile.
- Cero dependencias externas hoy; se agregarán `rusqlite` (persistencia) y bindings C a Needle/STT.
- Si algún día se agrega backend, el mismo crate se reutiliza.

**Qué tiene hoy (`core/src/lib.rs`):**

- `Transaction` struct + `validate()`
- `TipoMovimiento` enum (nota: tiene `Transferencia` que debería sacarse, ver ADR 9)
- `Routing` enum + `route_by_confidence()` (MVP siempre confirma)
- 4 tests unitarios

**Qué debe tener antes de conectar con Flutter:**

- Toda la lógica de `chat.py` portada: `numbers_in_query`, `words_to_number`,
  `keyword_category`, `detect_currency`, `for_model`
- Bridge a la C API de Cactus Needle 3 (cargar `.cact`, llamar `complete()`)
- Persistencia SQLite (reemplaza los JSONL)

### Modelo: Cactus Needle 3

- Modelo tiny on-device orientado a function calling.
- Peso compilado: `tuned2.cact` (~63MB), empaquetado como asset del APK/IPA.
- Se usa `complete()` (no `run()`), con `stateless=True`, `max_new_tokens=1024`.
- Fine-tune via CLI de Cactus: `needle finetune` (JAX/Flax) → adapter LoRA → `needle build` → `.cact`.
- Entrenamiento en GTX 1650 4GB (ver `docs/training.md`).

### STT: estrategia en dos fases

1. **MVP**: platform channels a los STT nativos de cada OS.
   - Android: `SpeechRecognizer` con modelos offline descargables.
   - iOS: `SFSpeechRecognizer` con reconocimiento on-device.
   - Ventaja: cero dependencias extra, funciona offline.
2. **Post-MVP** (si el nativo no es suficiente): `sherpa-onnx` via C API
   llamada desde Rust, misma cadena FFI que Needle.

### Persistencia: SQLite

- Hoy: archivos JSONL append-only (`movimientos_confirmados.jsonl`, `corrections.jsonl`).
- Destino: SQLite en device, accedido desde Rust (`rusqlite`) o desde Dart (`drift`).
  - Opción A: SQLite en Rust, expuesto a Dart via `flutter_rust_bridge`.
  - Opción B: SQLite en Dart via `drift`, Rust no toca DB.
  - Decisión pendiente: depende de si el core Rust necesita consultar datos
    (ej. para /resumen, o para alimentar reentrenamiento).

### CI: GitHub Actions

- `cargo test` para el core Rust.
- `py_compile` para los scripts Python (pendiente: agregar tests unitarios de
  funciones puras y compilar los 3 archivos principales).

## Cadena de FFI (lo más importante de entender)

```
Flutter (Dart)
    │
    ├── flutter_rust_bridge ──→ Rust (moneyneedle-core)
    │                              │
    │                              ├── unsafe { } ──→ C API Cactus Needle
    │                              │                    (cargar .cact, complete())
    │                              │
    │                              └── unsafe { } ──→ C API sherpa-onnx (fase 2)
    │
    └── Platform Channels ──→ Android SpeechRecognizer / iOS SFSpeechRecognizer
                                (STT nativo, fase 1)
```

La regla: **Dart nunca llama a C directamente**. Todo pasa por Rust.
Excepción: STT nativo vía platform channels (es API de plataforma, no C propio).

## Dependencias clave

| Capa | Dependencia | Versión / Estado |
|---|---|---|
| Python (prototype) | `cactus-needle` | ≥3.0.0, via `uv` |
| Rust | `std` only (hoy) | edition 2021 |
| Rust (futuro) | `rusqlite`, bindings Cactus C | pendiente |
| Flutter | `flutter_rust_bridge` | pendiente agregar |
| Flutter | `drift` (SQLite) | pendiente agregar |
| Flutter | `cupertino_icons` | ^1.0.6 (ya en pubspec) |
