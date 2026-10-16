# Cloud Study · 4 Nubes

Repo **privado de estudio** para entender, de cero a nivel intermedio, los servicios clave de **Azure** y su equivalente en **AWS**, **Oracle Cloud (OCI)** y **Google Cloud (GCP)**.

> Los casos de vida real son **inventados y genéricos**. Este repo no debe contener datos de ningún cliente, empresa, cuenta ni credenciales reales.

## Módulos

| # | Módulo | Qué cubre | Estado |
|---|---|---|---|
| 00 | [Fundamentos](00-fundamentos/README.md) | Qué es la nube, IaaS/PaaS, regiones, jerarquías, responsabilidad compartida, costos, glosario | Listo |
| 01 | [Networking](01-networking/README.md) | VNet/VPC/VCN, subnets, NSG, rutas, NAT, peering, Private Endpoint, DNS privado, híbrido | Listo |
| 02 | [Comunicación privada y diagnóstico](02-comunicacion-privada-y-diagnostico/README.md) | Políticas de comunicación entre servicios, AKS y APIM en red privada, qué revisar cuando algo no conecta | Listo |
| 03 | [IAM y seguridad](03-iam-seguridad/README.md) | Entra ID, RBAC, Managed Identity, políticas IAM en las 4 nubes | Listo |
| 04 | [Secretos y claves](04-secretos-y-claves/README.md) | Key Vault, Secrets Manager, OCI Vault, Secret Manager | Listo |
| 05 | [Compute](05-compute/README.md) | App Service, Function Apps, AKS y equivalentes | Listo |
| 06 | [Ingress y API](06-ingress-y-api/README.md) | Ingress en AKS, Application Gateway, APIM y equivalentes | Listo |
| 07 | [Storage](07-storage/README.md) | Blob Storage, SAS tokens / Presigned URL / PAR / Signed URL, patrón Claim Check | Listo |
| 08 | [Mensajería y streaming](08-mensajeria-y-streaming/README.md) | Colas, tópicos y equivalentes de Kafka (Event Hubs, MSK, OCI Streaming, Pub/Sub) | Listo |
| 09 | [Bases de datos](09-bases-de-datos/README.md) | Azure SQL, PostgreSQL, Cosmos DB y equivalentes | Listo |
| 10 | [Políticas y gobierno](10-politicas-y-gobierno/README.md) | Azure Policy, SCP, Security Zones, Organization Policy, costos | Listo |
| 11 | [Terraform (IaC)](11-terraform-iac/README.md) | Providers, state remoto, módulos, pipelines con OIDC y un laboratorio equivalente en las 4 nubes (`ejemplos/`) | Listo |
| 12 | [Casos integrados](12-casos-integrados/README.md) | Arquitecturas de punta a punta, Claim Check, runbook de incidentes, checklist de producción y plan de 8 semanas | Listo |
| 99 | [Prompts NotebookLM](99-prompts-notebooklm/prompts.md) | Prompts para generar videos de cada módulo | Listo |

## Orden recomendado

`00 → 01 → 02 → 03 → 04 → 05 → 06 → 07 → 08 → 09 → 10 → 11 → 12`

Red e identidad van primero porque casi todo error "raro" en la nube es de DNS, red o permisos.

## Cómo estudiar cada módulo

1. Lee el README del módulo (ya trae analogías, casos y qué hacer / qué no hacer).
2. Haz los labs pequeños. Siempre termina con el comando de limpieza.
3. Responde las preguntas de repaso sin mirar.
4. Sube el módulo a NotebookLM y genera el video con el prompt de `99-prompts-notebooklm`.

## Cada servicio sigue la misma plantilla

Ver [PLANTILLA-SERVICIO.md](PLANTILLA-SERVICIO.md): analogía, para qué sirve y cuándo no, casos reales, cómo se usa, qué hacer y qué no, equivalencias en las 4 nubes, IAM y políticas, troubleshooting y preguntas de entrevista.

## Reglas de seguridad del repo

- Nada de secretos, claves, tokens, connection strings ni IDs reales de suscripción o cuenta.
- Los ejemplos usan nombres inventados (`ModaLima`, `Café Andino`) y rangos IP de ejemplo.
- `.gitignore` ya excluye `*.tfstate`, `*.tfvars`, `.env` y llaves.
- Costos: usa créditos o free tier, crea un presupuesto con alerta y borra los recursos al terminar. Las condiciones de cada nube cambian, así que revísalas antes de empezar.

## Nota de vigencia

Los servicios cambian rápido (tiers, límites, flags de CLI, fechas de retiro). Lo que sea sensible a versión está marcado con "verifica en la doc oficial". Contenido revisado en octubre de 2026.

## Subir a GitHub como repo privado

Con GitHub CLI:

```bash
cd cloud-study-4-nubes
git init -b main
git add .
git commit -m "Estructura inicial del repo de estudio"
gh repo create cloud-study-4-nubes --private --source=. --remote=origin --push
```

Sin GitHub CLI: crea el repo vacío y privado en github.com y luego:

```bash
git remote add origin git@github.com:hugo-04/cloud-study-4-nubes.git
git push -u origin main
```
