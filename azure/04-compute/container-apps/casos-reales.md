# Azure · Container Apps · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar.)

## Caso 1 · De App Service a Container Apps para dormir de noche
- **Problema:** un entorno de QA con 6 APIs en App Service pagaba 24 h aunque solo se usaba de 9 a 18.
- **Solución:** las 6 APIs como Container Apps con `minReplicas = 0` en QA.
- **Resultado:** el costo nocturno bajó casi a cero; la primera petición de la mañana tarda unos segundos más.
- **Lección:** escalar a cero es ideal para pruebas; en producción de cara al público mide el arranque en frío.

## Caso 2 · Workers que siguen a la cola
- **Problema:** consumidores de pedidos con 5 réplicas fijas; los lunes se saturaban y el resto de la semana estaban ociosos.
- **Solución:** regla KEDA sobre Service Bus (`messageCount = 20`, `maxReplicas = 25`) autenticada con **identidad administrada**.
- **Resultado:** de 0 a 25 réplicas según el backlog; costo proporcional al trabajo.
- **Lección:** escalar por evento supera a escalar por CPU en cargas de colas. Pon un tope para no aplastar la base de datos.

## Caso 3 · Despliegue azul/verde con una reversión de 10 segundos
- **Problema:** un cambio de serialización rompió a un cliente móvil en producción.
- **Solución:** modo **multiple**, v2 con 10 % del tráfico y una etiqueta `green` para QA; al ver errores, el tráfico volvió a 100 % en v1.
- **Lección:** las revisiones inmutables convierten el rollback en cambiar un porcentaje.

## Caso 4 · El arranque en frío de la JVM
- **Problema:** con `minReplicas = 0`, el primer cliente esperaba 9 segundos (Spring Boot + Hibernate).
- **Solución:** `minReplicas = 1` para la API de cara al cliente, 0 para los workers; CDS de aplicación y menos inicialización perezosa.
- **Lección:** el arranque de una JVM es parte del SLA; decide por servicio qué tolera esperar.

## Caso 5 · Microservicios con Dapr
- **Problema:** cada servicio tenía su propio código de reintentos y su propia integración con Service Bus.
- **Solución:** Dapr `pubsub` (Service Bus) e invocación entre servicios con reintentos y mTLS; el componente se define en YAML.
- **Resultado:** el código de negocio habla HTTP con `localhost:3500`; al probar localmente se sustituye por Redis.
- **Lección:** Dapr quita infraestructura del código, a cambio de aprender sus componentes.

## Caso 6 · Entorno interno detrás de Application Gateway
- **Problema:** una auditoría exigió que ninguna API estuviera expuesta directamente a Internet.
- **Solución:** entorno **interno** en la VNet, ingress `internal`, y Application Gateway con WAF delante; DNS privado para el dominio del entorno.
- **Lección:** el ingress público es una decisión del entorno; planifícala al crearlo.

## Caso 7 · El reporte de las 07:00 como Job
- **Problema:** una VM encendida 24 h para correr un reporte de 20 minutos.
- **Solución:** un Job programado (cron) con `replicaTimeout = 1800` y reintento 1.
- **Resultado:** se paga solo la ejecución.
- **Lección:** si solo corre 20 minutos al día, no pagues 24 horas.

## Caso 8 · La subred era muy pequeña
- **Problema:** la creación del entorno falló con un error de espacio de direcciones.
- **Causa:** se reservó una /27 para un tipo de entorno que necesitaba más.
- **Solución:** recrear con la subred del tamaño correcto (*workload profiles* con /27 como mínimo, o /23 en Consumption-only; verifica).
- **Lección:** el tamaño de la subred y el tipo de entorno no se cambian después.

## Caso 9 · IP de salida para el allowlist del proveedor
- **Problema:** un banco solo aceptaba llamadas desde IP conocidas; la salida de ACA cambiaba.
- **Solución:** entorno de *workload profiles* en VNet con **NAT Gateway** y su IP pública fija.
- **Lección:** la IP de salida predeterminada no es tuya; si la necesitas, constrúyela.

## Caso 10 · Revisiones fantasma
- **Problema:** la factura no bajaba tras escalar a cero.
- **Causa:** varias revisiones antiguas seguían activas con `minReplicas = 2`.
- **Solución:** desactivar revisiones viejas; política de limpieza en el pipeline.
- **Lección:** en modo *multiple*, tú desactivas lo que ya no usas.

## Caso 11 · Rotación de un secreto sin redespliegue
- **Problema:** la clave de una API externa se rotaba a mano y requería redeploy.
- **Solución:** secreto de la app como **referencia a Key Vault** con identidad; al cambiar la versión y reiniciar la revisión, se toma el nuevo valor.
- **Lección:** las referencias a Key Vault eliminan secretos del código y simplifican la rotación; el reinicio de la réplica sigue siendo necesario para variables de entorno.
