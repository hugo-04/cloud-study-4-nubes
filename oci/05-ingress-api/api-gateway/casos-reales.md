# Oracle OCI · Ingress y API · API Gateway · Casos reales

## 1. El token de otra aplicación
**Qué pasó:** un token emitido para la app de backoffice de ModaLima funcionaba en la API pública de pedidos.
**Causa:** el deployment validaba la firma y el emisor, pero no la audiencia.
**Arreglo:** `audiences = ["tienda-api"]` y alcances por ruta.
**Lección:** firma válida no significa token para ti.

## 2. El autorizador que tumbó la API
**Qué pasó:** en horas punta la API de socios de Café Andino respondía 500.
**Causa:** el autorizador propio consultaba la base en cada petición y agotó conexiones.
**Arreglo:** llaves con *hash* en memoria, caché de resultados del autorizador y expiración corta.
**Lección:** el autorizador está en el camino de cada llamada: debe ser rápido.

## 3. Los 504 del reporte
**Qué pasó:** el reporte de ventas fallaba siempre a los 60 segundos.
**Causa:** el tiempo de lectura del backend era menor que lo que tardaba la consulta.
**Arreglo:** el reporte pasó a asíncrono (202 + consulta de estado); la API no espera procesos largos.
**Lección:** un gateway no es para trabajos largos.

## 4. CORS en producción
**Qué pasó:** la tienda web dejó de funcionar tras cambiar de dominio.
**Causa:** `allowed_origins` con el dominio viejo.
**Arreglo:** orígenes por variable de entorno y prueba de *preflight* en el pipeline.
**Lección:** CORS es configuración de despliegue, pruébala.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Token ajeno aceptado | Sin audiencia | `audiences` + scopes |
| 2 | 500 en punta | Autorizador lento | Caché y *hash* en memoria |
| 3 | 504 constantes | Proceso largo | Patrón asíncrono |
| 4 | Navegador bloquea | CORS desactualizado | Orígenes por entorno |
