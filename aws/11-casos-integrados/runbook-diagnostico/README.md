# AWS · Caso integrado · Runbook de diagnóstico de la tienda

Son las 14:07 de un jueves de campaña y la guardia recibe: **«los clientes no pueden comprar»**. Un *runbook* es el procedimiento escrito, probado y a mano que convierte ese momento de pánico en una secuencia de pasos: **qué mirar primero, cómo decidir, cómo mitigar y a quién avisar**. Este caso reúne lo aprendido en los capítulos de red, IAM, mensajería, datos y gobierno en un solo documento operativo para la tienda de ModaLima.

## 1. Qué es

**Analogía:** la lista de verificación de un piloto. No se improvisa en una emergencia: se leen pasos que otros ya ensayaron. Primero **estabilizar** (que el avión siga volando), después **entender** (por qué falló). En un incidente la prioridad es la misma: **mitigar primero, buscar la causa raíz después**.

```
 Alarma / queja ──► 1. Declarar y asignar roles ──► 2. ¿Qué cambió? ──► 3. Acotar la capa ──► 4. Mitigar ──► 5. Confirmar ──► 6. Postmortem
                         (2 min)                      (2 min)           (escalera RPDSI       (rollback,      (las métricas   (sin culpables,
                                                                         + sonda sintética)    escalar,        vuelven)        con acciones)
                                                                                               desactivar)
```

## 2. Cómo funciona por dentro

### 2.1 Roles y severidad

| Rol | Hace | No hace |
|---|---|---|
| **Comandante** | Decide, prioriza, pide ayuda, declara el fin | Teclear comandos (delega) |
| **Operador** | Ejecuta las comprobaciones y mitigaciones | Decidir solo acciones de riesgo |
| **Comunicación** | Actualiza al negocio y a los clientes cada 15–30 min | Especular sobre causas |
| **Escriba** | Anota la línea de tiempo con horas | Participar en el diagnóstico |

| Severidad | Criterio (ejemplo ModaLima) | Respuesta |
|---|---|---|
| **1** | No se puede comprar, no llega tráfico, o hay pérdida/exposición de datos | Guardia + comandante inmediatos; aviso a gerencia |
| **2** | Degradación seria (lentitud, un medio de pago caído) | Guardia en minutos |
| **3** | Fallo parcial sin impacto directo (cola de fallidos creciendo, una dependencia con errores) | Dentro del horario |

### 2.2 Los primeros cinco minutos (siempre igual)
1. **Declara el incidente** y asigna roles (2 min).
2. **¿Qué cambió?** Despliegues, reglas de red, políticas de IAM, rotación de secretos, certificados, picos de tráfico. La mayoría de los incidentes empiezan con un cambio ([`triage.sh`](ejemplos/cli/triage.sh) lo lista con CloudTrail).
3. **¿Cuánto y desde cuándo?** Tasa de errores por minuto (alarma, [panel](ejemplos/terraform/main.tf) y [consulta 1](ejemplos/logs-insights/consultas.md)).
4. **¿Qué capa?** Sigue la cadena de abajo.

> **CloudTrail tarda.** Los eventos de gestión pueden tardar hasta ~15 minutos en aparecer en `LookupEvents`. Si «no cambió nada» pero el problema es de hace 3 minutos, pregunta también al equipo y mira el historial de la herramienta de despliegue.

### 2.3 La cadena de capas (de afuera hacia adentro)

| Capa | Pregunta | Dónde mirar |
|---|---|---|
| Borde (Route 53, CloudFront, WAF) | ¿Resuelve el nombre? ¿El WAF bloquea clientes buenos? ¿El origen está sano? | Métricas de CloudFront y WAF (`BlockedRequests`), registros del WAF, salud del origen |
| Balanceador (ALB) | ¿Los 5xx los genera el balanceador (`ELB_5XX`) o el destino (`Target_5XX`)? ¿Destinos sanos? | Métricas del ALB; `describe-target-health` ([`triage.sh`](ejemplos/cli/triage.sh)) |
| Cómputo (EKS/ECS) | ¿Pods o tareas sanos? ¿Reinicios? ¿`OOMKilled`? | `kubectl get pods`, eventos; eventos del servicio de ECS |
| Aplicación | ¿Qué operación falla? ¿Qué excepción? | [Consultas 2–4](ejemplos/logs-insights/consultas.md) |
| Dependencias | ¿RDS, Redis, SQS, Secrets Manager responden? | **Sonda sintética** ([Java](uso-en-java.md)) |
| Red privada | ¿DNS, ruta, grupo de seguridad, ACL, endpoint de VPC? | Escalera [RPDSI](../../01-red/diagnostico-conectividad/README.md), Reachability Analyzer, Flow Logs |
| Identidad | ¿`AccessDenied`? ¿credenciales del pod? | Mensaje de error del servicio; CloudTrail (`errorCode`); política de confianza del rol |
| Plataforma AWS | ¿Incidente del proveedor? | AWS Health (regla de EventBridge del [Terraform](ejemplos/terraform/main.tf)) |

> **Regla de oro:** un `AccessDenied` o `403` no es de red; un *timeout* no es de identidad. El síntoma te dice el escalón ([tabla](../../01-red/diagnostico-conectividad/README.md)).

### 2.4 Runbooks por síntoma

**A. «Los clientes ven errores al comprar» (5xx en `POST /api/pedidos`)**

| Paso | Comprobación | Si es así… | Mitigación |
|---|---|---|---|
| 1 | ¿Hubo despliegue o cambio en los últimos 60 min? | Sí | **Rollback** a la versión anterior (no depurar en caliente) |
| 2 | ¿La sonda marca DNS/PUERTO/TLS/IDENTIDAD en alguna dependencia? | Sí | Seguir la escalera RPDSI; revisar cambios de red recientes |
| 3 | ¿RDS con conexiones agotadas o bloqueos? | Sí | Matar sesiones bloqueadas; limitar tráfico; subir tamaño con ventana |
| 4 | ¿Tareas/pods en reinicio (`OOMKilled`, `CrashLoopBackOff`)? | Sí | Revertir; subir límites si es memoria; revisar secretos |
| 5 | Nada de lo anterior | — | Escalar a desarrollo con la traza de una petición fallida ([consulta 4](ejemplos/logs-insights/consultas.md)) |

**B. «La compra va lenta» (p95 alto, sin errores)**

| Paso | Comprobación | Mitigación |
|---|---|---|
| 1 | ¿Qué operación tiene el p95 alto? ([consulta 3](ejemplos/logs-insights/consultas.md)) | Escalar esa dependencia o su caché |
| 2 | ¿Redis fuera o caché fría? | Calentar con cuidado; subir el tiempo de vida |
| 3 | ¿Nodos o tareas sin recursos? | Escalar |
| 4 | ¿Un cliente o bot acapara? | Regla de límite por IP en WAF |

**C. «Pedidos creados, sin factura»** (cola envejeciendo o mensajes en la DLQ)

| Paso | Comprobación | Mitigación |
|---|---|---|
| 1 | Alarmas `facturacion-antiguedad` / `facturacion-dlq` | Revisar el consumidor: permisos, DNS del endpoint de SQS |
| 2 | Mensajes en la DLQ | Leer el motivo; corregir y **reprocesar con procedimiento** (redrive) |
| 3 | ¿Consumidor reiniciándose? | Revisar excepciones; la lógica debe ser idempotente |
| 4 | Verificar al terminar | Que la cola y la DLQ vuelvan a 0 y no haya facturas duplicadas |

**D. «No hay tráfico»** (alarma `sin-trafico`): el silencio es un síntoma. Revisa en este orden: DNS de Route 53 (¿cambió un registro?), distribución de CloudFront/WAF (¿regla nueva?), certificado vencido, grupo de seguridad del ALB.

**E. «No se pueden subir comprobantes»**: sigue [subida con Claim Check](../subida-claim-check/troubleshooting.md). **«El tablero de clics va atrasado»**: [clickstream](../clickstream/troubleshooting.md).

**F. «Las salidas a Internet fallan a ratos»** (alarma `nat-puertos`): `ErrorPortAllocation` indica agotamiento de puertos de la NAT; busca clientes HTTP sin reutilizar conexiones y destinos concentrados ([NAT en el capítulo de red](../../01-red/diagnostico-conectividad/README.md)).

**G. «Gasto disparado»**: alerta de anomalías y presupuesto ([gobierno y costos](../../09-gobierno/README.md)); busca recursos nuevos en CloudTrail.

### 2.5 Mitigaciones disponibles (de menor a mayor riesgo)

| Mitigación | Cuándo | Riesgo |
|---|---|---|
| Rollback del despliegue | Hubo cambio reciente | Bajo si está probado |
| Escalar (tareas, nodos, tamaño de base) | Saturación | Costo; no arregla bugs |
| Desactivar una función (*feature flag*) | Una función nueva falla | Bajo |
| Limitar tráfico (WAF, API Gateway) | Bots o sobrecarga | Rechaza a algunos clientes |
| Aislar una dependencia (circuit breaker, degradar) | La dependencia falla | Funcionalidad reducida |
| Conmutar a otra región/réplica | Fallo de región | Alto; solo si está ensayado |
| Cambios manuales en producción | **Último recurso** | Muy alto; documentar y regularizar en código |

## 3. Para qué sirve y cuándo NO

| Situación | ¿Runbook? | Nota |
|---|---|---|
| Incidentes repetibles (5xx, cola de fallidos, DNS) | ✅ | Es el 80 % de los casos |
| Una falla totalmente nueva | ⚠️ Orienta, no sustituye al criterio | Se agrega al runbook después |
| Eventos de seguridad (intrusión, credenciales filtradas) | ❌ No es este runbook | Proceso de respuesta de seguridad aparte |
| Pérdida de datos | ❌ | Plan de recuperación ante desastres |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Runbook** | Procedimiento operativo escrito y probado |
| **Incidente** | Evento que degrada o interrumpe el servicio |
| **Mitigar** | Reducir el daño ya (rollback, escalar), sin esperar a entender todo |
| **Causa raíz** | Lo que permitió que ocurriera (se busca después) |
| **MTTD / MTTR** | Tiempo en detectar / en resolver |
| **SLI / SLO** | Medida de calidad (p. ej. % de compras exitosas) / meta (99,9 %) |
| **Alarma por síntoma** | Avisa de lo que sufre el cliente (errores, silencio, lentitud), no de una causa supuesta |
| **Alarma compuesta** | Combina alarmas con `AND/OR/NOT`: una sola página por incidente en vez de siete correos |
| **Sonda sintética** | Comprobación automática que imita lo que ve la aplicación |
| **Postmortem sin culpables** | Análisis centrado en el sistema y las mejoras, no en personas |
| **Acceso de emergencia (*break-glass*)** | Permisos elevados, con aprobación y caducidad, para casos graves |

## 5. Cómo se usa

**Antes (preparación):**
1. Alarmas por **síntoma** con enlace al runbook en la descripción, más una alarma compuesta que pagina ([Terraform](ejemplos/terraform/main.tf)).
2. Panel con las 4 señales: tráfico, errores, latencia, saturación.
3. Consultas de Logs Insights guardadas ([lista](ejemplos/logs-insights/consultas.md)) y un pod de diagnóstico listo ([manifiesto](ejemplos/k8s/pod-diagnostico.yaml)). En ECS, usa ECS Exec sobre una tarea de la misma definición.
4. La sonda dentro de la aplicación ([Java](uso-en-java.md)) y el [informe de ejemplo](ejemplos/json/resultado-sonda.json).
5. **Simulacros trimestrales** («día de juego»): rompe algo en un entorno de prueba y mide cuánto tarda la guardia.

**Durante:** sigue las secciones 2.2–2.5; anota todo con horas.

**Después:** [plantilla de postmortem](ejemplos/plantillas/postmortem.md) en 3 días hábiles; cada acción con responsable y fecha; **actualiza el runbook**.

## 6. Seguridad

| Rol de la guardia | Identidad (quién es) | Plano de control (qué puede cambiar) | Plano de datos (qué puede ver) |
|---|---|---|---|
| Primer nivel | Rol federado de solo lectura, sesión de 1 h | `ViewOnlyAccess`, `CloudWatchReadOnlyAccess`, `AWSCloudTrail_ReadOnlyAccess` | Ninguno |
| Operación (mitigar) | Rol propio, con aprobación | Acciones acotadas: reiniciar, escalar, desplegar la versión anterior | Ninguno por defecto |
| Emergencia (*break-glass*) | Rol elevado con aprobación, motivo y caducidad | Lo que la mitigación exija | Solo si es imprescindible, y queda auditado |

| Riesgo en incidentes | Defensa |
|---|---|
| Pegar secretos o datos de clientes en el chat del incidente | Prohibido; comparte **enlaces** a consultas, no resultados con datos personales |
| Cambios manuales no documentados | El escriba los anota; luego se vuelven código |
| Permisos de emergencia que se quedan | Sesiones cortas y revisión posterior de CloudTrail |
| Endpoint de diagnóstico expuesto | Rol de operaciones y red interna |
| Logs con datos personales | Seudónimos y enmascarado desde el origen |
| Tópico de alertas sin cifrar o abierto | Clave propia con permiso para CloudWatch/EventBridge y política con `aws:SourceArn` |

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Mitigar primero, investigar después | Depurar en caliente con la tienda caída |
| Preguntar «¿qué cambió?» antes que nada | Empezar por la hipótesis favorita |
| Un comandante y un escriba | Diez personas tecleando a la vez |
| Comunicar cada 15–30 min aunque no haya novedades | Silencio hasta tener la causa |
| Alarmas por síntoma con enlace al runbook | Alarmas por causa que nadie entiende |
| Tratar el silencio (cero tráfico) como alarma | Dar por bueno lo que no reporta datos |
| Postmortem sin culpables y con acciones | Buscar a quién culpar |
| Ensayar | Descubrir el runbook roto en pleno incidente |

## 8. Límites, costos y versiones
- **Costo:** cada alarma, alarma compuesta, panel y métrica personalizada tiene precio; **Logs Insights cobra por dato escaneado** y la ingesta de CloudWatch Logs por GB. Acota siempre el tiempo y el grupo de logs (verifica precios).
- **Latencia de las alarmas:** una alarma de 3 de 3 minutos tarda al menos 3 minutos en saltar; ajusta por servicio.
- **CloudTrail `LookupEvents`:** retraso de hasta ~15 min, pocas llamadas por segundo y solo los últimos 90 días de eventos de gestión; para más historial usa el rastro en S3 y Athena.
- **Alarmas con datos faltantes:** elige `treat_missing_data` con intención (`breaching` para el silencio, `notBreaching` para métricas que solo existen cuando hay problema).
- **Retención de logs:** conserva lo suficiente para un postmortem (30–90 días operativos).
- **Versiones:** Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 2.56.0; Terraform con proveedor `aws` 6.x.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
