# Azure · App Service · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar.)

## Caso 1 · El sitio de ModaLima y las campañas
- **Problema:** un servidor propio que se caía en cada campaña de descuentos.
- **Solución:** App Service Premium v3, autoescalado entre 2 y 6 instancias por CPU, slot `staging` y health check.
- **Resultado:** despliegues sin caída y campañas sin incidentes.
- **Lección:** un servicio administrado simple resuelve el 80 % de las webs; no empieces por Kubernetes.

## Caso 2 · El swap que devolvió 502
- **Problema:** tras cada *swap*, durante ~40 segundos los clientes veían 502.
- **Causa:** la app Spring Boot tardaba en arrancar y recibía tráfico antes de estar lista.
- **Solución:** `WEBSITE_SWAP_WARMUP_PING_PATH=/actuator/health/readiness` y readiness real que incluye la conexión a la base.
- **Lección:** el slot debe estar **caliente y listo** antes del cambio.

## Caso 3 · "Funciona en App Service pero no llega a la base de datos"
- **Problema:** `Connection timed out` hacia un PostgreSQL con Private Endpoint.
- **Causa:** la app no tenía **VNet Integration** (solo se había creado el Private Endpoint de la base) y además la zona DNS privada no estaba enlazada a la VNet.
- **Solución:** integrar la app a una subred delegada y enlazar `privatelink.postgres.database.azure.com`.
- **Lección:** salida privada = VNet Integration + DNS. El Private Endpoint de *otro* servicio no lo reemplaza.

## Caso 4 · Tres tareas programadas, tres correos duplicados
- **Problema:** el correo de resumen diario llegaba triplicado.
- **Causa:** `@Scheduled` corría en las tres instancias del plan.
- **Solución:** bloqueo distribuido (ShedLock sobre la base de datos) o mover la tarea a un job/Function de timer.
- **Lección:** en escala horizontal todo código programado corre N veces.

## Caso 5 · IP del cliente con puerto
- **Problema:** la lista blanca por IP rechazaba a todos con `1.2.3.4:51234`.
- **Causa:** App Service agrega el puerto en `X-Forwarded-For`.
- **Solución:** normalizar la cabecera y configurar el framework para confiar en los proxys.
- **Lección:** detrás de un proxy, la IP real hay que reconstruirla.

## Caso 6 · Sesiones perdidas al escalar
- **Problema:** usuarios deslogueados al subir de 1 a 3 instancias.
- **Causa:** sesión HTTP guardada en memoria de la instancia.
- **Solución:** Spring Session con Redis (o JWT sin estado) y desactivar ARR affinity.
- **Lección:** sin estado en la instancia, o la escala rompe la app.

## Caso 7 · Quitando la puerta de atrás
- **Problema:** una auditoría encontró que el sitio SCM aceptaba usuario y contraseña desde Internet.
- **Solución:** deshabilitar credenciales básicas de FTP y SCM, desplegar con identidad federada desde GitHub Actions, access restriction al sitio SCM.
- **Lección:** el sitio de administración también es una superficie de ataque.

## Caso 8 · Una factura sorpresa
- **Problema:** el plan de pruebas P3v3 quedó encendido todo el mes.
- **Solución:** dev y QA en B1/P0v3 con script de apagado, etiquetas de costo y presupuesto con alerta.
- **Lección:** el plan se paga por hora, haya tráfico o no.
