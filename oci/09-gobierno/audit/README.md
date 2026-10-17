# Oracle OCI · Gobierno · Audit

Registro automático, sin costo y siempre activo de **todas las llamadas a la API** de OCI en tu tenancy: quién hizo qué, sobre qué recurso, cuándo, desde qué IP y con qué resultado. Es la caja negra del avión: no evita el accidente, pero explica qué pasó.

## 1. Qué es

**Analogía:** el libro de visitas de la recepción con cámaras. Cada persona que entra firma con nombre, hora, a qué oficina fue y si la dejaron pasar; nadie puede arrancar páginas.

```
 Consola / CLI / SDK / Terraform / servicios ──► API de OCI
                                                     │ cada llamada
                                                     ▼
 Audit (por región, retención 90–365 días)  ──► búsqueda en Logging · Service Connector → Object Storage (años)
   evento: eventName, principalName, ipAddress, resourceName, compartmentName, response.status, eventTime
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Evento de auditoría** | Formato CloudEvents con `data.identity` (quién), `data.request` (qué), `data.response` (resultado) |
| **Retención** | Configurable por tenancy, de 90 a 365 días *(verifica)* |
| **Alcance regional** | Cada región guarda sus eventos; IAM se registra en la región de origen (*home*) |
| **Búsqueda** | Consola de Logging (Audit) o `ListEvents` del API |
| **Service Connector Hub** | Copia continua a Object Storage, Streaming o Logging Analytics |

### Qué registra y qué no
- Sí: operaciones de **plano de control** (crear, modificar, borrar, listar) y muchas de datos de algunos servicios *(verifica)*.
- No: lo que pasa **dentro** de tus apps o bases de datos (para eso, registros de aplicación y auditoría de la base).

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| ¿Quién borró la VM de pagos? | **Audit** |
| Cumplimiento: conservar 7 años de actividad | **Audit** + Service Connector → Object Storage con retención |
| Detectar cambios de políticas fuera de horario | Audit + reglas (o Events / Cloud Guard) |
| ¿Qué SQL ejecutó un usuario? | **No**: auditoría de la base de datos |
| Registros de errores de mi app | **No**: Logging de aplicación |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Principal** | Usuario, grupo dinámico o servicio que llamó |
| **`eventName`** | Operación (`DeletePolicy`, `UpdateBucket`) |
| **Inmutable** | No se puede editar ni borrar desde el tenancy |
| **Región home** | Donde vive IAM y se registran sus cambios |
| **Retención extendida** | Copia propia fuera de Audit |

## 5. Cómo se usa
1. Retención en 365 días y copia continua a un bucket con retención: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Detecta operaciones sensibles fuera de horario o desde IP inesperadas: [uso en Java](uso-en-java.md).
3. Buscar: [`ejemplos/cli/audit.sh`](ejemplos/cli/audit.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Auditoría/seguridad | `read audit-events` en el tenancy | — |
| Administradores | `manage audit` solo para la retención | — |
| Service Connector | Política de servicio hacia el bucket | — |

- El bucket de archivo con **regla de retención** (nadie borra) y acceso mínimo.
- Revisa periódicamente quién puede leer Audit: muestra IPs y nombres.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Retención máxima + copia a Object Storage | Confiar en 90 días para cumplimiento |
| Alertas sobre eventos sensibles | Mirar Audit solo después de un incidente |
| Consultas acotadas por tiempo y compartimento | Pedir 30 días de todo el tenancy de golpe |
| Identidades nominales (no cuentas compartidas) | Un usuario «admin» que usan cinco personas |

## 8. Límites, costos y versiones
- **Costo:** Audit no tiene cargo; la copia en Object Storage y los conectores sí *(verifica)*.
- **Límites** (verifica): retención máxima, ventana de consulta del API, paginación.
- **Terraform:** `oci_audit_configuration`, `oci_sch_service_connector`.
- **SDK:** `AuditClient` (`oci-java-sdk-audit`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
