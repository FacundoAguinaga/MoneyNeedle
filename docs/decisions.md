# Decisiones de diseño (ADRs cortos)

1. **Un solo tool `add_transaction`** (no 10, no gasto/ingreso separados).
   La variante 2-tools daba +4pp en tipo pero más alucinaciones y más
   categorías rotas. El tipo va como enum y la app lo confirma.
2. **`transferencia` no existe como tipo.** Las transferencias van como
   gasto/otros. Menos enums = mejor grounding en modelo tiny.
3. **Moneda y fecha las pone la app, no el modelo.** `moneda` como parámetro
   libre hacía que el modelo metiera la categoría ahí. La app detecta
   USD/EUR por keywords (default ARS) y fecha = hoy salvo que haya lógica
   de relativos después. Además: la moneda en el prompt confunde al modelo
   ("usd"→monto 200000), así que se le saca de la frase antes de llamar.
4. **`complete()`, no `run()`.** `run()` intenta ejecutar funciones Python y
   falla con schemas JSON. Se lee `function_calls` + `suppressed_calls`
   (el base local no calibra confidence y todo cae en suppressed).
5. **MVP siempre confirma.** Se ignora `confidence` (None en modelos
   tuneados localmente). Auto-carga solo si algún día se supera 90% exacto
   en held-out.
6. **Guardrails en app, no fe ciega:** grounding (monto debe estar en el
   texto), keywords por palabra completa como fallback de categoría,
   reintento ante respuesta vacía, sin dígitos→rechazar.
7. **Español rioplatense, montos con todas sus formas:** k, lucas, mil,
   puntos de miles, palabras. El tokenizer fragmenta el español ~1.7x;
   schema chico y `max_new_tokens=1024` (con 512 hay truncations).
8. **Frases ambiguas no se etiquetan con default.** "clases 25000" sin verbo
   es ingreso o gasto según quién habla: va a confirmación manual.
   El verbo (`cobré`/`pagué`/`vendí`) es la señal que el modelo aprende.
9. **Sacar `Transferencia` del enum Rust.** ADR 2 dice que no existe; el enum
   la tenía por scaffold inicial. Antes de conectar core↔Flutter, limpiar.
10. **App multiplataforma con Flutter.** Se evaluaron Flutter, KMP, Kotlin
    nativo, React Native y Swift. Flutter gana por `flutter_rust_bridge`
    (genera bindings Dart↔Rust automáticamente). KMP requiere FFI manual por
    plataforma (JNI + cinterop). React Native descartado por FFI pobre.
    Kotlin nativo descartado porque se necesita iOS. Detalle en `docs/stack.md`.
11. **STT: nativo primero, sherpa-onnx después.** Android `SpeechRecognizer` y
    iOS `SFSpeechRecognizer` funcionan offline con modelos descargables, sin
    dependencias extra. Si no alcanzan, agregar sherpa-onnx via C API en Rust.
12. **Dart es solo UI.** Toda la lógica de negocio (parsing, grounding,
    keywords, moneda, validación, inferencia Needle) vive en Rust. Flutter
    llama al core via `flutter_rust_bridge` y muestra resultados. Nunca
    duplicar lógica en Dart.
13. **STT: locale del sistema + fallback online.** Forzar `es-AR` falla con
    STT_12 si no está el pack offline. Se intenta offline primero y ante
    error 12/13/2 se reintenta online una vez. El permiso de mic se pide
    con `permission_handler`, con atajo a Ajustes si está bloqueado.
