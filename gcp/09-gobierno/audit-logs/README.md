# Google Cloud · Gobierno · Cloud Audit Logs

Registro de **quién hizo qué, dónde y cuándo** en Google Cloud. Hay cuatro tipos: **Admin Activity** (cambios de configuración, siempre activos y gratis), **Data Access** (lecturas y escrituras de datos, desactivados por defecto salvo BigQuery), **System Event** (acciones de Google) y **Policy Denied** (accesos bloqueados por políticas). Se guardan en buckets de **Cloud Logging** y se pueden enrutar a otro lugar con **sinks**.

## 1. Qué es

**Analogía:** el libro de visitas con cámara de la recepción: registra a cada persona que entra, qué oficina visitó y a qué hora; algunos pisos (datos) solo se registran si lo pides.

```
 Proyecto modalima-tienda-prod
   ├── Admin Activity  ─ SetIamPolicy, compute.instances.insert …   (siempre, 400 días)
   ├── Data Access     ─ secretmanager.versions.access, storage.objects.get (si lo activas)
   ├── System Event    ─ migraciones en vivo de VMs
   └── Policy Denied   ─ violaciones de VPC Service Controls
        │  sink agregado a nivel de organización (incluye hijos)
        ▼
 Proyecto modalima-seguridad: bucket de logs "auditoria" (retención 3 años, bloqueado) + BigQuery para consultas
```

## 2. Cómo funciona por dentro

| Pieza | Qué es |
|---|---|
| **Entrada de auditoría** | `protoPayload` tipo `AuditLog`: `serviceName`, `methodName`, `resourceName`, `authenticationInfo.principalEmail`, `status` |
| **Buckets `_Required` / `_Default`** | `_Required` guarda Admin Activity y System Event 400 días sin costo |
| **Configuración de Data Access** | En la política IAM (`auditConfigs`) por servicio y tipo: `DATA_READ`, `DATA_WRITE`, `ADMIN_READ` |
| **Sinks** | Envían entradas a un bucket de logs, BigQuery, Pub/Sub o Cloud Storage |
| **Sink agregado** | En organización o carpeta, con `include_children` |
| **Bucket bloqueado** | Retención que nadie puede acortar |
| **Log Analytics** | Consultas SQL sobre buckets de logs |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Investigar un cambio en IAM o red | Admin Activity |
| Saber quién leyó un secreto o un objeto sensible | Data Access para ese servicio |
| Cumplimiento con retención larga | Sink agregado a bucket bloqueado |
| Alertas en minutos | Métricas basadas en logs o Eventarc |
| Logs de tu aplicación | Cloud Logging normal, no Audit Logs |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **principalEmail** | Quién actuó (usuario o cuenta de servicio) |
| **methodName** | Qué API llamó |
| **Data Access** | Registros de lectura/escritura de datos (pueden ser muchos) |
| **Sink** | Regla de copia de logs a un destino |
| **Exención** | Identidad excluida de Data Access (con cuidado) |

## 5. Cómo se usa
1. Data Access para Secret Manager, sink agregado y bucket bloqueado: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Construcción de filtros y lectura de entradas de auditoría en [Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/auditoria.sh`](ejemplos/cli/auditoria.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Seguridad | `roles/logging.configWriter` (sinks), `roles/resourcemanager.organizationAdmin` para `auditConfigs` | `roles/logging.privateLogViewer` (Data Access) |
| Auditores | — | `roles/logging.viewer` + `privateLogViewer` en el proyecto de seguridad |
| Cuenta del sink | — | Escritor en el destino (la crea el sink) |

- Los registros de Data Access pueden traer datos sensibles: `privateLogViewer` es otro rol.
- Bucket de destino bloqueado y en un proyecto separado.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Sink agregado en la organización | Configurar proyecto por proyecto |
| Data Access solo donde importa | Activar `allServices` sin calcular el costo |
| Retención bloqueada para cumplimiento | Dejar que los dueños de proyectos borren logs |
| Alertas sobre `SetIamPolicy` y llaves de SA | Revisar logs solo después de un incidente |
| Consultas guardadas para investigaciones | Buscar a mano en la consola |

## 8. Límites, costos y versiones
- **Costo:** Admin Activity y System Event gratis; Data Access y Policy Denied se cobran por ingesta y almacenamiento *(verifica)*.
- **Retención:** `_Required` 400 días; `_Default` 30 días configurables; buckets propios hasta 10 años *(verifica)*.
- **Terraform:** `google_project_iam_audit_config`, `google_logging_organization_sink`, `google_logging_project_bucket_config`.
- **Java:** `google-cloud-logging` (`Logging.listLogEntries`) y `proto-google-cloud-audit` para `AuditLog`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
