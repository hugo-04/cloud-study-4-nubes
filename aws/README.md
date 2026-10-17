# AWS

Documentación de estudio de AWS enfocada en **microservicios con Java (Spring Boot y Quarkus)**. Cada servicio vive en su propia carpeta y habla solo de AWS.

## Versiones usadas en los ejemplos

Java 21 · Spring Boot 4.1 · Quarkus 3.40 (con extensiones Quarkiverse Amazon Services) · AWS SDK for Java v2 (BOM 2.56) · Terraform/OpenTofu con proveedor `aws` 6.x. Los ejemplos de Terraform se validan con `init` + `validate`; el código Java de la documentación se compila. Lo que depende de versión lleva la nota "verifica en la doc oficial".

## Orden de estudio y estado

| # | Capítulo | Servicios | Estado |
|---|---|---|---|
| 00 | [Fundamentos](00-fundamentos/README.md) | Cuentas, regiones y AZ, IAM básico, costos, CLI, nombres, ARN | Listo |
| 01 | [Red](01-red/README.md) | VPC y subredes, SG/NACL/rutas/NAT, VPC Endpoints + PrivateLink + Route 53, peering + Transit Gateway, diagnóstico | Listo |
| 02 | [IAM](02-iam/README.md) | Roles y políticas, IAM Identity Center, STS (asumir roles), IRSA y Pod Identity | Listo |
| 03 | [Secretos](03-secretos/README.md) | Secrets Manager, KMS, Parameter Store | Listo |
| 04 | [Compute](04-compute/README.md) | ECS Fargate, ECS Express Mode, EKS, Lambda | Listo |
| 05 | [Ingress y API](05-ingress-api/README.md) | ALB/NLB, API Gateway, CloudFront + WAF, Ingress en EKS | Listo |
| 06 | [Storage](06-storage/README.md) | S3, URLs prefirmadas, Claim Check, eventos de S3, EFS | Listo |
| 07 | [Mensajería](07-mensajeria/README.md) | SQS, SNS, EventBridge, Kinesis Data Streams, MSK (Kafka) | Listo |
| 08 | [Datos](08-datos/README.md) | RDS / Aurora, DynamoDB, ElastiCache (Redis) | Listo |
| 09 | [Gobierno](09-gobierno/README.md) | Organizations + SCP, Config, CloudTrail, Budgets / Cost Explorer | Listo |
| 10 | [Terraform en AWS](10-terraform/README.md) | Estado remoto (S3), autenticación y pipelines (OIDC), módulos y entornos | Listo |
| 11 | [Casos integrados](11-casos-integrados/README.md) | Cinco sistemas completos: tienda con eventos, subida con Claim Check, clickstream, landing zone y runbook de diagnóstico | Listo |

## Cómo usar cada carpeta de servicio

1. `README.md` → teoría completa.
2. `casos-reales.md` → historias.
3. `uso-en-java.md` → código Spring Boot y Quarkus.
4. `ejemplos/` → CLI y Terraform listos para copiar.
5. `troubleshooting.md` → qué revisar cuando falla.
6. `repaso.md` → autoevaluación.
7. `notebooklm.md` → prompt para generar el video.

Prompt del video de toda la nube: [notebooklm.md](notebooklm.md).
