# AWS · Claim Check · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. Los catálogos de 300 MB que no cabían
**Qué pasó:** los proveedores de ModaLima enviaban catálogos de imágenes (decenas de MB) que se intentaban meter en un mensaje. **Solución:** el proveedor sube a S3 con URL prefirmada y el sistema publica un ticket de 600 bytes. **Lección:** el broker transporta intención, no volumen.

## 2. El ticket que llegó antes que el archivo
**Qué pasó:** el productor publicaba el ticket y luego subía el archivo; el consumidor, rápido, fallaba con `NoSuchKey` a veces. **Solución:** subir primero, publicar después, y reintentos con espera para la variante por eventos. **Lección:** orden: dato, luego referencia.

## 3. Procesado dos veces, cobrado dos veces
**Qué pasó:** SQS entregó un mensaje duplicado y se generaron dos facturas. **Solución:** registro de idempotencia con escritura condicional en DynamoDB y estado «en proceso/completado». **Lección:** la entrega es *al menos una vez*.

## 4. El objeto cambió bajo los pies
**Qué pasó:** un proceso reemplazó el archivo mientras el consumidor lo leía; se procesó una versión mezclada. **Solución:** bucket versionado y `versionId` + SHA-256 en el ticket. **Lección:** referencia inmutable o no es referencia.

## 5. La DLQ con tickets muertos
**Qué pasó:** los mensajes de la DLQ se revisaron a los 20 días; los objetos ya habían expirado por el ciclo de vida de 7 días. **Solución:** retención del objeto mayor que la de la DLQ (14 días) más margen de análisis. **Lección:** el ticket de la DLQ necesita su objeto.

## 6. El inquilino curioso
**Qué pasó:** un productor interno publicó un ticket apuntando al archivo de otro cliente; el consumidor, con permisos amplios, lo procesó. **Solución:** validar bucket y prefijo del ticket y limitar el rol del consumidor a su prefijo. **Lección:** el ticket es entrada no confiable.

| Problema | Solución |
|---|---|
| Mensaje demasiado grande | Claim Check con S3 |
| `NoSuchKey` intermitente | Subir antes de publicar |
| Doble procesamiento | Idempotencia con condicional |
| Archivo modificado | Versionado + `versionId` + hash |
| Tickets sin objeto | Retención del objeto > DLQ |
| Acceso cruzado | Validar prefijo + rol mínimo |
