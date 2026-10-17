# Oracle OCI · Secretos · Vault: secretos (contraseñas, tokens, claves de terceros)

El servicio que guarda **valores que tu aplicación necesita leer**: la contraseña de la base de datos, un token de un proveedor, un certificado. A diferencia de las [llaves](../vault-kms/README.md), aquí el valor **sí sale** (a quien tiene permiso).

## 1. Qué es

**Analogía:** el casillero con llave de un gimnasio. Cada casillero (secreto) guarda algo; solo quien tiene permiso abre el suyo; el gimnasio anota quién abrió cuál; y puedes cambiar el contenido sin que los usuarios cambien de casillero.

```
 App ── GetSecretBundle(secretId, stage=CURRENT) ──► Vault (cifra con tu llave maestra)
     ◄── valor (base64) + versión + etapa
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Secreto** | Contenedor con nombre y OCID; el valor vive en **versiones** |
| **Versión** | Valor inmutable con número; al cambiar el secreto se crea otra |
| **Etapa** (*stage*) | `CURRENT` (la vigente), `PENDING` (lista para pasar a vigente), `LATEST` (la última creada), `PREVIOUS`, `DEPRECATED` |
| **Llave maestra** | La [llave de Vault](../vault-kms/README.md) que cifra el secreto |
| **Reglas** (*secret rules*) | Caducidad del contenido, reutilización de valores, tiempo de vida |
| **Rotación** | Automática con una función que cambia la credencial en el sistema y crea la versión nueva *(verifica el soporte vigente)* |
| **Recuperación** (`Secrets`) | API aparte para leer el valor: `SecretsClient.getSecretBundle` |

### Dos APIs
- **Vaults** (`VaultsClient`): crear, actualizar, programar borrado.
- **Secrets retrieval** (`SecretsClient`): leer el valor (la que usa tu aplicación).

### Etapas y rotación sin caída
1. Creas una versión nueva en `PENDING`.
2. Cambias la credencial real en el sistema destino.
3. Promueves la versión a `CURRENT`; la anterior pasa a `PREVIOUS`.
4. La app que cacheó la anterior **sigue funcionando** hasta renovar: por eso se conserva `PREVIOUS`.

### Contenido
El valor viaja en **base64**; tamaño máximo pequeño *(verifica)*. Para archivos grandes, no es el lugar.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Contraseña de una base o token de un proveedor | Secreto en Vault, leído al arrancar |
| Rotación periódica de credenciales | Versiones + etapas |
| Configuración no sensible | **No**: configuración normal |
| Datos de clientes | **No**: base de datos cifrada |
| Una clave para firmar | Llave de [KMS](../vault-kms/README.md), no un secreto |
| Secretos en variables de entorno de la imagen | **No** |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Secreto** | El casillero |
| **Versión** | Un valor concreto del secreto |
| **Etapa** | Etiqueta del estado de una versión |
| **Bundle** | La respuesta con valor + metadatos |
| **Rotación** | Cambiar el valor sin cortar el servicio |
| **Caché con TTL** | Guardar el valor unos minutos para no llamar siempre |

## 5. Cómo se usa
1. Crea el vault, la llave y el secreto: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Da `read secret-bundles` solo a quien lo necesita ([IAM](../../02-iam/README.md)).
3. Lee con caché y *stale-if-error* desde [Java](uso-en-java.md).
4. Opera con [`ejemplos/cli/secretos.sh`](ejemplos/cli/secretos.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Administrador de seguridad | `manage secret-family` (pocos) | — |
| Aplicación | — | `read secret-bundles` con `where target.secret.id = …` |
| Auditoría | Registros de Audit de cada lectura | — |

- Política **por secreto** (`target.secret.id`), no por compartimento entero.
- **Nunca** registres el valor; ni en excepciones.
- El valor inicial en Terraform queda en el **estado**: cámbialo tras crear y protege el estado.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Leer `CURRENT` con caché corta | Leer en cada petición |
| Rotar con `PENDING` → `CURRENT` | Sobrescribir sin periodo de gracia |
| Un secreto por credencial | Un JSON con todo |
| Política por secreto | `read secret-family` a toda la app |
| Alarma de lecturas anómalas | Sin observabilidad |
| Reintentar con el valor en caché si Vault falla | Caer porque Vault tardó |

## 8. Límites, costos y versiones
- **Costo:** por secreto y por versión activa, más lecturas *(verifica)*.
- **Límites** (verifica): tamaño del valor, secretos por vault, lecturas por segundo.
- **Terraform:** `oci_vault_secret`.
- **SDK:** `SecretsClient` (`oci-java-sdk-secrets`) y `VaultsClient` (`oci-java-sdk-vault`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
