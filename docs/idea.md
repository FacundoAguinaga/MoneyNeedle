# Idea MoneyNeedle

## Problema
Registrar gastos a mano da pereza. Las apps actuales obligan a formularios. Las apps con IA mandan tus finanzas a la nube.

## Solución
Hablar o escribir como a un amigo: "gasté 5 lucas en súper", "me entraron 200k del sueldo", y que se cargue solo, **offline**.

## Principios
1. **Local-first / privado**: STT + Needle 3 + SQLite, todo en el dispositivo.
2. **Confirmación humana**: la IA propone, el usuario confirma/edita en 1 tap. Nunca carga silencioso en MVP.
3. **Sin fine-tune prematuro**: Fase 0 mide el modelo base. El fine-tune (LoRA local -> `.cact`) solo si el grounding falla.
4. **Cada corrección es futuro training data**: guardar `query/tools/answers/reasoning` desde día 1.

## MVP scope
* [x] Repo + scaffolding
* [ ] Prototype Python valida 50 frases ES (>90%)
* [ ] Agregar gasto/ingreso por texto
* [ ] Agregar por voz (STT local)
* [ ] Lista + balance + categorías
* [ ] Confirmar / editar propuesta de IA

## Fuera del MVP
* Cuentas múltiples, presupuestos, gráficos avanzados, sync nube, fine-tune automático.
