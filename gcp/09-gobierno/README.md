# Google Cloud · 09 Gobierno

¿Cómo ordeno, limito, vigilo y pago lo que hay en la nube sin frenar a los equipos?

| Unidad | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Jerarquía y etiquetas](jerarquia-etiquetas/README.md) | ¿Cómo organizo y etiqueto todo? | Organigrama + credencial + centro de costo | Herencia, condiciones, showback |
| [Organization Policy](org-policy/README.md) | ¿Qué configuraciones prohíbo para todos? | Reglamento del edificio | IP pública, regiones, llaves |
| [Cloud Audit Logs](audit-logs/README.md) | ¿Quién hizo qué y cuándo? | Libro de visitas con cámara | Investigación y cumplimiento |
| [Security Command Center](security-command-center/README.md) | ¿Qué está mal configurado o bajo ataque? | Empresa de seguridad | Postura y amenazas |
| [Presupuestos y costos](presupuestos-costos/README.md) | ¿Cuánto gasto, quién y cómo me entero a tiempo? | Tarjeta con SMS | Avisos y reparto |

## Árbol de decisión: «quiero…»

```
¿Agrupar por entorno y que hereden reglas?          → Carpetas + tags (jerarquía)
¿Impedir una configuración aunque tengan permisos?   → Organization Policy (dry run primero)
¿Saber quién cambió algo?                            → Audit Logs (Admin Activity)
   └─ ¿Quién leyó un dato?                           → Data Access activado en ese servicio
¿Detectar lo que ya está mal o un ataque?            → Security Command Center
¿Avisos y reparto de costos?                         → Presupuestos + exportación a BigQuery
```

## Comparativa

| Característica | Jerarquía/tags | Org Policy | Audit Logs | SCC | Presupuestos |
|---|---|---|---|---|---|
| **Momento** | Diseño | Prevención | Registro | Detección | Seguimiento |
| **Bloquea** | No (organiza) | Sí | No | No | No |
| **Alcance** | Organización | Jerarquía | Proyecto/organización | Organización | Cuenta de facturación |
| **Costo** | Sin cargo | Sin cargo | Data Access cobra | Según nivel | Sin cargo |
| **Error típico** | Roles arriba | Sin dry run | Sin Data Access | Fatiga de alertas | Solo al 100 % |

## La receta ModaLima
| Necesidad | Pieza | Por qué |
|---|---|---|
| Separar prod/no-prod | Carpetas + tag `entorno` | Herencia |
| Nada público | `sql.restrictPublicIp`, `storage.publicAccessPrevention`, `vmExternalIpAccess` | Barandas |
| Evidencia | Sink agregado a bucket bloqueado | Inmutable |
| Alertas de seguridad | SCC críticos → Pub/Sub → triaje | Prioridad |
| Costos | Presupuesto por proyecto + exportación + labels | Showback |

## Orden recomendado de adopción
1. Jerarquía y tags antes del primer proyecto.
2. Línea base de Org Policy (con dry run).
3. Sink agregado de auditoría.
4. Presupuestos y exportación.
5. SCC con notificaciones de lo crítico.

## Reglas transversales
- Todo como código y revisado.
- Prevenir > detectar > corregir.
- Decisiones de seguridad con tags, no labels.
- La evidencia vive fuera del alcance de los equipos.
- Cada alerta tiene dueño y plazo.

## Java en gobierno: qué construye cada `uso-en-java.md`
| Unidad | Qué construyes | Patrón común |
|---|---|---|
| Jerarquía y etiquetas | Validador de labels y tags efectivos | Auditoría de lectura |
| Org Policy | Línea base vs política efectiva | Comparación pura |
| Audit Logs | Filtros escapados y lectura de AuditLog | `protoPayload` desempaquetado |
| SCC | Triaje con SLA | Orden por vencimiento |
| Presupuestos | Reacción idempotente y costo por equipo | Parámetros en SQL |

## Cómo se relaciona con otros capítulos
- [IAM](../02-iam/README.md): condiciones con tags y políticas de denegación.
- [Mensajería](../07-mensajeria/README.md): Eventarc sobre Audit Logs y Pub/Sub de alertas.
- [Datos](../08-datos/README.md): restricciones de IP pública.
- [Terraform](../10-terraform/README.md): todo esto como código.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos, troubleshooting, repaso y prompt de NotebookLM.
