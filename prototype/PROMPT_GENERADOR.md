# PROMPT para IA generadora de frases (copiar desde "INICIO" hasta "FIN")

INICIO — copiar todo lo de abajo
---
Sos un generador de datos de entrenamiento para MoneyNeedle, una app argentina
de finanzas donde el usuario escribe o dicta sus movimientos y una IA tiny
(Cactus Needle 3) los convierte en transacciones.

Tu salida es SOLO líneas JSON (JSONL), un objeto por línea, sin explicaciones,
sin markdown, sin numerar. Cada objeto tiene esta forma exacta:

{"query": "gasté 5000 en supermercado", "expected": {"tipo": "gasto", "monto": 5000, "categoria": "supermercado"}}

Valores permitidos:
- tipo: "gasto" o "ingreso". Gastos (70%): gasté, compré, pagué, taxi, súper,
  cena, alquiler, farmacia, tarjeta, impuestos, streaming, ropa, auto.
  Ingresos (30%): me pagaron, me entraron, cobré, sueldo, aguinaldo,
  me transfirieron, freelance. Las transferencias entre cuentas propias van
  como {"tipo": "gasto", "categoria": "otros"}.
- monto: número. Debe aparecer LITERAL en la frase (si decís "200k", el monto
  es 200000; si decís "5 lucas", es 5000; si decís "doscientos mil", es 200000).
- categoria: "supermercado" (súper, verdulería, kiosco, almacén),
  "transporte" (taxi, uber, bondi, colectivo, nafta, remis),
  "comida" (delivery, café, cena, almuerzo, restaurante, parrilla, asado),
  "alquiler", "sueldo" (solo para ingresos de sueldo/aguinaldo),
  "servicios" (luz, gas, agua, internet, tarjeta, expensas, celular, impuestos,
  netflix, spotify), "salud" (farmacia, médico, dentista),
  "otros" (ropa, perfume, peluquería, préstamos, freelance, banco, auto/taller).

Reglas de estilo (español rioplatense, como hablándole a un amigo):
- Frases cortas, 3 a 8 palabras. Voseo: "gasté", "compré", "pagá" no, "pagué".
- Variá la forma del monto EN ESTA PROPORCIÓN: 40% dígitos simples ("8000"),
  15% con k ("200k", "5k"), 15% con luca/mil ("5 lucas", "200 mil", "mil"),
  15% con puntos de miles ("15.000", "1.000.000"), 15% en palabras
  ("cinco mil", "doscientos mil", "tres millones").
- 20% sin tilde ni mayúsculas y con errores típicos de dictado por voz:
  "gaste", "super", "cafe", "farmacia" bien, "iverduleria" no (eso es demasiado).
- A veces con fecha relativa ("ayer", "hoy", "el lunes", "esta mañana") y a
  veces sin fecha. A veces con "en efectivo" / "con tarjeta" (no cambia nada).
- 1 de cada 8 líneas es OFF-TOPIC con tipo nulo, así:
  {"query": "contame un chiste", "expected": {"tipo": null, "monto": null, "categoria": null}}
  Ejemplos off-topic: saludos, clima, chistes, preguntas generales, "llamame un taxi".

Ejemplos (seguí este nivel de variedad):
{"query": "gasté 5000 en supermercado", "expected": {"tipo": "gasto", "monto": 5000, "categoria": "supermercado"}}
{"query": "me pagaron 200k del sueldo", "expected": {"tipo": "ingreso", "monto": 200000, "categoria": "sueldo"}}
{"query": "uber 4500 hasta lo de mamá", "expected": {"tipo": "gasto", "monto": 4500, "categoria": "transporte"}}
{"query": "compre 200 mil en ropa", "expected": {"tipo": "gasto", "monto": 200000, "categoria": "otros"}}
{"query": "pague mil pesos de impuestos", "expected": {"tipo": "gasto", "monto": 1000, "categoria": "servicios"}}
{"query": "cobré 150000 de freelance", "expected": {"tipo": "ingreso", "monto": 150000, "categoria": "otros"}}
{"query": "hola qué hora es", "expected": {"tipo": null, "monto": null, "categoria": null}}

Generame 100 líneas JSONL así ahora.
FIN
