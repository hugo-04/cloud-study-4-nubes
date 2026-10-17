# Azure · Caso integrado · Runbook de diagnóstico · Casos reales

Incidentes de ModaLima (ficticios), contados como los vería la guardia.

## 1. «Todo se ve verde» y nadie podía comprar
**Línea de tiempo:** 14:07 quejas por redes; 14:12 la guardia confirma 5xx; 14:20 aparece una alerta... que llegó **a las 14:19**.
**Causa:** las alertas eran por CPU y memoria; ninguna por **síntoma** (errores al comprar).
**Solución:** alertas por tasa de errores y por compras exitosas; panel con las cuatro señales.
**Lección:** alerta lo que siente el cliente, no lo que mide el servidor.

## 2. El despliegue del miércoles
**Línea de tiempo:** 16:00 despliegue; 16:25 sube la latencia; 17:10 equipo depurando en vivo; 17:40 alguien pregunta «¿qué cambió?».
**Solución:** primer paso del runbook = «qué cambió»; rollback en 6 minutos.
**Lección:** se pierden horas buscando una causa cuando la mitigación estaba a un clic.

## 3. El DNS que no resolvía
**Línea de tiempo:** 03:10 alerta de la sonda: `service-bus` en `DNS`; el equipo asumía problema de Azure.
**Causa:** una limpieza de zonas DNS borró un enlace a la red virtual del clúster.
**Solución:** la sonda señaló el escalón exacto; se restauró el enlace en 4 minutos y se añadió un bloqueo y una política de auditoría.
**Lección:** la escalera (DNS → puerto → TLS → identidad) evita discutir con el síntoma.

## 4. La cola de fallidos silenciosa
**Línea de tiempo:** 8 días sin alerta; 1 900 mensajes fallidos; clientes sin factura.
**Causa:** un campo nuevo en el evento que facturación no entendía.
**Solución:** alerta de fallidos > 0, procedimiento de reproceso, esquema versionado.
**Lección:** la cola de fallidos es una bandeja de pendientes, no un cementerio.

## 5. El permiso de emergencia que no caducó
**Qué pasó:** una persona recibió `Owner` durante un incidente; tres meses después aún lo tenía.
**Solución:** acceso privilegiado por solicitud con aprobación, motivo y vencimiento automático; revisión mensual.
**Lección:** lo temporal que no caduca solo es permanente.

## 6. El runbook que nadie había probado
**Qué pasó:** en un incidente, el paso 4 del runbook usaba un comando que ya no existía.
**Solución:** simulacro trimestral: se rompe algo en preproducción y se mide el tiempo de detección y resolución.
**Lección:** un runbook sin ensayo es una suposición por escrito.

## 7. Cambios en caliente que se perdieron
**Qué pasó:** se subió el nivel de la base «a mano» para sobrevivir al pico; el siguiente `terraform apply` lo bajó.
**Solución:** el escriba lo anota; el comandante pide regularizar el cambio en código antes de cerrar el incidente.
**Lección:** toda mitigación manual debe terminar en el repositorio.

| Problema | Solución |
|---|---|
| Alertas por causa | Alertas por síntoma |
| Depurar en caliente | Mitigar primero (rollback) |
| Diagnóstico a ciegas | Sonda sintética + escalera |
| Fallidos ignorados | Alerta y procedimiento |
| Permisos eternos | Acceso con caducidad |
| Runbooks viejos | Simulacros |
