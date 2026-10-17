# Azure · 11 Casos integrados

Los capítulos anteriores explican cada servicio por separado. Este capítulo los **junta** en cinco situaciones reales de punta a punta, para ver cómo encajan, dónde se rompen y qué decisiones se toman entre servicios. Las empresas son ficticias (ModaLima y Café Andino); los problemas, no.

| Caso | La pregunta que responde | Servicios que se combinan | Lo que te llevas |
|---|---|---|---|
| [Tienda online](tienda-online/README.md) | ¿Cómo guardo un pedido **y** aviso a otros sin perder ni duplicar nada? | Front Door + WAF, APIM, AKS, Azure SQL, Redis, Service Bus, Blob, Key Vault, Private Endpoint | Bandeja de salida y de entrada, idempotencia, red privada, permisos por servicio |
| [Subida con Claim Check](subida-claim-check/README.md) | ¿Cómo dejo que los usuarios suban archivos grandes sin que pasen por mi API ni se usen sin revisar? | Blob (cuarentena y validados), SAS de delegación, Event Grid, Storage Queues, Service Bus, SQL | Máquina de estados, validación por bytes, conciliador, limpieza automática |
| [Clickstream](clickstream/README.md) | ¿Cómo analizo miles de eventos por segundo en vivo y de forma exacta después? | Event Hubs (Capture), Data Lake Gen2, Redis, Key Vault | Dimensionar con números, clave de partición, ventanas, privacidad |
| [Landing zone](landing-zone/README.md) | ¿Cómo entrego a cada equipo un espacio ya listo, seguro y sin solapamientos? | Grupos de administración, Policy, RBAC, VNet + peering, Cost Management, bloqueos, Terraform | Subscription vending, asignación de redes, verificador de la zona |
| [Runbook de diagnóstico](runbook-diagnostico/README.md) | ¿Qué hago cuando «los clientes no pueden comprar»? | Monitor, Log Analytics, Application Insights, escalera RPDSI, AKS, Service Bus | Primeros cinco minutos, runbooks por síntoma, sonda sintética, postmortem |

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos (Terraform, CLI, SQL, JSON, consultas), troubleshooting, repaso y prompt de NotebookLM.

## Árbol de decisión: «quiero construir…»

```
¿Dos sistemas deben enterarse de lo mismo sin perder ni duplicar?  ──► Tienda online (bandeja de salida/entrada + Service Bus)
¿Los usuarios suben archivos?                                      ──► Subida con Claim Check (SAS corta + cuarentena + validación)
¿Hay un flujo constante de eventos pequeños para analizar?         ──► Clickstream (Event Hubs + Capture)
¿Habrá varios equipos y entornos que deben cumplir las mismas reglas? ──► Landing zone (jerarquía + políticas + módulo de suscripción)
¿Algo falla en producción y hay que actuar ya?                     ──► Runbook de diagnóstico
```

## Los cinco casos y los capítulos que usan

| Capítulo | Tienda | Subida | Clickstream | Landing zone | Runbook |
|---|:--:|:--:|:--:|:--:|:--:|
| [00 Fundamentos](../00-fundamentos/README.md) | ● | ● | ● | ● | ● |
| [01 Red](../01-red/README.md) | ● | ● | ○ | ● | ● |
| [02 IAM](../02-iam/README.md) | ● | ● | ● | ● | ● |
| [03 Secretos](../03-secretos/README.md) | ● | ○ | ● | ○ | ○ |
| [04 Compute](../04-compute/README.md) | ● | ● | ● | ○ | ● |
| [05 Ingress y API](../05-ingress-api/README.md) | ● | ○ | ○ | ○ | ● |
| [06 Storage](../06-storage/README.md) | ● | ● | ● | ○ | ○ |
| [07 Mensajería](../07-mensajeria/README.md) | ● | ● | ● | ○ | ● |
| [08 Datos](../08-datos/README.md) | ● | ● | ● | ○ | ● |
| [09 Gobierno](../09-gobierno/README.md) | ○ | ○ | ○ | ● | ○ |
| [10 Terraform](../10-terraform/README.md) | ● | ● | ● | ● | ● |

● protagonista · ○ de apoyo

## Checklist de producción en Azure (antes de abrir al público)

**Red**
- [ ] Bloques de direcciones planificados sin solapamientos entre redes conectadas ([landing zone](landing-zone/README.md))
- [ ] Servicios de datos sin acceso público, con Private Endpoint y zona DNS privada enlazada
- [ ] NSG con denegación por defecto y reglas mínimas; salida controlada (NAT o firewall) y registrada
- [ ] Resolución de nombres comprobada **desde un pod**, no desde el portal ([script](tienda-online/ejemplos/cli/verificar-privado.sh))

**Identidad y secretos**
- [ ] Identidades administradas / Workload Identity en lugar de claves; **sin claves de cuenta** donde sea posible
- [ ] Secretos solo en Key Vault, con rotación y acceso mínimo por servicio
- [ ] Pipelines con federación OIDC (sin secretos guardados) y dos identidades por entorno ([capítulo 10](../10-terraform/autenticacion-y-pipelines/README.md))
- [ ] Revisión de roles amplios (Owner, User Access Administrator, Contributor a nivel de suscripción)

**Datos y mensajería**
- [ ] Copias de seguridad probadas con una **restauración real**; objetivos de recuperación acordados
- [ ] Cifrado en reposo y TLS mínimo 1.2
- [ ] Consumidores **idempotentes**; bandeja de salida donde se guarda y avisa
- [ ] Cola de mensajes fallidos con **alerta** y procedimiento de reproceso

**Operación**
- [ ] Alertas por **síntoma** (errores, latencia, compras exitosas) con enlace al runbook ([runbook](runbook-diagnostico/README.md))
- [ ] Sondas de salud y escalado automático configurados y probados con carga
- [ ] Registros y métricas centralizados con retención definida y datos personales seudonimizados
- [ ] Simulacro de incidente en el último trimestre

**Gobierno y costos**
- [ ] Políticas de región, etiquetas obligatorias y acceso público (primero `Audit`, luego `Deny`)
- [ ] Bloqueos `CanNotDelete` en red, bóvedas y bases de producción
- [ ] Presupuestos con alertas reales y pronosticadas por suscripción; alerta de anomalías
- [ ] Todo como código, revisado por solicitud de cambio, con estado remoto protegido

## Plan de estudio de 8 semanas

| Semana | Capítulos | Práctica |
|---|---|---|
| 1 | 00 Fundamentos · 01 Red (VNet, NSG) | VNet con 2 subredes y un NSG, primero con CLI y luego con Terraform |
| 2 | 01 Red (Private Endpoint, diagnóstico) | Storage con Private Endpoint; rompe el DNS a propósito y diagnostícalo con RPDSI |
| 3 | 02 IAM · 03 Secretos | Identidad administrada que lee un secreto de Key Vault sin claves |
| 4 | 04 Compute | App Service y Function; luego una aplicación en AKS con Workload Identity |
| 5 | 05 Ingress y API | Ingress + APIM con una política de límite de llamadas |
| 6 | 06 Storage · 07 Mensajería | Subida con SAS de delegación + Claim Check; bandeja de salida con Service Bus |
| 7 | 08 Datos · 09 Gobierno | SQL por Private Endpoint; una política que niegue el acceso público; un presupuesto |
| 8 | 10 Terraform · 11 Casos integrados | Un entorno completo en Terraform, destruirlo y reconstruirlo; un simulacro de incidente |

> **Costos:** haz cada laboratorio, **estudia y destruye**. Configura un presupuesto con alerta el primer día. Los Private Endpoints, Service Bus Premium y APIM son lo más caro de un laboratorio: usa niveles bajos o destruye al terminar.

## Preguntas de entrevista (integradoras)

1. Diseña una API pública que accede a una base de datos privada. ¿Qué componentes, qué reglas de red y qué identidades?
2. Un pod en AKS no puede alcanzar Key Vault. Recorre tu diagnóstico paso a paso.
3. ¿Cuándo usarías Service Bus, Event Grid o Event Hubs?
4. Explica el patrón Claim Check y por qué no pones una SAS de larga duración en un mensaje.
5. ¿Cómo evitas que un equipo cree una base de datos con IP pública?
6. ¿Cómo autenticas un pipeline de Terraform en Azure sin secretos guardados?
7. Un `terraform plan` muestra `-/+` en un servidor SQL. ¿Qué haces?
8. ¿Cómo garantizas que un pedido guardado nunca se quede sin su evento, y que el evento no se procese dos veces?
9. ¿Por qué la clave de partición decide el éxito de un event hub? Da un ejemplo bueno y uno malo.
10. Te avisan a las 3 a. m. de que nadie puede comprar. ¿Cuáles son tus primeros cinco minutos?
11. ¿Cómo entregas una suscripción nueva a un equipo asegurando que no solape redes y cumpla las políticas?
12. ¿Cuál es la diferencia entre mitigar y resolver la causa raíz? ¿Cuál va primero y por qué?

## Cómo se relacionan con otros capítulos

Este capítulo es la **síntesis**: cada caso enlaza a los servicios que usa. Si algo no se entiende, el enlace te lleva a su carpeta (teoría, casos reales, Java, ejemplos, troubleshooting).

Prompt del video de este capítulo: [notebooklm.md](notebooklm.md).
