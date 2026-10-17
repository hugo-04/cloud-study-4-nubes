# Google Cloud · Red · Diagnóstico de conectividad · Casos reales

## 1. «La base está caída»
**Qué pasó:** el servicio de pedidos de ModaLima no conectaba a Cloud SQL tras un cambio.
**Causa:** una nueva política jerárquica denegaba el puerto 5432 desde la carpeta de desarrollo, aplicada por error a producción.
**Arreglo:** Connectivity Tests mostró la política exacta; se corrigió el alcance.
**Lección:** las políticas jerárquicas también son sospechosas.

## 2. Timeout vs rechazo
**Qué pasó:** se pasó una hora revisando firewall por un error «connection refused».
**Causa:** el proceso escuchaba en `127.0.0.1`.
**Arreglo:** escuchar en `0.0.0.0` dentro del contenedor.
**Lección:** rechazo inmediato = llegó, pero nadie escucha.

## 3. La regla que nunca se usó
**Qué pasó:** Firewall Insights mostró que una regla «temporal» abierta llevaba un año sin coincidencias.
**Causa:** quedó tras una migración.
**Arreglo:** eliminarla.
**Lección:** limpia reglas con datos, no con miedo.

## 4. El 403 que parecía de red
**Qué pasó:** Café Andino abrió firewall para una llamada a Cloud Storage que daba 403.
**Causa:** la cuenta de servicio no tenía el rol.
**Arreglo:** rol `storage.objectViewer` y cerrar lo abierto.
**Lección:** 403 es IAM, no red.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Timeout a la base | Deny jerárquico | Connectivity Tests |
| 2 | Refused | Escucha en localhost | Escuchar en 0.0.0.0 |
| 3 | Regla vieja | Restos de migración | Insights y borrar |
| 4 | 403 | IAM | Rol correcto |
