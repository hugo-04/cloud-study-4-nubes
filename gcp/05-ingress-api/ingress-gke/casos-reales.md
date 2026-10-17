# Google Cloud · Ingress y API · Entrada a GKE · Casos reales

## 1. El Ingress que nadie quería tocar
**Qué pasó:** un solo `Ingress` con 40 reglas de todos los equipos de ModaLima; cada cambio era una reunión.
**Causa:** el modelo de un objeto por balanceador.
**Arreglo:** Gateway compartido de plataforma y una `HTTPRoute` por equipo.
**Lección:** separa quién administra la puerta de quién define las rutas.

## 2. Chequeos fallidos en cadena
**Qué pasó:** el balanceador marcaba no sanos los pods del catálogo.
**Causa:** chequeo por defecto a `/`, que devolvía 302 al login.
**Arreglo:** `HealthCheckPolicy` a `/actuator/health/readiness`.
**Lección:** define el chequeo de cada servicio.

## 3. La IP del cliente equivocada
**Qué pasó:** el antifraude de Café Andino veía la IP del balanceador o IPs falsas.
**Causa:** tomaba el primer valor de `X-Forwarded-For`, que el cliente puede inventar.
**Arreglo:** tomar el penúltimo valor (el que agrega el balanceador de Google).
**Lección:** entiende quién escribe cada valor de la cabecera.

## 4. El namespace intruso
**Qué pasó:** un equipo publicó una ruta que capturaba `/api/*` de otro.
**Causa:** `allowedRoutes: All`.
**Arreglo:** namespaces permitidos por etiqueta y revisión de hosts/rutas por equipo.
**Lección:** compartir la puerta exige reglas de convivencia.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Cambios lentos | Ingress monolítico | Gateway + rutas |
| 2 | Pods no sanos | Chequeo por defecto | HealthCheckPolicy |
| 3 | IP falsa | Primer XFF | Penúltimo valor |
| 4 | Rutas capturadas | allowedRoutes abierto | Selector de namespaces |
