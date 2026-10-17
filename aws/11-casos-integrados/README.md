# AWS · 11 Casos integrados

Los capítulos anteriores explican **piezas**; aquí se arman **sistemas**. Cada caso resuelve un problema real de ModaLima o Café Andino combinando varios servicios, con Terraform validado, código Java compilado (Spring MVC/WebFlux y Quarkus imperativo/reactivo) y pruebas del núcleo. Úsalos como plantilla: copia la estructura, cambia los nombres.

| Caso | El problema | Piezas principales | Lo que enseña |
|---|---|---|---|
| [Tienda online](tienda-online/README.md) | Crear un pedido sin perder eventos ni duplicar facturas | ALB, ECS/EKS, RDS, Secrets Manager, EventBridge, SQS, DynamoDB | Bandeja de salida (*outbox*), bandeja de entrada idempotente (*inbox*), contratos de eventos |
| [Subida con Claim Check](subida-claim-check/README.md) | Subir archivos grandes sin pasarlos por la API ni por la cola | S3 (URL prefirmadas), EventBridge, SQS, DynamoDB | Cuarentena, máquina de estados condicional, reconciliador |
| [Clickstream](clickstream/README.md) | Medir clics de la web con orden por sesión y relectura | Kinesis Data Streams, DynamoDB, Firehose, S3, Athena | Clave de partición, ventanas con marca de agua, checkpoint seguro |
| [Landing zone](landing-zone/README.md) | Crear cuentas nuevas con red, presupuesto y guardarraíles, y auditarlas | Organizations, SCP, IAM Identity Center, VPC, Budgets, CloudTrail, Config | Cuentas como código, CIDR sin solapes, verificación donde «no se pudo» es hallazgo |
| [Runbook de diagnóstico](runbook-diagnostico/README.md) | Atender un incidente con método y herramientas | CloudWatch (alarmas, compuestas, panel, Logs Insights), CloudTrail, SNS, AWS Health | Roles, escalera de capas, sonda sintética, triage automatizado |

## Árbol de decisión: «quiero…»

```
¿Quiero publicar un hecho de negocio sin perderlo si falla el broker?
   └─ Tienda online (outbox + EventBridge + SQS con inbox idempotente)

¿Quiero que usuarios suban archivos grandes y procesarlos después?
   └─ Subida con Claim Check (URL prefirmada + evento + estado condicional)

¿Quiero analizar un flujo continuo de eventos con orden por clave?
   └─ Clickstream (Kinesis + ventanas + salida idempotente)

¿Quiero abrir cuentas nuevas con una base segura y auditarlas?
   └─ Landing zone (planificador + módulo + verificador)

¿Quiero estar listo para el próximo incidente?
   └─ Runbook de diagnóstico (alarmas por síntoma + sonda + triage + postmortem)
```

## Matriz capítulo × caso

● usa el capítulo de forma central · ○ lo toca.

| Capítulo | Tienda | Subida | Clickstream | Landing zone | Runbook |
|---|:-:|:-:|:-:|:-:|:-:|
| [00 Fundamentos](../00-fundamentos/README.md) | ○ | ○ | ○ | ● | ○ |
| [01 Red](../01-red/README.md) | ● | ○ | ○ | ● | ● |
| [02 IAM](../02-iam/README.md) | ● | ● | ● | ● | ● |
| [03 Secretos](../03-secretos/README.md) | ● | ○ | ○ | ○ | ○ |
| [04 Compute](../04-compute/README.md) | ● | ○ | ● | ○ | ● |
| [05 Ingress y API](../05-ingress-api/README.md) | ● | ● | ● | ○ | ● |
| [06 Storage](../06-storage/README.md) | ○ | ● | ● | ○ | ○ |
| [07 Mensajería](../07-mensajeria/README.md) | ● | ● | ● | ○ | ● |
| [08 Datos](../08-datos/README.md) | ● | ● | ● | ○ | ○ |
| [09 Gobierno](../09-gobierno/README.md) | ○ | ○ | ○ | ● | ● |
| [10 Terraform](../10-terraform/README.md) | ● | ● | ● | ● | ● |

## Lista de producción: antes de decir «está listo»

- [ ] **Todo como código** y revisado; sin clics manuales en la consola.
- [ ] **Identidades por función**, sin claves de acceso en archivos; permisos acotados por recurso.
- [ ] **Cifrado** en reposo (KMS) y en tránsito; datos personales seudonimizados.
- [ ] **Idempotencia** en cada consumidor y en cada escritura reintentable.
- [ ] **Cola de fallidos con alarma** y procedimiento de reproceso.
- [ ] **Alarmas por síntoma** con enlace al runbook; una página por incidente.
- [ ] **Presupuesto y etiquetas** de costo desde el primer día.
- [ ] **Límites y cuotas** revisados con la carga esperada (con margen).
- [ ] **Pruebas de los caminos de fallo**, no solo del feliz; un simulacro de incidente.
- [ ] **Documentación viva**: el diagrama y el runbook cambian con el sistema.

## Orden recomendado para estudiarlos

1. **Tienda online:** es el esqueleto de casi cualquier microservicio con eventos.
2. **Subida con Claim Check:** añade almacenamiento, cuarentena y estados.
3. **Clickstream:** el mundo de los flujos y las ventanas.
4. **Landing zone:** la base de todo lo demás, vista desde la organización.
5. **Runbook de diagnóstico:** cómo operar lo que construiste.

## Reglas que se repiten en los cinco casos

- **Núcleo puro + adaptador del SDK:** las reglas se prueban sin red; el SDK se cambia sin tocarlas.
- **Lo que no se pudo comprobar no es «bien»:** se informa como hallazgo.
- **Lotes con resultado por elemento:** HTTP 200 no significa «todo salió bien».
- **Cierre ordenado y tiempos límite** en cada cliente.
- **Nunca bloquear el bucle de eventos** en WebFlux/Mutiny.

Cada carpeta trae: teoría, casos reales, uso desde Java, ejemplos (Terraform, CLI, JSON y específicos), troubleshooting, repaso y prompt de NotebookLM.
