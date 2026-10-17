# Oracle OCI · Caso integrado · Subida con claim check · Casos reales

## 1. El «JPG» que era un ejecutable
**Qué pasó:** se subió un archivo `foto.jpg` que en realidad era un script.
**Causa:** la validación miraba la extensión.
**Arreglo:** validar la firma (primeros bytes) y el tamaño antes de aprobar.
**Lección:** el nombre del archivo lo elige el atacante.

## 2. La API que se caía con fotos grandes
**Qué pasó:** las subidas de 20 MB agotaban memoria en los pods.
**Causa:** los archivos pasaban por la API.
**Arreglo:** PAR para subir directo al bucket.
**Lección:** los bytes grandes no deben pasar por tus servicios.

## 3. Subidas fantasma
**Qué pasó:** miles de registros `PENDIENTE` de hacía semanas.
**Causa:** usuarios que pedían la PAR y no subían nada.
**Arreglo:** reconciliador horario que marca `EXPIRADA`.
**Lección:** todo flujo de varios pasos necesita limpieza.

## 4. El evento doble que borró una foto aprobada
**Qué pasó:** una foto aprobada desapareció.
**Causa:** el segundo evento la volvió a validar, no la encontró en cuarentena y la marcó rechazada.
**Arreglo:** transiciones condicionales: si ya no está `RECIBIDA`, el evento se ignora.
**Lección:** idempotencia también en las máquinas de estado.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Archivo malicioso | Validar extensión | Firma + tamaño |
| 2 | Pods sin memoria | Bytes por la API | PAR directa |
| 3 | Pendientes eternos | Sin limpieza | Reconciliador |
| 4 | Aprobado borrado | Evento duplicado | Transición condicional |
