# Google Cloud · Gobierno · Organization Policy · Casos reales

## 1. La base expuesta que no pudo existir
**Qué pasó:** un desarrollador de ModaLima intentó dar IP pública a Cloud SQL «para conectarse desde casa».
**Causa:** (sin incidente) `sql.restrictPublicIp` lo bloqueó.
**Arreglo:** acceso con el Auth Proxy por IAP.
**Lección:** las barandas evitan incidentes antes de que existan.

## 2. El despliegue que se rompió el lunes
**Qué pasó:** al activar `gcp.resourceLocations`, el pipeline de Café Andino falló.
**Causa:** recursos en `us-central1` que nadie conocía.
**Arreglo:** dry run de dos semanas, migrar y luego aplicar.
**Lección:** simula primero.

## 3. El correo personal con acceso
**Qué pasó:** un consultor compartió un bucket con su Gmail.
**Causa:** sin restricción de dominios.
**Arreglo:** `iam.allowedPolicyMemberDomains` con el ID del cliente de Cloud Identity.
**Lección:** limita quién puede recibir permisos.

## 4. La excepción eterna
**Qué pasó:** una carpeta tenía `compute.vmExternalIpAccess` desactivada «temporalmente» hacía un año.
**Causa:** `reset` sin fecha ni dueño.
**Arreglo:** excepción por tag para dos VMs concretas.
**Lección:** excepciones pequeñas, etiquetadas y revisadas.

## Resumen
| # | Situación | Causa | Arreglo |
|---|---|---|---|
| 1 | Bloqueo correcto | Línea base | Acceso privado |
| 2 | Pipeline roto | Sin dry run | Simular |
| 3 | Acceso externo | Sin dominios | Restringir |
| 4 | Excepción amplia | Reset | Tag puntual |
