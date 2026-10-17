# AWS · Kinesis Data Streams · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. El clickstream del Black Friday
**Qué pasó:** la web de ModaLima enviaba cada clic por HTTP a analítica; con el pico, el servicio caía y se perdían clics. **Solución:** la web escribe en un stream con clave `idSesion`; analítica lee a su ritmo y, si se atrasa, no pierde datos mientras dure la retención. **Lección:** el stream absorbe el pico y desacopla a quien produce de quien procesa.

## 2. El shard caliente
**Qué pasó:** alguien usó el **país** como clave de partición; el 90 % del tráfico era de Perú y un shard se saturó con `WriteProvisionedThroughputExceeded` mientras los demás dormían. **Solución:** clave `idSesion` (alta cardinalidad), verificada antes con un simulador de distribución. **Lección:** la clave decide el reparto; pruébala con datos reales.

## 3. PutRecords devolvió 200
**Qué pasó:** en lotes de 500, algunos registros fallaban por límite de capacidad y nadie miraba `FailedRecordCount`. Se perdía ~1 %. **Solución:** reintento solo de los registros fallidos (por índice) con espera creciente, y separación de errores definitivos. **Lección:** el resultado es por registro.

## 4. El lector que se quedó atrás
**Qué pasó:** `IteratorAgeMilliseconds` subió a horas porque el procesamiento de antifraude hacía una llamada HTTP lenta por registro. **Solución:** procesar por lotes, aislar la llamada lenta, subir el paralelismo y, mientras tanto, ampliar la retención para no perder datos. **Lección:** vigila el atraso; la retención es tu margen, no tu plan.

## 5. Cinco lectores, un solo caño
**Qué pasó:** facturación, analítica, antifraude, búsqueda y auditoría leían el mismo stream en modo compartido y se robaban ancho de banda (2 MiB/s por shard entre todos). **Solución:** **fan-out mejorado** para los consumidores críticos. **Lección:** más lectores no es «gratis» en modo compartido.

## 6. Reprocesar tres días
**Qué pasó:** un error de cálculo en analítica contaminó tres días de métricas. **Solución:** corregir el código, arrancar una aplicación KCL nueva con posición inicial `AT_TIMESTAMP` y reescribir las agregaciones de forma idempotente (por clave y ventana). **Lección:** el stream es una máquina del tiempo… mientras la retención lo permita.

## Resumen

| # | Problema | Pieza que lo resolvió |
|---|---|---|
| 1 | Pico que tumba a analítica | Stream como amortiguador |
| 2 | Shard caliente | Clave de alta cardinalidad + simulador |
| 3 | Pérdida silenciosa en `PutRecords` | Reintento por registro |
| 4 | Lector atrasado | Alarma de atraso + paralelismo + retención |
| 5 | Lectores compitiendo | Fan-out mejorado |
| 6 | Datos contaminados | Retención + `AT_TIMESTAMP` + idempotencia |
