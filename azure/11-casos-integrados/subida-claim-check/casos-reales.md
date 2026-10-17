# Azure · Caso integrado · Subida con Claim Check · Casos reales

Historias de Café Andino (ficticia).

## 1. El PDF que era un ejecutable
**Qué pasó:** un proveedor subió `factura.pdf` que en realidad era un instalador. El área contable lo abrió desde un enlace.
**Causa:** el sistema confiaba en la extensión y en el `Content-Type` declarado.
**Solución:** cuarentena + validación por bytes iniciales; solo `validados` se sirve.
**Lección:** el nombre y el encabezado los escribe quien sube; el contenido no miente.

## 2. El mensaje de 40 MB
**Qué pasó:** las facturas viajaban dentro del mensaje; la cola se atascaba y los costos crecían.
**Solución:** Claim Check: el mensaje lleva `{ruta, tamaño, hash}` (<1 KB).
**Lección:** la mensajería transporta avisos, no archivos.

## 3. La subida que nadie terminó
**Qué pasó:** 12 000 filas «pendientes» y 300 GB de blobs a medias tras tres meses.
**Causa:** usuarios que cerraban la app en mitad de la subida; sin limpieza.
**Solución:** conciliador (PENDIENTE vieja → EXPIRADA) y regla de ciclo de vida que borra cuarentena a las 24 h.
**Lección:** todo flujo con un paso del usuario necesita expiración.

## 4. La SAS con la clave de la cuenta
**Qué pasó:** una SAS de 7 días con la clave de la cuenta apareció en un foro. Para revocarla hubo que **rotar la clave de toda la cuenta**.
**Solución:** SAS de delegación de usuario de 10 minutos y `shared_access_key_enabled = false`.
**Lección:** una SAS de clave de cuenta solo se revoca con un martillo.

## 5. El evento duplicado que facturó dos veces
**Qué pasó:** Event Grid entregó dos veces el mismo evento; el validador emitió dos avisos.
**Solución:** transición `SUBIDA → VALIDADA` condicionada al estado: la segunda no hace nada (y el aviso va dentro de la misma transacción).
**Lección:** con entrega «al menos una vez», cada paso debe poder repetirse.

## 6. El validador que murió a medias
**Qué pasó:** un reinicio dejó 40 subidas en `SUBIDA` para siempre.
**Solución:** la cola devuelve el mensaje tras el tiempo de invisibilidad, y el conciliador revalida las atascadas.
**Lección:** diseña para el caso «murió a la mitad», no solo para el camino feliz.

## 7. CORS: «en el celular funciona, en el navegador no»
**Qué pasó:** las pruebas con `curl` iban bien; el navegador fallaba en la petición previa (`OPTIONS`).
**Causa:** CORS de la cuenta sin el origen ni las cabeceras `x-ms-*`.
**Solución:** regla CORS exacta en Terraform y prueba de integración desde el navegador.
**Lección:** `curl` no aplica CORS; el navegador sí.

## 8. El nombre elegido por el cliente
**Qué pasó:** dos proveedores subieron `lote.pdf` y uno sobrescribió el del otro.
**Solución:** el servidor genera `año/mes/UUID`; el nombre original solo se guarda como metadato.
**Lección:** nunca uses el nombre del cliente como ruta.

| Problema | Solución |
|---|---|
| Archivo no confiable | Cuarentena + validación por bytes |
| Mensajes enormes | Claim Check |
| Subidas abandonadas | Conciliador + ciclo de vida |
| Enlaces filtrados | SAS de delegación, corta y de un solo blob |
| Eventos duplicados | Transiciones idempotentes |
