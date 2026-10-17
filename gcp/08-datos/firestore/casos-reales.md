# Google Cloud · Datos · Firestore · Casos reales

## 1. El contador de visitas lento
**Qué pasó:** el contador de un producto viral de ModaLima daba errores de contención.
**Causa:** cientos de escrituras por segundo al mismo documento.
**Arreglo:** contador distribuido en 20 fragmentos; la lectura suma.
**Lección:** un documento aguanta pocas escrituras sostenidas.

## 2. «The query requires an index»
**Qué pasó:** la consulta de carritos por nivel y fecha falló en producción.
**Causa:** índice compuesto creado a mano solo en desarrollo.
**Arreglo:** índices en Terraform para todos los entornos.
**Lección:** los índices son esquema.

## 3. Carritos fantasma
**Qué pasó:** Café Andino guardaba millones de carritos abandonados.
**Causa:** nadie los borraba.
**Arreglo:** campo `expira` con política TTL.
**Lección:** TTL desde el día uno.

## 4. Las reglas que no protegían
**Qué pasó:** se pensó que las reglas bloqueaban al backend.
**Causa:** el SDK de servidor usa IAM y no evalúa reglas.
**Arreglo:** roles mínimos y validación en el backend.
**Lección:** reglas para clientes, IAM para servidores.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Contención | Documento caliente | Fragmentos |
| 2 | Consulta falla | Índice faltante | Índices como código |
| 3 | Costo de almacenamiento | Sin limpieza | TTL |
| 4 | Falsa seguridad | Reglas vs IAM | Roles mínimos |
