# Azure

Documentación de estudio de Azure enfocada en **microservicios con Java (Spring Boot y Quarkus)**. Cada servicio vive en su propia carpeta y habla solo de Azure.

## Versiones usadas en los ejemplos

Java 21 · Spring Boot 4.1 · Quarkus 3.40 · Azure SDK BOM 1.3 · msal4j 1.26 · Terraform/OpenTofu (azurerm 4.x, azuread 3.x). Los ejemplos de Terraform se validan con `init` + `validate`; el código Java de la documentación se compila. Lo que depende de versión lleva la nota "verifica en la doc oficial".

## Orden de estudio y estado

| # | Capítulo | Servicios | Estado |
|---|---|---|---|
| 00 | [Fundamentos](00-fundamentos/README.md) | Jerarquía, regiones, costos, CLI, nombres | Listo |
| 01 | [Red](01-red/README.md) | VNet, NSG/rutas/NAT, Private Endpoint+DNS, peering, diagnóstico | Listo |
| 02 | [IAM](02-iam/README.md) | Entra ID, RBAC, Managed Identity, Workload Identity | Listo |
| 03 | [Secretos](03-secretos/README.md) | Key Vault | Listo |
| 04 | [Compute](04-compute/README.md) | App Service, Function Apps, AKS, Container Apps | Listo |
| 05 | [Ingress y API](05-ingress-api/README.md) | Ingress en AKS, Application Gateway, Front Door+WAF, APIM | Listo |
| 06 | [Storage](06-storage/README.md) | Blob Storage, SAS tokens, Claim Check, eventos de blob, Azure Files, Data Lake Gen2 | Listo |
| 07 | Mensajería | Service Bus, Event Grid, Event Hubs (Kafka) | Pendiente |
| 08 | Datos | Azure SQL, PostgreSQL Flexible, Cosmos DB | Pendiente |
| 09 | Gobierno | Azure Policy, locks, management groups, costos | Pendiente |
| 10 | Terraform en Azure | Backend, autenticación, módulos, pipelines | Pendiente |
| 11 | Casos integrados | Arquitecturas de punta a punta | Pendiente |

## Cómo usar cada carpeta de servicio

1. `README.md` → teoría completa.
2. `casos-reales.md` → historias.
3. `uso-en-java.md` → código Spring Boot y Quarkus.
4. `ejemplos/` → CLI y Terraform listos para copiar.
5. `troubleshooting.md` → qué revisar cuando falla.
6. `repaso.md` → autoevaluación.
7. `notebooklm.md` → prompt para generar el video.

Prompt del video de toda la nube: [notebooklm.md](notebooklm.md).
