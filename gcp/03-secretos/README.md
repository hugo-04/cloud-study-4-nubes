# Google Cloud · 03 Secretos y claves

Dos preguntas que se confunden: **¿dónde guardo un valor que mi app debe leer?** y **¿cómo cifro datos sin que nadie vea la llave?**

| Unidad | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Secret Manager](secret-manager/README.md) | ¿Dónde guardo la contraseña que lee mi app? | Casilleros con llave | Contraseñas, tokens, certificados, rotación |
| [Cloud KMS](cloud-kms/README.md) | ¿Cómo cifro sin exponer la llave maestra? | La caja fuerte que sella sobres | Cifrado de sobre, CMEK, firmas |

## Árbol de decisión: «quiero…»

```
¿Mi app debe LEER un valor sensible (contraseña, token)?  → Secret Manager (IAM por secreto + caché)
¿Debo CIFRAR datos de clientes en mi base o archivos?      → KMS + cifrado de sobre con AAD
¿Que Cloud Storage/BigQuery/Cloud SQL use MI llave?         → CMEK (permiso al agente de servicio)
¿Firmar algo?                                              → Llave asimétrica de firma en KMS
¿Rotar una credencial sin caída?                           → Versiones de Secret Manager + doble validez
¿Es configuración no sensible?                             → Ni uno ni otro
```

## Comparativa

| Característica | Secret Manager | Cloud KMS |
|---|---|---|
| **¿El valor sale del servicio?** | Sí, a quien tiene permiso | Nunca (la llave) |
| **Operación típica** | Leer la versión vigente | Cifrar, descifrar, firmar |
| **Tamaño** | Hasta 64 KiB | Datos pequeños o DEK |
| **Rotación** | Versiones + aviso a Pub/Sub | Versiones primarias automáticas |
| **Rol de datos** | `secretAccessor` | `cryptoKeyEncrypterDecrypter` |
| **Error típico** | Leer en cada petición | `Encrypt` para archivos grandes |

## La receta ModaLima
| Necesidad | Pieza | Por qué |
|---|---|---|
| Contraseña de Cloud SQL | Secreto con rotación y acceso por servicio | Sin contraseñas en imágenes |
| Token de la pasarela de pagos | Secreto con alias `actual` | Cambio controlado |
| Documentos de clientes | Cifrado de sobre con AAD = id del cliente | Sin sustituciones |
| Bucket de documentos | CMEK con llave HSM | Control y auditoría |

## Orden recomendado de adopción
1. Secret Manager para toda credencial; cero secretos en imágenes y repositorios.
2. IAM por secreto y caché en las apps.
3. Proyecto de llaves y CMEK donde lo exija la normativa.
4. Cifrado de sobre para campos sensibles.
5. Rotaciones automatizadas y alertas de acceso anómalo.

## Reglas transversales
- Permisos por recurso (secreto, llave), no por proyecto.
- Nunca registres valores ni llaves.
- El estado de Terraform puede contener secretos: protégelo.
- Destrucciones con espera y revisión.
- Data Access logs activos.

## Java en secretos: qué construye cada `uso-en-java.md`
| Unidad | Qué construyes | Patrón común |
|---|---|---|
| Secret Manager | Caché con TTL y gracia + CRC32C | Reloj inyectable |
| Cloud KMS | Cifrado de sobre AES-GCM con AAD | Envolvedor como interfaz |

## Cómo se relaciona con otros capítulos
- [IAM](../02-iam/README.md): quién lee qué secreto y usa qué llave.
- [Compute](../04-compute/README.md): montaje de secretos en Cloud Run y GKE.
- [Storage](../06-storage/README.md) y [Datos](../08-datos/README.md): CMEK.
- [Gobierno](../09-gobierno/README.md): auditoría de accesos.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos, troubleshooting, repaso y prompt de NotebookLM.
