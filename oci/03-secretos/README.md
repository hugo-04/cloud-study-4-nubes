# Oracle OCI · 03 Secretos y claves

Dos cosas se confunden mucho: **cifrar** y **guardar un valor para leerlo después**. En OCI Vault conviven, pero responden preguntas distintas.

| Unidad | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Vault: llaves (KMS)](vault-kms/README.md) | ¿Cómo **cifro** sin que nadie vea la llave maestra? | La caja fuerte del banco | Cifrado de sobre, llaves de servicios (CMK), firmas |
| [Vault: secretos](vault-secrets/README.md) | ¿Dónde guardo la **contraseña** que mi app debe leer? | El casillero con llave | Contraseñas, tokens, certificados, rotación |

## Árbol de decisión: «quiero…»

```
¿Quiero que mi app lea una contraseña o un token?
   └─ Secreto en Vault (política por secreto, caché con TTL)

¿Quiero cifrar datos de clientes en mi base o en archivos?
   └─ Cifrado de sobre con una llave maestra (HSM si es sensible)

¿Quiero que Object Storage, volúmenes o bases usen MI llave?
   └─ Llave en Vault + política de servicio (use keys)

¿Quiero rotar una credencial sin caída?
   └─ Secreto con versiones: PENDING → CURRENT, conserva PREVIOUS

¿Quiero firmar algo?
   └─ Llave asimétrica de firma en KMS

¿Es configuración que no es sensible?
   └─ Configuración normal, no Vault
```

## Comparativa

| Característica | Llave (KMS) | Secreto |
|---|---|---|
| **¿El valor sale del servicio?** | Nunca (la maestra) | Sí, a quien tiene permiso |
| **Operación típica** | Cifrar, descifrar, firmar | Leer la versión vigente |
| **Tamaño** | Datos pequeños (o sobre) | Valores pequeños |
| **Rotación** | Versiones de llave | Versiones y etapas |
| **Permiso de datos** | `use keys` | `read secret-bundles` |
| **Error típico** | `Encrypt` para archivos grandes | Leer en cada petición |

## La receta ModaLima
| Necesidad | Pieza | Por qué |
|---|---|---|
| Contraseña de la base de pedidos | Secreto + política por secreto + caché | Rotación sin caída |
| Tarjeta tokenizada guardada | Cifrado de sobre con llave HSM | La maestra nunca sale |
| Bucket de comprobantes cifrado con llave propia | CMK + política de servicio | Control y auditoría |
| Token de la pasarela de pago | Secreto con rotación trimestral | Reglas de caducidad |

## Orden recomendado de adopción
1. Un vault por entorno (o por frontera de seguridad).
2. Secretos para toda credencial; cero contraseñas en imágenes o repositorios.
3. Caché con TTL y *stale-if-error* en las aplicaciones.
4. Llaves propias para datos sensibles y cifrado de sobre.
5. Rotación con etapas; alarmas ante lecturas anómalas.
6. Todo como código, con el estado protegido.

## Reglas transversales
- Política **por recurso** (`target.secret.id`, `target.key.id`).
- Nunca registres valores ni llaves.
- El estado de Terraform es un secreto más.
- Borrado de llaves **programado** y revisado.
- Acceso por red privada cuando sea posible.

## Java en secretos: qué construye cada `uso-en-java.md`
| Unidad | Qué construyes | Patrón común |
|---|---|---|
| Llaves | Cifrado de sobre AES-GCM con contexto (AAD) y `KmsCryptoClient` | Núcleo puro + adaptador del SDK |
| Secretos | Caché con TTL y gracia + `SecretsClient` | Reloj inyectable; fuente intercambiable |

## Cómo se relaciona con otros capítulos
- [IAM](../02-iam/README.md): quién puede usar la llave o leer el secreto.
- [Red](../01-red/README.md): puerta de servicios o NAT hacia Vault.
- [Compute](../04-compute/README.md): pods, funciones y VM leen secretos al arrancar.
- [Storage](../06-storage/README.md): cifrado de buckets con tu llave.
- [Datos](../08-datos/README.md): contraseñas y cifrado de bases.
- [Gobierno](../09-gobierno/README.md): auditoría de cada lectura.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos, troubleshooting, repaso y prompt de NotebookLM.
