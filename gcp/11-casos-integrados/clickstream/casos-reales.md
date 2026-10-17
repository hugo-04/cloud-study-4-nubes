# Google Cloud · Caso integrado · Clickstream · Casos reales

## 1. El top que bailaba
**Qué pasó:** el tablero de ModaLima cambiaba el top del minuto anterior sin parar.
**Causa:** ventanas por hora de llegada y móviles con retraso.
**Arreglo:** hora del evento + marca de agua de 30 s.
**Lección:** el tiempo del negocio es el del evento.

## 2. Conteos dobles tras un despliegue
**Qué pasó:** el top se duplicó durante un despliegue del tablero.
**Causa:** el pod nuevo releyó desde el último commit y la caché sumaba.
**Arreglo:** escribir el top de la ventana como reemplazo idempotente.
**Lección:** si relees, que repetir no cambie el resultado.

## 3. Lag en el Cyber
**Qué pasó:** el tablero iba 20 minutos atrasado.
**Causa:** 6 particiones y consumidores lentos por escrituras unitarias a la caché.
**Arreglo:** 12 particiones planificadas y escritura por ventana.
**Lección:** paralelismo = particiones; y lotes.

## 4. Datos personales en el historial
**Qué pasó:** en Café Andino el historial guardaba IP completas.
**Causa:** el colector reenviaba todo.
**Arreglo:** recorte en el colector.
**Lección:** minimiza en la entrada.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Top inestable | Hora de llegada | Hora del evento |
| 2 | Duplicados | Relectura + suma | Reemplazo idempotente |
| 3 | Lag | Particiones/escrituras | 12 particiones y lotes |
| 4 | Datos personales | Sin recorte | Minimizar |
