# AWS · Caso integrado · Runbook de diagnóstico · Casos reales

## 1. «Nadie compra» y el WAF era el culpable
**Qué pasó:** a las 14:07 de una campaña, las ventas cayeron a cero sin ningún 5xx.
**Causa:** una regla nueva del WAF bloqueaba el `User-Agent` de la aplicación móvil. El balanceador no veía tráfico: la alarma `sin-trafico` fue la única en saltar.
**Arreglo:** regla en modo «contar», luego corregida; la alarma compuesta ya pagina por silencio.
**Lección:** si no hay errores pero tampoco peticiones, el fallo está antes del ALB.

## 2. El rollback que ahorró dos horas
**Qué pasó:** 5xx del 30 % tras un despliegue de la tarde.
**Causa:** una variable de entorno apuntaba a un secreto que aún no existía.
**Arreglo:** `triage.sh` mostró `UpdateService` a 2 minutos del inicio; el comandante ordenó **rollback** en 4 minutos y la causa se analizó después.
**Lección:** «¿qué cambió?» antes que cualquier hipótesis; mitigar primero.

## 3. DNS que resolvía a la IP pública
**Qué pasó:** `GetQueueAttributes` empezó a fallar por *timeout* solo en un clúster nuevo.
**Causa:** la VPC del clúster no tenía habilitado el DNS privado del endpoint de SQS; el nombre resolvía a una IP pública sin salida.
**Arreglo:** activar «DNS privado» y comprobar nombres de host en la VPC.
**Lección:** la sonda marcó `DNS_PUBLICA` al primer minuto; sin ella se habrían revisado grupos de seguridad durante horas.

## 4. La DLQ que crecía sin que nadie lo viera
**Qué pasó:** 300 pedidos sin factura al día siguiente.
**Causa:** facturación rechazaba un campo nuevo; los mensajes iban a la DLQ y nadie tenía alarma sobre ella.
**Arreglo:** alarma `facturacion-dlq` ( >0 ), lectura del motivo y *redrive* controlado tras corregir.
**Lección:** una DLQ sin alarma es un cajón cerrado.

## 5. Puertos agotados en la NAT
**Qué pasó:** errores intermitentes al llamar a un proveedor de pagos externo, sin despliegues.
**Causa:** un cliente HTTP abría una conexión nueva por llamada; `ErrorPortAllocation` en la NAT.
**Arreglo:** reutilizar conexiones, más NAT por zona y alarma `nat-puertos`.
**Lección:** los fallos intermitentes de salida suelen ser de puertos, no del proveedor.

## 6. El postmortem que cambió la guardia
**Qué pasó:** tres incidentes seguidos tuvieron «¿quién decide?» como mayor demora.
**Causa:** nadie asumía el mando; todos tecleaban.
**Arreglo:** roles fijos (comandante, operador, comunicación, escriba) y un simulacro trimestral.
**Lección:** el proceso humano pesa tanto como las herramientas.

## Resumen
| # | Síntoma | Causa | Señal que lo mostró | Mitigación |
|---|---|---|---|---|
| 1 | Cero ventas, cero 5xx | Regla de WAF | Alarma `sin-trafico` | Regla en modo contar |
| 2 | 30 % de 5xx | Despliegue con secreto faltante | CloudTrail `UpdateService` | Rollback |
| 3 | Timeout a SQS | DNS privado desactivado | Sonda `DNS_PUBLICA` | Activar DNS privado |
| 4 | Sin factura | DLQ sin alarma | `ApproximateNumberOfMessagesVisible` | Redrive tras corregir |
| 5 | Salida intermitente | Puertos NAT agotados | `ErrorPortAllocation` | Reutilizar conexiones |
| 6 | Respuesta lenta del equipo | Sin roles | Línea de tiempo del postmortem | Roles y simulacros |
