# Google Cloud · Storage · URLs firmadas

Una **URL firmada** da acceso temporal a **un objeto** y **un método** (GET para descargar, PUT para subir) a quien no tiene cuenta de Google Cloud. La firma la hace tu backend con la identidad de una cuenta de servicio (firma V4); Cloud Storage la verifica sin consultarte.

## 1. Qué es

**Analogía:** el código temporal de un casillero. Abre **ese** casillero, para **esa** acción, hasta la hora indicada.

```
 Navegador ─(1) «quiero subir mi foto» ─► backend (decide nombre, tipo, vencimiento)
 Backend ─(2) firma V4 con la SA (IAM signBlob o llave local) ─► URL: https://storage.googleapis.com/<bucket>/fotos/F-1.jpg?X-Goog-Signature=…&X-Goog-Expires=600
 Navegador ─(3) PUT directo con Content-Type: image/jpeg ─► Cloud Storage (bucket privado)
 Evento del bucket ─► validación (ver eventos de Cloud Storage)
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Firma V4** | Algoritmo de firma con vencimiento máximo de 7 días *(verifica)* |
| **Firmante** | Una cuenta de servicio: con llave local (evitar) o mediante **IAM `signBlob`** (sin llaves) |
| **Método** | GET, PUT, POST (formularios), DELETE, HEAD |
| **Cabeceras firmadas** | `Content-Type`, `x-goog-meta-*`, `x-goog-if-generation-match`… que el cliente **debe** enviar igual |
| **Vencimiento** | `X-Goog-Expires` en segundos |
| **CORS del bucket** | Necesario si el navegador sube directo |

### Sin llaves
En Cloud Run o GKE la firma se hace con la API IAM Credentials (`signBlob`) usando la cuenta adjunta; requiere `roles/iam.serviceAccountTokenCreator` **sobre sí misma** *(verifica)*.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Descargar un comprobante desde el navegador | URL GET de 5–15 min |
| Subida directa de fotos | URL PUT a un nombre fijo con `Content-Type` firmado |
| Socio que entrega archivos | URL PUT por archivo (o carpeta del socio con IAM federado) |
| Acceso permanente de un sistema | **No**: IAM |
| Contenido público real | CDN/bucket público dedicado, no URLs largas |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Portador** | Quien tiene la URL tiene el acceso |
| **Firmar sin llave** | Usar `signBlob` de IAM |
| **Cabecera firmada** | Debe coincidir exactamente al usarla |
| **Revocar** | No se puede revocar una URL; acórtala o quita el permiso del firmante |

## 5. Cómo se usa
1. Bucket privado con CORS para subida directa y permiso de firma: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Emisión con reglas (prefijo, método, vencimiento, tipo) desde [Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/firmadas.sh`](ejemplos/cli/firmadas.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Backend firmante | `roles/iam.serviceAccountTokenCreator` sobre su SA (para `signBlob`) | El rol de objetos que delega (`objectViewer`/`objectCreator`) |
| Portador | — | Exactamente lo firmado |

- La URL **no se puede revocar**: vencimientos cortos.
- No registres URLs firmadas.
- Firma con la condición `x-goog-if-generation-match: 0` para que una subida no pise.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| 5–15 minutos | 7 días «por comodidad» |
| Nombre fijado por el backend | Que el cliente elija el objeto |
| `Content-Type` firmado | Aceptar cualquier tipo |
| Firmar con `signBlob` | Llaves JSON para firmar |
| Validar lo subido antes de usarlo | Procesar sin revisar |

## 8. Límites, costos y versiones
- **Costo:** sin cargo por firmar; operaciones y salida normales; `signBlob` tiene cuotas *(verifica)*.
- **Límites:** vencimiento máximo de 7 días con V4.
- **Terraform:** `google_storage_bucket` (`cors`), `google_service_account_iam_member`.
- **Java:** `Storage.signUrl` con `withV4Signature`, `httpMethod`, `withExtHeaders` (`google-cloud-storage`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
