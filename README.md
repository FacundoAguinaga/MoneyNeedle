# MoneyNeedle 🌵💰

App de finanzas personal **local-first** con IA on-device.

El usuario **escribe o habla** sus movimientos ("gasté 5000 en súper ayer") y **Cactus Needle 3** los convierte en transacciones estructuradas, 100% offline.

## Estado
Fase 0 — scaffolding. Sin fine-tune todavía: primero se valida el modelo base con buenos tools.

## Arquitectura

```
[Mic Flutter] -> [STT local sherpa-onnx/whisper.cpp] -> texto
  -> [Needle 3 .cact + tools.json] -> tool_call JSON
  -> [core Rust: valida + SQLite] -> [Flutter: confirmar/editar]
  -> [corrección guardada como futuro data.jsonl para finetune]
```

* `app/` — UI Flutter (iOS/Android/Desktop, una codebase).
* `core/` — lógica compartida en Rust (modelos, validación, DB, bridge a Needle/STT).
* `prototype/` — validación rápida en Python con `cactus-needle` antes de tocar el móvil.
* `assets/models/` — `.cact` base + futuro `tuned.cact` (no se versionan pesos).
* `docs/` — idea, diseño de tools, frases de test en español.

## Quickstart

```bash
# 1. Prototipo Python (validar Needle 3 sin móvil)
cd prototype
pip install -r requirements.txt
python test.py --phrase "gasté 5000 en supermercado ayer"

# 2. Core Rust
cd core
cargo test

# 3. App Flutter (requiere Flutter SDK >= 3.22)
cd app
flutter pub get
flutter run
```

## Decisiones
* Móvil local-first, STT 100% local, privacidad total.
* MVP **sin fine-tune**: se mide el base primero (>90% tool+args exactos). Si falla grounding -> finetune LoRA local.
* Stack alto rendimiento multiplataforma: Rust + Flutter.

Ver `docs/idea.md` y `docs/tools.md`.
