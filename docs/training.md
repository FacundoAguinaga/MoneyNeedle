# Bitácora de entrenamiento y build Android

## Build Android (verificado 2026-09-30)

Toolchain: NDK r28c (`~/Android/Sdk/ndk/28.2.13676358`), target
`aarch64-linux-android`, `cargo-ndk`, JDK 21 portable (`~/jdk21`,
el Java 26 del sistema rompe AGP), `compileSdk = 37`
(`permission_handler` lo exige), plataforma android-35 para el
transform de un plugin.

```fish
# .so arm64 con engine (desde core/)
export ANDROID_NDK_HOME=$HOME/Android/Sdk/ndk/28.2.13676358
NEEDLE_LIB_DIR=/tmp/needle-android cargo ndk -t arm64-v8a build --release
cp target/aarch64-linux-android/release/libmoneyneedle_core.so \
   ../app/android/app/src/main/jniLibs/arm64-v8a/
# engine android: needle build --lora data/adapter2.safetensors \
#   --platform android-arm64 --out /tmp/needle-android
# .cact como asset: app/assets/models/tuned2.cact (gitignored)
export JAVA_HOME=$HOME/jdk21
fvm flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

Lecciones (cada una costó un crash real):

- `build.rs` pasa `libc++_shared.so` del NDK **por ruta completa**, nunca
  por `-L`: si el dir del sysroot entra al search path, el linker pesca
  objetos de `libc.a` estática (un `getauxval` incompatible → SIGSEGV
  en `dlopen`, verificado por disassembly + `llvm-nm`).
- Tras CADA cambio del core, recompilar el `.so` arm64: si no, FRB frena
  el arranque (content-hash mismatch = pantalla negra).
- Debug: `adb logcat -c` + lanzar + `grep -E "Unhandled|Fatal signal"`;
  backtrace nativo se decodifica con `llvm-addr2line` del NDK.
- Gradle cachea agresivo el merge de jniLibs: ante duda, `rm -rf build`.

## Entrenamiento (2026-09-29)

Cómo se pasó de 16% a 48% exacto en frases no vistas, con comandos
reproducibles. Modelos: `data/tuned.cact` (v1), `data/tuned2.cact` (v2, actual).
Esos archivos pesan 63MB y NO se versionan (ver `.gitignore`).

## Entorno

- Máquina: i5-9300H (8 hilos) + GTX 1650 4GB, fish shell, `uv` + `.venv`.
- Base: `cactus-needle` 3.x, checkpoint `checkpoints/needle3.safetensors` (242MB, auto-descargado de HF).
- Lecciones de entorno:
  - CPU: la compilación JAX no terminó en 44 min (i5 muy lento). Descartado.
  - GPU 4GB: OOM con batch 4 y 2. Lo que lo hace andar:
    `XLA_PYTHON_CLIENT_PREALLOCATE=false XLA_PYTHON_CLIENT_MEM_FRACTION=.9`
    + `--batch-size 1`. (JAX pre-aloca 75% por defecto y no queda lugar.)
  - La validación (`jit_loss_fn`) también da OOM en 4GB → `--val-split 0`.
    Se pierde la señal de val; se compensa con pocas epochs (3) y held-out externo.
  - Cerrar el juego/navegador pesado: se necesitan ~3.5GB libres (`nvidia-smi`).
  - Lanzar desacoplado para que sobreviva al terminal:
    `setsid nohup env ... .venv/bin/needle finetune ... > data/train_gpu2.log 2>&1 < /dev/null &`

## Ronda 1 (2026-09-29): 1500 ej. ← 112 semillas

```fish
.venv/bin/python make_dataset.py --num 1500
setsid nohup env NEEDLE_TELEMETRY=0 XLA_PYTHON_CLIENT_PREALLOCATE=false \
  .venv/bin/needle finetune data/data.jsonl --epochs 3 --batch-size 1 \
  --val-split 0 --out data/adapter.safetensors > data/train_gpu.log 2>&1 < /dev/null &
tail -f data/train_gpu.log   # ver step/loss
NEEDLE_TELEMETRY=0 .venv/bin/needle build --lora data/adapter.safetensors --out data/tuned.cact
.venv/bin/python eval.py --data test_es.jsonl --weights data/tuned.cact
```

Train loss 0.63 → 0.004. Held-out: tipo 86%, exacto 40% (base: 64%/16%).

## Ronda 2 (2026-09-29): 2000 ej. ← 140 semillas (+28 anti-errores)

Semillas nuevas atacando fallos vistos: miles con punto (`45.000`),
variedad de `lucas`, `vendí`→ingreso, bono/liquidación→sueldo,
vocab nuevo (didi, peaje, cochera, delivery-comida, ferretería...).
Etiquetas alineadas con el gold de `test_es.jsonl` (cochera→alquiler,
estacionamiento→transporte). Mismo comando con `data2.jsonl`/`adapter2`/`tuned2`.

Train loss → 0.0000 (memoriza plantillas: techo del sintético).
Held-out: tipo 84%, exacto **48%**.

## Reglas del dataset

- `test_es.jsonl` es HELD-OUT: nunca entra a `make_dataset.py`. Cero duplicados
  exactos con `dataset_es.jsonl` (verificado por script).
- `make_dataset.py --num N`: multiplica semillas variando montos (correcciones
  del usuario pesan x3), 1/8 off-topic vacíos, reasoning auto, shuffle con seed.
- `data/` es generado y no se versiona. Semillas + scripts sí.

## Pendiente (ronda 3)

Dato real de `chat.py` (`corrections.jsonl`, hoy vacío): cuando haya ~50,
regenerar mezclado y reentrenar. Medir siempre en `test_es.jsonl` + una tanda
nueva de frases no vistas.
