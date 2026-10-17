# Oracle OCI · Caso integrado · Runbook de diagnóstico de la tienda

Son las 21:07 del Cyber y llegan alertas: el checkout de ModaLima responde lento y con errores. Este caso es el **método** para atender el incidente: roles, los primeros cinco minutos, la cadena de capas de afuera hacia adentro, runbooks por síntoma, mitigaciones de menor a mayor riesgo y el *postmortem*.

## 1. Qué es

**Analogía:** el protocolo de una sala de emergencias. Hay un coordinador, alguien que habla con la familia y médicos que examinan en orden: vía aérea, respiración, circulación. Nadie opera antes de estabilizar.

```
 Alarmas por síntoma (Monitoring) ─► Notifications ─► guardia (correo/PagerDuty)
 Sonda sintética (cada minuto)    ─┘
 Triage automático (Java): recorre las capas y dice cuál falla primero
   1 DNS/WAF ─► 2 Load Balancer ─► 3 Ingress/pods ─► 4 dependencias (ATP, Cache, Queue) ─► 5 cambios recientes (Audit)
```

## 2. Cómo funciona por dentro

### 2.1 Roles y severidad
| Rol | Hace |
|---|---|
| **Coordinador** | Decide, prioriza, pide ayuda; no teclea |
| **Comunicación** | Informa a negocio y atención al cliente cada 15–30 min |
| **Operadores** | Diagnostican y aplican mitigaciones acordadas |
| **Escriba** | Línea de tiempo de hechos y decisiones |

| Severidad | Criterio |
|---|---|
| SEV1 | Checkout caído o errores > 5 % |
| SEV2 | Degradación visible (latencia p95 > 2 s) |
| SEV3 | Problema interno sin impacto al cliente |

### 2.2 Los primeros cinco minutos (siempre igual)
1. Declarar el incidente, asignar coordinador y canal.
2. Confirmar el impacto con la sonda y las métricas del LB (no con suposiciones).
3. Preguntar: **¿qué cambió?** (despliegues, Terraform, Audit de la última hora).
4. Correr el triage de capas.
5. Elegir la mitigación de menor riesgo.

### 2.3 La cadena de capas (de afuera hacia adentro)
| Capa | Mira | Herramienta |
|---|---|---|
| 1 DNS/WAF | Resolución, bloqueos del WAF | Registros del WAF |
| 2 Load Balancer | 5xx, salud de backends | Métricas `oci_lbaas`, `backend-set-health` |
| 3 Ingress/pods | Readiness, reinicios, CPU/memoria | `kubectl`, métricas de OKE |
| 4 Dependencias | Sesiones de ATP, latencia de Cache, DLQ | Performance Hub, métricas |
| 5 Cambios | Despliegues y Audit | Audit, historial del pipeline |

### 2.4 Runbooks por síntoma
| Síntoma | Primeros pasos |
|---|---|
| 502 masivos | Salud del backend set → readiness → últimos despliegues |
| 504 / lentitud | Latencia de ATP y Cache → pools agotados → consultas top |
| 429 | WAF/API Gateway: ¿ataque o límite mal puesto? |
| Pedidos sin factura | Outbox pendiente → relay → cola/DLQ |
| Todo bien pero clientes se quejan | Sonda desde fuera, DNS, certificados |

### 2.5 Mitigaciones disponibles (de menor a mayor riesgo)
1. Revertir el último despliegue.
2. Escalar réplicas o nodos.
3. Desactivar una función no esencial (bandera).
4. Drenar un backend o zona problemática.
5. *Failover* de base de datos (Data Guard).

## 3. Para qué sirve y cuándo NO
| Situación | Decisión |
|---|---|
| Incidentes de producción | **Este runbook** |
| Problemas de rendimiento lentos y crónicos | Análisis planificado, no modo incidente |
| Fallos de una dependencia externa (pasarela de pago) | Runbook propio con su proveedor |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Alarma por síntoma** | Alerta sobre lo que siente el cliente (errores, latencia) |
| **Sonda sintética** | Un «cliente robot» que prueba el flujo cada minuto |
| **MTTR** | Tiempo medio de recuperación |
| **Postmortem sin culpables** | Analizar el sistema, no a las personas |
| **SLO** | Objetivo de servicio (por ejemplo 99,9 % sin error) |

## 5. Cómo se usa
1. Alarmas por síntoma sobre el LB y tema de guardia: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Triage de capas automático en Java: [uso en Java](uso-en-java.md).
3. Comandos de los primeros cinco minutos: [`ejemplos/cli/primeros-5-minutos.sh`](ejemplos/cli/primeros-5-minutos.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Guardia | `read` de métricas, LB, OKE, Audit; `use` para mitigar (drenar, escalar) | — |
| Triage automático | `read metrics`, `read load-balancers` | — |
| Acceso de emergencia | Grupo *break-glass* con MFA y alerta al usarse | — |

- Las mitigaciones también quedan en Audit.
- No compartas credenciales en el canal del incidente.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Alarmar por síntomas del cliente | Alarmar por cada CPU al 80 % |
| Preguntar «qué cambió» primero | Depurar código en producción |
| Mitigar antes de entender del todo | Buscar la causa raíz con el sitio caído |
| Línea de tiempo durante el incidente | Reconstruirla de memoria |
| Postmortem con acciones y dueños | Cerrar el incidente sin aprender |

## 8. Límites, costos y versiones
- **Costo:** alarmas, métricas y notificaciones con costos bajos *(verifica)*.
- **Límites** (verifica): resolución mínima de métricas, alarmas por tenancy.
- **Terraform:** `oci_monitoring_alarm`, `oci_ons_notification_topic`.
- **SDK:** `MonitoringClient` (`summarizeMetricsData`), `LoadBalancerClient`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
