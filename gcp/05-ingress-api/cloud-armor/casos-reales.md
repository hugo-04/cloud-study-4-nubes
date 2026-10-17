# Google Cloud · Ingress y API · Cloud Armor · Casos reales

## 1. Las reseñas bloqueadas
**Qué pasó:** las reseñas con comillas de ModaLima devolvían 403.
**Causa:** firma de inyección SQL activada sin vista previa ni exclusiones.
**Arreglo:** vista previa dos semanas y exclusión del campo `comentario` para esa firma.
**Lección:** ajusta antes de bloquear.

## 2. Fuerza bruta en el login
**Qué pasó:** miles de intentos por minuto contra `/v1/login`.
**Causa:** sin limitación de tasa.
**Arreglo:** `rate_based_ban` 10/min por IP con baneo de 10 minutos.
**Lección:** protege las rutas sensibles por separado.

## 3. Cloud Run esquivado
**Qué pasó:** los ataques llegaban a la URL `run.app` directamente.
**Causa:** ingress `all` en Cloud Run.
**Arreglo:** ingress `internal-and-cloud-load-balancing`.
**Lección:** si hay otra puerta, el WAF no sirve.

## 4. El ataque de la madrugada
**Qué pasó:** un pico de peticiones L7 tumbó el catálogo de Café Andino.
**Causa:** sin Adaptive Protection ni reglas de tasa generales.
**Arreglo:** Adaptive Protection con alertas y despliegue de la regla sugerida.
**Lección:** la detección automática compra tiempo.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | 403 legítimos | Sin vista previa | Vista previa + exclusión |
| 2 | Fuerza bruta | Sin tasa | Rate-based ban |
| 3 | Bypass | Ingress abierto | Interno + balanceador |
| 4 | Caída por L7 | Sin detección | Adaptive Protection |
