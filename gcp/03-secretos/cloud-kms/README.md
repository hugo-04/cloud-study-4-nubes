# Google Cloud · Secretos · Cloud KMS

Servicio de **llaves criptográficas** administradas: creas llaves (simétricas, asimétricas, MAC) en **llaveros** por ubicación, con rotación, niveles de protección (software, HSM, externo) y permisos por llave. Las llaves **nunca salen** del servicio: le pides cifrar, descifrar o firmar. También es la base de **CMEK**: que Cloud Storage, BigQuery, Cloud SQL o Pub/Sub cifren con **tu** llave.

## 1. Qué es

**Analogía:** la caja fuerte de un banco con un empleado que sella sobres. No te lleva la llave maestra; le das el sobre y él lo sella o abre frente a ti, y anota cada uso.

```
 Llavero "tienda" (southamerica-west1)
   ├─ llave "datos-clientes"  ENCRYPT_DECRYPT · HSM · rotación 90 días
   │     ├─ versión 3 (primaria)  ← cifra lo nuevo
   │     └─ versiones 1,2         ← siguen descifrando lo viejo
   └─ llave "firma-comprobantes" ASYMMETRIC_SIGN (EC P-256)
 App: genera DEK (AES-256) local → cifra datos → KMS cifra la DEK (wrap) → guarda {datos cifrados + DEK envuelta}
 CMEK: el agente de servicio de Cloud Storage tiene cryptoKeyEncrypterDecrypter sobre la llave
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Llavero (key ring)** | Agrupa llaves en una ubicación; no se puede borrar |
| **Llave (crypto key)** | Propósito: `ENCRYPT_DECRYPT`, `ASYMMETRIC_SIGN`, `ASYMMETRIC_DECRYPT`, `MAC` |
| **Versión** | El material criptográfico; la primaria cifra, las demás solo descifran |
| **Nivel de protección** | `SOFTWARE`, `HSM`, `EXTERNAL` (llave fuera de Google) |
| **Rotación** | Automática para simétricas: nueva versión primaria periódica |
| **Destrucción programada** | Espera configurable antes de destruir (24 h por defecto *(verifica)*) |
| **Autokey** | Crea llaves CMEK automáticamente por proyecto/recurso *(verifica disponibilidad)* |
| **AAD** | Datos asociados que deben coincidir al descifrar (contexto) |

### Cifrado de sobre (envelope)
1. Generas localmente una **DEK** (llave de datos) y cifras los datos con AES-GCM.
2. Pides a KMS cifrar la DEK con la **KEK** (tu llave en KMS).
3. Guardas datos cifrados + DEK envuelta. Para leer: KMS descifra la DEK, tú descifras los datos.
- `Encrypt` directo solo para datos pequeños (hasta 64 KiB *(verifica)*).

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Cifrar campos sensibles (documento, tarjeta tokenizada) | Cifrado de sobre con KMS |
| Que un bucket/BigQuery/Cloud SQL use tu llave | CMEK |
| Firmar comprobantes o JWT internos | Llave asimétrica de firma |
| Guardar una contraseña para leerla | **No**: [Secret Manager](../secret-manager/README.md) |
| Cifrar archivos de GB con `Encrypt` | **No**: cifrado de sobre |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **KEK / DEK** | Llave que cifra llaves / llave que cifra datos |
| **CMEK** | Servicios de Google cifrando con tu llave |
| **Versión primaria** | La que cifra lo nuevo |
| **AAD** | Contexto que ata el cifrado a su uso |
| **Crypto-shredding** | Destruir la llave para volver ilegibles los datos |

## 5. Cómo se usa
1. Llavero, llave HSM con rotación, permisos por llave y CMEK de un bucket: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Cifrado de sobre con AES-GCM y AAD en [Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/kms.sh`](ejemplos/cli/kms.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Admin de llaves | `roles/cloudkms.admin` (sin permisos de uso) | — |
| App | — | `roles/cloudkms.cryptoKeyEncrypterDecrypter` **en esa llave** |
| Agentes de servicio (CMEK) | — | El mismo rol en la llave |
| Firmas | — | `roles/cloudkms.signerVerifier` |

- Separa quién administra de quién usa (separación de funciones).
- Llaves en un **proyecto dedicado** de seguridad.
- Audit Logs de acceso a datos de KMS para ver cada uso.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Cifrado de sobre con AAD | Mandar archivos grandes a `Encrypt` |
| Rotación automática | Una versión eterna |
| Permiso por llave | `cryptoKeyEncrypterDecrypter` en el proyecto |
| Proyecto de llaves separado | Llaves junto a los datos que protegen |
| Revisar antes de destruir | Destruir versiones con datos vivos |

## 8. Límites, costos y versiones
- **Costo:** por versión de llave activa al mes (HSM más caro) y por operaciones *(verifica)*.
- **Límites** (verifica): tamaño de `Encrypt`, operaciones por minuto por llave y por proyecto.
- **Terraform:** `google_kms_key_ring`, `google_kms_crypto_key`, `google_kms_crypto_key_iam_member`.
- **Java:** `KeyManagementServiceClient` (`google-cloud-kms`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
