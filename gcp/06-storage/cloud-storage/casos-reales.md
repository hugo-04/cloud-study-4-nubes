# Google Cloud · Storage · Cloud Storage · Casos reales

## 1. El comprobante pisado
**Qué pasó:** un reintento regeneró el PDF de un pedido de ModaLima y reemplazó el ya enviado.
**Causa:** escritura sin precondición.
**Arreglo:** nombre determinista + `ifGenerationMatch=0`; un 412 significa «ya existía».
**Lección:** idempotencia también al guardar.

## 2. El bucket público
**Qué pasó:** exportes de clientes quedaron accesibles con `allUsers`.
**Causa:** ACL heredadas y permiso agregado «para probar».
**Arreglo:** acceso uniforme y prevención de acceso público por política de organización.
**Lección:** imposibilita el error.

## 3. Respaldos caros
**Qué pasó:** los respaldos de Café Andino costaban cada vez más.
**Causa:** todo en Standard.
**Arreglo:** ciclo de vida a Coldline/Archive y borrado tras la retención legal.
**Lección:** cada dato en su clase.

## 4. El objeto caliente
**Qué pasó:** un contador guardado como objeto fallaba con errores 429.
**Causa:** más de una escritura por segundo al mismo objeto.
**Arreglo:** el contador a una base de datos; Cloud Storage para archivos.
**Lección:** un objeto no es una fila.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Archivo reemplazado | Sin precondición | `ifGenerationMatch=0` |
| 2 | Datos expuestos | ACL/allUsers | Acceso uniforme + prevención |
| 3 | Costo alto | Sin ciclo de vida | Clases frías |
| 4 | 429 | Objeto caliente | Base de datos |
