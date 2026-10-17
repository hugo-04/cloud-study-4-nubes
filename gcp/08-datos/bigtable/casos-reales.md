# Google Cloud · Datos · Bigtable · Casos reales

## 1. La clave con fecha primero
**Qué pasó:** la telemetría de Café Andino usaba `20260601#maquina` y un nodo estaba al 100 %.
**Causa:** todas las escrituras del día en el mismo rango.
**Arreglo:** `maquina#tsInvertido`.
**Lección:** la entidad va primero.

## 2. La consulta por temperatura
**Qué pasó:** quisieron «todas las lecturas > 95 °C» y tardaba minutos.
**Causa:** filtro sin clave = escaneo completo.
**Arreglo:** exportar a BigQuery para analítica; Bigtable para lecturas por máquina.
**Lección:** Bigtable responde preguntas que conoce de antemano.

## 3. El almacenamiento que no paraba de crecer
**Qué pasó:** cada celda guardaba todas sus versiones.
**Causa:** familia sin política de GC.
**Arreglo:** GC por edad de 30 días.
**Lección:** define la retención al crear la familia.

## 4. Lecturas lentas en el panel
**Qué pasó:** el panel de ModaLima competía con la carga batch.
**Causa:** mismo clúster y perfil para todo.
**Arreglo:** segundo clúster y perfiles de app separados.
**Lección:** aísla cargas con clústeres y perfiles.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Nodo caliente | Fecha primero | Entidad primero |
| 2 | Lentitud | Escaneo | BigQuery |
| 3 | Crecimiento | Sin GC | GC por edad |
| 4 | Interferencia | Mismo clúster | Perfiles |
