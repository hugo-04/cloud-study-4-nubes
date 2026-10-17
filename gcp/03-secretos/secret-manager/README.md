# Google Cloud · Secretos · Secret Manager

Almacén administrado de secretos (contraseñas, tokens, certificados) con **versiones**, **IAM por secreto**, replicación automática o por regiones elegidas, cifrado con llaves de Google o propias (CMEK) y **rotación** programada con notificaciones a Pub/Sub.

## 1. Qué es

**Analogía:** casilleros con llave en una oficina. Cada casillero (secreto) guarda sobres numerados (versiones); solo quien tiene permiso sobre **ese** casillero abre el sobre vigente; los sobres viejos se desactivan sin tirarlos de inmediato.

```
 Secreto "db-pedidos-password" (replicación: southamerica-west1 + southamerica-east1, CMEK)
   ├─ versión 3  ENABLED   ← alias "latest" (o un alias propio "actual")
   ├─ versión 2  ENABLED   (se mantiene durante la rotación)
   └─ versión 1  DISABLED / DESTROYED
 Rotación: cada 90 días → mensaje a Pub/Sub → función que crea la versión nueva y cambia la contraseña
 App (cuenta de servicio) ── roles/secretmanager.secretAccessor SOLO en ese secreto ── accessSecretVersion
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Secreto** | Contenedor con política de replicación, etiquetas, rotación y expiración |
| **Versión** | El valor (hasta 64 KiB *(verifica)*); estados `ENABLED`, `DISABLED`, `DESTROYED` |
| **Alias de versión** | Nombre propio (por ejemplo `actual`) que apunta a una versión |
| **Replicación** | Automática (Google elige) o administrada por el usuario (regiones fijas) |
| **Secretos regionales** | Viven en una sola región para residencia de datos *(verifica)* |
| **CMEK** | Cifrado con tu llave de Cloud KMS |
| **Rotación** | Programa que publica en un tema de Pub/Sub; **tú** implementas la rotación |
| **Checksum CRC32C** | Para verificar integridad del valor leído/escrito |

### Lectura
- `accessSecretVersion` de `latest` o de una versión fija.
- Leer en cada petición es caro y lento: **caché con TTL** y tolerancia a fallos.
- En Cloud Run y GKE también puedes **montar** el secreto como variable o archivo (Cloud Run lo resuelve al arrancar o por versión).

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Contraseña de la base, tokens de terceros | **Secret Manager** |
| Configuración no sensible | **No**: variables o archivos de configuración |
| Cifrar datos de clientes | **No**: [Cloud KMS](../cloud-kms/README.md) (cifrado de sobre) |
| Certificados TLS de balanceadores | Certificate Manager (puede apoyarse en secretos) |
| Valores de más de 64 KiB | **No**: guarda un archivo cifrado en Cloud Storage |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **`latest`** | La versión habilitada más reciente |
| **Fijar versión** | Leer siempre la versión N hasta cambiarla a propósito |
| **Rotación sin caída** | Nueva versión + doble validez + cambio + retiro |
| **Accessor** | Rol que permite leer el valor |
| **Destruir** | Borrado irreversible de una versión |

## 5. Cómo se usa
1. Secreto con replicación, rotación y acceso por secreto: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Lectura con caché, gracia ante fallos y verificación CRC32C desde [Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/secretos.sh`](ejemplos/cli/secretos.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `roles/secretmanager.admin` | — |
| Pipeline que crea versiones | `roles/secretmanager.secretVersionAdder` en ese secreto | — |
| App | — | `roles/secretmanager.secretAccessor` **en ese secreto** |
| Auditoría | `roles/secretmanager.viewer` (metadatos, no valores) | Audit Logs de acceso a datos |

- Activa los Data Access logs de Secret Manager para ver cada lectura.
- Acceso por secreto, nunca `secretAccessor` a nivel de proyecto para todas las apps.
- No registres valores ni los pongas en variables visibles de la consola si puedes montarlos.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Caché con TTL y gracia | Leer en cada petición |
| Permiso por secreto | Accessor a nivel de proyecto |
| Rotación con dos versiones válidas | Cambiar la contraseña y la versión a la vez |
| Deshabilitar antes de destruir | Destruir versiones en uso |
| Replicación acorde a tu residencia de datos | Replicación automática sin revisarlo |

## 8. Límites, costos y versiones
- **Costo:** por versión activa al mes y por cada 10.000 operaciones de acceso; notificaciones de rotación *(verifica)*.
- **Límites** (verifica): tamaño de la versión, versiones por secreto, tasa de acceso.
- **Terraform:** `google_secret_manager_secret`, `google_secret_manager_secret_version`, `google_secret_manager_secret_iam_member`.
- **Java:** `SecretManagerServiceClient` (`google-cloud-secretmanager`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
