# AWS · Diagnóstico de conectividad · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. «Es la red» (y no lo era)
**Qué pasó:** pagos fallaba con timeouts; el equipo culpó a la red. **Diagnóstico:** Reachability decía *alcanzable*; los Flow Logs mostraban `ACCEPT`; `nc` conectaba. El problema era el pool de conexiones de la aplicación agotado. **Lección:** probar la red en minutos evita días de discusión.

## 2. El REJECT que señalaba a la NACL
**Qué pasó:** una API nueva no respondía. **Diagnóstico:** el origen veía `ACCEPT`, el destino registraba `ACCEPT` de entrada pero la respuesta aparecía `REJECT` al volver. **Causa:** NACL sin puertos efímeros. **Solución:** regla de retorno. **Lección:** mirar ambos lados del flujo.

## 3. DNS que resolvía a la IP equivocada
**Qué pasó:** SQS iba por el NAT y costaba. **Diagnóstico:** `dig` desde la tarea devolvía una IP pública. **Causa:** DNS privado apagado en el endpoint. **Lección:** el primer paso siempre es resolver el nombre.

## 4. Intermitente cada 5 minutos
**Qué pasó:** errores a una API de terceros cada cierto tiempo. **Diagnóstico:** la métrica `ErrorPortAllocation` del NAT subía en picos. **Solución:** reutilizar conexiones y repartir salidas. **Lección:** lo intermitente se mide con métricas, no con Reachability.

## 5. Un análisis guardado que evitó un incidente
**Qué pasó:** en el cambio de una tabla de rutas, el análisis programado «pedidos → base:5432» pasó a *no alcanzable* antes de que lo notara un usuario. **Solución:** revertir el cambio. **Lección:** convierte las rutas críticas en pruebas automáticas.

## 6. El runbook de media hora
**Qué pasó:** un incidente de conectividad se resolvía en horas. **Solución:** el procedimiento de seis pasos con herramientas listas (scripts, consultas, rol de SSM). Ahora tarda 15–30 minutos. **Lección:** el diagnóstico es un procedimiento, no un talento.

| Problema | Herramienta decisiva |
|---|---|
| «Es la red» | Reachability + Flow Logs |
| Retorno bloqueado | Flow Logs en ambos lados |
| DNS equivocado | `dig` desde la app |
| Intermitente | Métricas del NAT |
| Cambio que rompe | Análisis programado |
| Respuesta lenta | Runbook |
