# Oracle OCI · Secretos · Vault: llaves de cifrado (KMS)

OCI Vault guarda dos cosas distintas: **llaves** (para cifrar) y **secretos** ([otra unidad](../vault-secrets/README.md)). Aquí hablamos de las llaves: el servicio que cifra por ti sin dejarte ver jamás la llave maestra.

## 1. Qué es

**Analogía:** la caja fuerte del banco. Tú le entregas un documento y ella te lo devuelve sellado; **la llave de la caja nunca sale del banco**. Para archivos grandes, la caja te presta una llave pequeña de un solo uso (que sellas tú) y te devuelve la misma llave **envuelta**: solo la caja sabe abrirla.

```
 Tu app ── "dame una llave de datos" ──► Vault (llave maestra, nunca sale)
        ◄── llave en claro (la usas y la olvidas) + llave envuelta (la guardas junto al dato)
 Tu app cifra el dato con AES-GCM localmente
 Para leer: "abre esta llave envuelta" ──► Vault ──► llave en claro ──► descifras
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Vault** | Contenedor de llaves y secretos; tiene dos endpoints (gestión y criptografía) |
| **Tipo de vault** | `DEFAULT` (compartido) o *virtual private* (partición dedicada del HSM) |
| **Llave maestra** (*master encryption key*) | AES, RSA o ECDSA; nunca se exporta |
| **Protección** | `HSM` (hardware certificado) o `SOFTWARE` |
| **Versión de llave** | Cada rotación crea una versión; las anteriores siguen descifrando |
| **Llave de datos** (*DEK*) | Llave AES de un solo uso que generas con Vault |
| **Llave envuelta** | La DEK cifrada con la maestra; se guarda junto al dato |

### Dos endpoints
- **Gestión** (`managementEndpoint`): crear, listar, rotar, programar borrado.
- **Criptografía** (`cryptoEndpoint`): `Encrypt`, `Decrypt`, `GenerateDataEncryptionKey`, firmar.

### Cifrado de sobre (*envelope encryption*)
1. Pides una DEK a Vault: recibes **en claro** y **envuelta**.
2. Cifras el dato **localmente** con AES-GCM.
3. Guardas: llave envuelta + IV + dato cifrado.
4. Para leer: pides a Vault que abra la envuelta y descifras.
Ventajas: no envías datos grandes por la red, y la maestra no sale del servicio.

### Cifrado directo
`Encrypt`/`Decrypt` solo aceptan **datos pequeños** (unos KB; verifica el límite): sirve para cifrar claves o textos cortos, no archivos.

### Rotación y borrado
- **Rotar** crea una versión nueva; lo cifrado antes sigue abriéndose.
- **Borrar** una llave se **programa** (entre 7 y 30 días *(verifica)*): es tu red de seguridad. Lo cifrado con ella queda **irrecuperable** al borrarse.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Cifrar datos sensibles de la aplicación | Envelope encryption con una llave maestra |
| Cifrado del servicio (Object Storage, volúmenes, bases) con tu llave | Llave administrada por ti (CMK) |
| Firmar tokens o documentos | Llave asimétrica de firma |
| Cifrar archivos de GB con `Encrypt` directo | **No**: usa sobre |
| Guardar contraseñas de terceros | **No** aquí: [Secretos](../vault-secrets/README.md) |
| Exportar la llave maestra | No es posible (por diseño) |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Envelope encryption** | Cifras con una llave pequeña, y esa llave la protege la maestra |
| **DEK** | Llave de datos, de un solo uso |
| **Llave maestra** | La que nunca sale del Vault |
| **HSM** | Hardware dedicado a proteger llaves |
| **AAD** | Contexto autenticado: ata el dato cifrado a su identificador |
| **Borrado programado** | Ventana de arrepentimiento antes de borrar |

## 5. Cómo se usa
1. Crea el vault y la llave: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Da permiso `use keys` sobre **esa** llave a quien cifra ([IAM](../../02-iam/README.md)).
3. Implementa el sobre en Java: [`uso-en-java.md`](uso-en-java.md).
4. Opera con la CLI: [`ejemplos/cli/llaves.sh`](ejemplos/cli/llaves.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Administrador de seguridad | `manage keys`, `manage vaults` (pocos) | — |
| Aplicación | — | `use keys` solo sobre su llave (`where target.key.id = …`) |
| Servicios de OCI | — | Política `Allow service objectstorage-<región> to use keys …` |

- **Separa** quien administra llaves de quien las usa.
- **Una llave por aplicación y entorno.**
- **AAD** con el identificador del registro: un dato copiado a otra fila no se descifra.
- Acceso por **red privada** (puerta de servicios) cuando sea posible.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Sobre para datos de aplicación | `Encrypt` directo para archivos |
| HSM para datos sensibles | Software por defecto sin pensarlo |
| Rotación periódica | Una llave eterna |
| Borrado programado con ventana larga | Borrar llaves en uso |
| `use keys` con condición de llave | `manage keys` a la aplicación |
| Guardar la llave envuelta con el dato | Guardar la DEK en claro |

## 8. Límites, costos y versiones
- **Costo:** por versión de llave y por tipo (HSM > software); las operaciones tienen una cuota gratuita *(verifica)*.
- **Límites** (verifica): tamaño de `Encrypt`, peticiones por segundo, llaves por vault.
- **Terraform:** `oci_kms_vault`, `oci_kms_key`.
- **SDK:** `KmsCryptoClient`, `KmsManagementClient`, `KmsVaultClient` (artefacto `oci-java-sdk-keymanagement`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
