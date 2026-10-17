# Google Cloud · Gobierno · Security Command Center

Centro de **postura y detección de amenazas** de Google Cloud: inventaria activos, detecta **configuraciones inseguras** (Security Health Analytics: buckets públicos, firewalls abiertos, llaves de SA), **vulnerabilidades** (Web Security Scanner, imágenes de contenedor), **amenazas** (Event Threat Detection sobre logs, Container Threat Detection en GKE) y, en niveles superiores, simula **rutas de ataque** y evalúa cumplimiento. Todo aparece como **hallazgos** (*findings*).

## 1. Qué es

**Analogía:** la empresa de seguridad del edificio: rondas (escáneres de configuración), cámaras con alertas (detección de amenazas) y un informe de puertas mal cerradas ordenado por gravedad.

```
 Organización ModaLima (SCC Standard / Premium / Enterprise — verifica niveles)
   ├── Security Health Analytics  → PUBLIC_BUCKET_ACL, OPEN_FIREWALL, SERVICE_ACCOUNT_KEY_NOT_ROTATED
   ├── Event Threat Detection     → Persistence: IAM anomalous grant, Malware: bad domain
   ├── Container Threat Detection → Added binary executed (GKE)
   └── Vulnerabilidades            → CVE en imágenes, XSS en apps
        │ hallazgos (state ACTIVE, severity CRITICAL…LOW, mute)
        ▼
 Notificación continua → Pub/Sub → Cloud Run "triaje" → ticket / chat
```

## 2. Cómo funciona por dentro

| Pieza | Qué es |
|---|---|
| **Niveles** | Standard (básico), Premium y Enterprise (más detectores, rutas de ataque, cumplimiento) *(verifica)* |
| **Fuentes** | Detectores de Google y de terceros que escriben hallazgos |
| **Hallazgo** | Categoría, severidad, estado, recurso, hora del evento, clase (amenaza, vulnerabilidad, mala configuración) |
| **Mute** | Silenciar hallazgos aceptados con reglas (con justificación) |
| **Exportación continua** | A Pub/Sub o BigQuery |
| **Postura** | Conjuntos de políticas y detectores personalizados *(verifica)* |
| **Valor de recursos** | Prioriza según lo que importa (Premium/Enterprise) |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Ver de un vistazo buckets públicos y firewalls abiertos | SCC (Security Health Analytics) |
| Detectar una concesión de IAM anómala | Event Threat Detection |
| Enviar hallazgos críticos al equipo en minutos | Notificación a Pub/Sub |
| Prevenir la configuración en primer lugar | [Org Policy](../org-policy/README.md) |
| Saber quién hizo un cambio | [Audit Logs](../audit-logs/README.md) |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Finding** | Un problema detectado en un recurso |
| **Severidad** | CRITICAL, HIGH, MEDIUM, LOW |
| **Clase** | Amenaza, vulnerabilidad, mala configuración, observación |
| **Mute** | Aceptado o falso positivo, con regla |
| **SLA de remediación** | Plazo según severidad |

## 5. Cómo se usa
1. Notificación de hallazgos críticos a Pub/Sub y regla de mute: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Triaje con SLA por severidad en [Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/scc.sh`](ejemplos/cli/scc.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Seguridad | `roles/securitycenter.admin` | — |
| Triaje | `roles/securitycenter.findingsEditor` (estado, mute) | — |
| Lectores | `roles/securitycenter.findingsViewer` | — |

- Hallazgos de amenazas pueden revelar detalles sensibles: lectores limitados.
- Mute siempre por regla y con justificación; nunca masivo.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| SLA por severidad y dueño por proyecto | Un tablero que nadie mira |
| Notificaciones solo de lo crítico/alto | Mandar todo al chat |
| Mute con regla y revisión periódica | Silenciar por cansancio |
| Corregir la causa con Org Policy | Arreglar a mano el mismo hallazgo cada semana |
| Exportar a BigQuery para tendencias | Medir solo el conteo del día |

## 8. Límites, costos y versiones
- **Costo:** Standard sin cargo; Premium/Enterprise por suscripción o consumo según activos *(verifica)*.
- **Límites** (verifica): reglas de mute, configuraciones de notificación por organización.
- **Terraform:** `google_scc_v2_organization_notification_config`, `google_scc_v2_organization_mute_config`.
- **Java:** `google-cloud-securitycenter` (`v2.SecurityCenterClient.listFindings`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
