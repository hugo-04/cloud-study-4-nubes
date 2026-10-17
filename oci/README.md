# Oracle OCI

Documentación de estudio de Oracle Cloud Infrastructure enfocada en **microservicios con Java (Spring Boot y Quarkus)**. Cada servicio vive en su propia carpeta y habla solo de OCI.

## Versiones usadas en los ejemplos

Java 21 · Spring Boot 4.1 · Quarkus 3.40 · OCI SDK for Java 3.97 · Terraform/OpenTofu con proveedor `oracle/oci`. Los ejemplos de Terraform se validan con `init` + `validate`; el código Java se compila contra el SDK real. *Verifica versiones vigentes.*

## Orden de estudio y estado

| # | Capítulo | Servicios | Estado |
|---|---|---|---|
| 00 | [Fundamentos](00-fundamentos/README.md) | Tenancy, compartimentos, regiones, AD/FD, OCID, autenticación, costos | Listo |
| 01 | [Red](01-red/README.md) | VCN y subredes, listas de seguridad/NSG/rutas, DRG y peering, Service Gateway + endpoints privados + DNS, diagnóstico | Listo |
| 02 | [IAM](02-iam/README.md) | Compartimentos y políticas, identity domains, grupos dinámicos, workload identity en OKE | Listo |
| 03 | [Secretos y claves](03-secretos/README.md) | Vault: llaves de cifrado (KMS) y Vault: secretos | Listo |
| 04 | [Compute](04-compute/README.md) | VM, OKE, Functions, Container Instances | Listo |

## Cómo usar cada carpeta de servicio

1. `README.md` → teoría completa.
2. `casos-reales.md` → historias.
3. `uso-en-java.md` → código Spring Boot y Quarkus.
4. `ejemplos/` → CLI y Terraform listos para copiar.
5. `troubleshooting.md` → qué revisar cuando falla.
6. `repaso.md` → autoevaluación.
7. `notebooklm.md` → prompt para generar el video.

Prompt del video de toda la nube: [notebooklm.md](notebooklm.md).
