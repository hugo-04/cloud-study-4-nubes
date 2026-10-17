# Azure · Caso integrado · Runbook de diagnóstico de la tienda

Son las 14:07 de un jueves de campaña y la guardia recibe: **«los clientes no pueden comprar»**. Un *runbook* es el procedimiento escrito, probado y a mano que convierte ese momento de pánico en una secuencia de pasos: **qué mirar primero, cómo decidir, cómo mitigar y a quién avisar**. Este caso reúne lo aprendido en los capítulos de red, IAM, mensajería, datos y gobierno en un solo documento operativo para la tienda de ModaLima (ver [tienda online](../tienda-online/README.md)).

## 1. Qué es

**Analogía:** la lista de verificación de un piloto. No se improvisa en una emergencia: se leen pasos que otros ya ensayaron. Primero **estabilizar** (que el avión siga volando), después **entender** (por qué falló). En un incidente la prioridad es la misma: **mitigar primero, buscar la causa raíz después**.

```
 Alerta / queja ──► 1. Declarar y asignar roles ──► 2. ¿Qué cambió? ──► 3. Acotar la capa ──► 4. Mitigar ──► 5. Confirmar ──► 6. Postmortem
                         (2 min)                      (2 min)           (escalera RPDSI)     (rollback,      (métricas     (sin culpables,
                                                                         + sonda sintética     escalar,         vuelven)       con acciones)
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
| **1** | No se puede comprar o hay pérdida/exposición de datos | Guardia + comandante inmediatos; aviso a gerencia |
| **2** | Degradación seria (lentitud, un medio de pago caído) | Guardia en minutos |
| **3** | Fallo parcial sin impacto directo (cola de fallidos creciendo) | Dentro del horario |

### 2.2 Los primeros cinco minutos (siempre igual)
1. **Declara el incidente** y asigna roles (2 min).
2. **¿Qué cambió?** Despliegues, reglas de red, políticas, rotación de secretos, certificados, picos de tráfico. La mayoría de los incidentes empiezan con un cambio ([`triage.sh`](ejemplos/cli/triage.sh) lo lista).
3. **¿Cuánto y desde cuándo?** Tasa de errores por minuto ([KQL 1](ejemplos/kql/kql-incidente.md)).
4. **¿Qué capa?** Sigue la cadena de abajo.

### 2.3 La cadena de capas (de afuera hacia adentro)

| Capa | Pregunta | Dónde mirar |
|---|---|---|
| Borde (Front Door + WAF) | ¿El WAF bloquea clientes buenos? ¿Origen sano? | Registros del WAF ([KQL 7](ejemplos/kql/kql-incidente.md)); salud del origen |
| APIM | ¿Los 5xx los genera APIM o el backend? ¿Límites de tasa? | Registros del gateway; `GatewayLogs` |
| Ingress / AKS | ¿Pods sanos? ¿Reinicios? ¿Eventos de advertencia? | `kubectl get pods`, eventos ([`triage.sh`](ejemplos/cli/triage.sh)) |
| Aplicación | ¿Qué operación falla? ¿Qué excepción? | [KQL 2 y 4](ejemplos/kql/kql-incidente.md) |
| Dependencias | ¿SQL, Service Bus, Key Vault, Blob, Redis responden? | [KQL 3](ejemplos/kql/kql-incidente.md) + **sonda sintética** |
| Red privada | ¿DNS, ruta, NSG, Private Endpoint? | Escalera [RPDSI](../../01-red/diagnostico-conectividad/README.md) |
| Identidad | ¿401/403? ¿token? ¿rol? | Registros de Entra ID y del servicio |
| Plataforma Azure | ¿Incidente del proveedor? | Resource Health / Service Health |

> **Regla de oro:** un `403` o `401` no es de red; un *timeout* no es de identidad. El síntoma te dice el escalón ([tabla](../../01-red/diagnostico-conectividad/README.md)).

### 2.4 Runbooks por síntoma

**A. «Los clientes ven errores al comprar» (5xx en `POST /api/pedidos`)**

| Paso | Comprobación | Si es así… | Mitigación |
|---|---|---|---|
| 1 | ¿Hubo despliegue en los últimos 60 min? | Sí | **Rollback** a la versión anterior (no depurar en caliente) |
| 2 | ¿Falla una dependencia? ([KQL 3](ejemplos/kql/kql-incidente.md)) | SQL con timeouts | Revisar conexiones/bloqueos; escalar el nivel de la base; limitar tráfico en APIM |
| 3 | ¿La sonda marca DNS/PUERTO en alguna dependencia? | Sí | Seguir la escalera RPDSI; revisar cambios de red recientes |
| 4 | ¿Pods en `CrashLoopBackOff` / `OOMKilled`? | Sí | Revertir; subir límites si es memoria; revisar secretos |
| 5 | Nada de lo anterior | — | Escalar a desarrollo con la traza de una petición fallida ([KQL 5](ejemplos/kql/kql-incidente.md)) |

**B. «La compra va lenta» (p95 alto, sin errores)**

| Paso | Comprobación | Mitigación |
|---|---|---|
| 1 | ¿Qué dependencia tiene el p95 alto? | Escalar esa dependencia o su caché |
| 2 | ¿Redis fuera / caché fría? | Calentar o reiniciar con cuidado; aumentar el tiempo de vida |
| 3 | ¿Nodos sin recursos (CPU/memoria)? | Escalar pods/nodos |
| 4 | ¿Un cliente o bot acapara? | Límite por cliente en APIM / regla de WAF |

**C. «Pedidos creados, sin factura» (bandeja de salida o cola de fallidos creciendo)**

| Paso | Comprobación | Mitigación |
|---|---|---|
| 1 | `bandeja_salida` con filas sin publicar ([esquema](../tienda-online/ejemplos/sql/esquema.sql)) | Revisar el publicador: permisos *Data Sender*, DNS de Service Bus |
| 2 | Mensajes en la DLQ (triage, paso 3) | Leer `DeadLetterReason`; corregir y **reprocesar con procedimiento** |
| 3 | ¿Consumidor reiniciándose? | Revisar excepciones; la lógica debe ser idempotente |
| 4 | Verificar al terminar | Que `pendientes` y DLQ vuelvan a 0 y no haya facturas duplicadas |

**D. «No se pueden subir comprobantes»**: sigue [subida con Claim Check](../subida-claim-check/troubleshooting.md) (SAS, CORS, evento, validador).

**E. «El tablero de clics está en cero o atrasado»**: sigue [clickstream](../clickstream/troubleshooting.md) (limitaciones, partición, grupo de consumidores).

**F. «Gasto disparado»**: alerta de anomalías y presupuesto ([Cost Management](../../09-gobierno/cost-management/README.md)); busca recursos nuevos (registro de actividad, [KQL 8](ejemplos/kql/kql-incidente.md)).

### 2.5 Mitigaciones disponibles (de menor a mayor riesgo)

| Mitigación | Cuándo | Riesgo |
|---|---|---|
| Rollback del despliegue | Hubo cambio reciente | Bajo si está probado |
| Escalar (pods, nodos, nivel de base) | Saturación | Costo; no arregla bugs |
| Desactivar una función (*feature flag*) | Una función nueva falla | Bajo |
| Limitar tráfico (APIM, WAF) | Bots o sobrecarga | Rechaza a algunos clientes |
| Aislar una dependencia (circuit breaker, degradar) | La dependencia falla | Funcionalidad reducida |
| Conmutar a otra región/réplica | Fallo de región | Alto; solo si está ensayado |
| Cambios manuales en producción | **Último recurso** | Muy alto; documentar y regularizar en código |

## 3. Para qué sirve y cuándo NO

| Situación | ¿Runbook? | Nota |
|---|---|---|
| Incidentes repetibles (5xx, cola de fallidos, DNS) | ✅ | Es el 80 % de los casos |
| Una falla totalmente nueva | ⚠️ Orienta, no sustituye al criterio | Se agrega al runbook después |
| Eventos de seguridad (intrusión) | ❌ No es este runbook | Proceso de respuesta de seguridad aparte |
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
| **Sonda sintética** | Comprobación automática que imita lo que ve la aplicación |
| **Postmortem sin culpables** | Análisis centrado en el sistema y las mejoras, no en personas |
| **Acceso de emergencia (*break-glass*)** | Permisos elevados, con aprobación y caducidad, para casos graves |

## 5. Cómo se usa

**Antes (preparación):**
1. Alertas por **síntoma** (no por causa): 5xx, cola de fallidos y sonda, con enlace al runbook ([Terraform](ejemplos/terraform/main.tf)).
2. Panel con las 4 señales: tráfico, errores, latencia, saturación.
3. Pod de diagnóstico listo ([manifiesto](ejemplos/k8s/pod-diagnostico.yaml)) y la sonda en la aplicación ([Java](uso-en-java.md)).
4. **Simulacros trimestrales** («día de juego»): rompe algo en un entorno de prueba y mide cuánto tarda la guardia.

**Durante:** sigue las secciones 2.2–2.5; anota todo con horas.

**Después:** [plantilla de postmortem](ejemplos/plantillas/postmortem.md) en 3 días hábiles; cada acción con responsable y fecha; **actualiza el runbook**.

## 6. Seguridad

| Rol de la guardia | Control (ARM) | Datos |
|---|---|---|
| Guardia de primer nivel | *Reader*, *Monitoring Reader*, *Log Analytics Reader* | Ninguno |
| Operación (mitigar) | Roles personalizados acotados: reiniciar, escalar, desplegar el anterior | Ninguno por defecto |
| Acceso de emergencia | *Contributor* elevado **con aprobación, motivo y caducidad** (acceso privilegiado por solicitud) | Solo si la mitigación lo exige |

| Riesgo en incidentes | Defensa |
|---|---|
| Pegar secretos o datos de clientes en el chat del incidente | Prohibido; compartir **enlaces** a consultas, no resultados con datos personales |
| Cambios manuales no documentados | El escriba los anota; luego se vuelven código |
| Permisos de emergencia que se quedan | Caducidad automática y revisión |
| El endpoint de diagnóstico expuesto | Rol de operaciones, red interna |
| Logs con datos personales | Seudónimos y enmascarado desde el origen |

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Mitigar primero, investigar después | Depurar en caliente con la tienda caída |
| Preguntar «¿qué cambió?» antes que nada | Empezar por la hipótesis favorita |
| Un comandante y un escriba | Diez personas tecleando a la vez |
| Comunicar cada 15–30 min aunque no haya novedades | Silencio hasta tener la causa |
| Alertas por síntoma con enlace al runbook | Alertas por causa que nadie entiende |
| Postmortem sin culpables y con acciones | Buscar a quién culpar |
| Ensayar | Descubrir el runbook roto en pleno incidente |

## 8. Límites, costos y versiones
- **Costo:** cada regla de alerta sobre registros y las métricas tienen precio por regla/evaluación; el mayor gasto es la **ingesta de Log Analytics** (por GB). Muestrea y filtra lo verboso (verifica precios).
- **Retraso:** las alertas basadas en registros tienen latencia de minutos; combínalas con métricas para lo urgente.
- **Retención:** conserva lo suficiente para un postmortem (30–90 días operativos).
- **Versiones:** Java 21, Spring Boot 4.1, Quarkus 3.40; Terraform con `azurerm` 4.x.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
