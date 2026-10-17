# Google Cloud · 02 IAM

Quién puede hacer qué sobre qué, y cómo tu código obtiene su identidad **sin llaves**.

| Unidad | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Roles y políticas](iam-roles-politicas/README.md) | ¿Quién puede hacer qué, dónde? | El llavero del edificio | Permisos de personas y apps |
| [Cuentas de servicio y suplantación](cuentas-de-servicio/README.md) | ¿Con qué identidad corre mi app? ¿Cómo actúo como ella? | El gafete del contratista | Identidad de apps, tokens cortos |
| [Workload Identity en GKE](workload-identity-gke/README.md) | ¿Cómo obtiene permisos un pod? | El pase reconocido por convenio | Pods sin llaves |
| [Workload Identity Federation](workload-identity-federation/README.md) | ¿Y un sistema fuera de Google Cloud? | El convenio entre universidades | CI y centros de datos |

## Árbol de decisión: «quiero…»

```
¿Dar permisos a personas?                       → Grupos + roles predefinidos en el recurso más pequeño
¿Mi código corre en Cloud Run/VM/Functions?     → Cuenta de servicio adjunta + ADC
¿Mi código corre en GKE?                        → Workload Identity (principal directo de la KSA)
¿Mi código corre fuera de Google Cloud?         → Workload Identity Federation (con condición)
¿Necesito actuar como otra cuenta un rato?      → Suplantación (TokenCreator), nunca llaves
¿Algo debe estar prohibido para todos?          → Política de denegación / política de organización
¿Acceso temporal?                               → Binding con condición de tiempo
```

## Comparativa

| Necesidad | Mecanismo | Duración de credenciales | Error típico |
|---|---|---|---|
| Personas | Grupos + roles | Sesión | Roles básicos |
| App en Google Cloud | Cuenta adjunta | 1 h, renovación automática | Cuenta por defecto |
| Pod en GKE | Workload Identity | 1 h | KSA `default` con roles |
| Sistema externo | Federación | ≤ 1 h | Proveedor sin condición |
| Diagnóstico | Suplantación | ≤ 1 h | Llaves «para probar» |

## La receta ModaLima
| Necesidad | Pieza | Por qué |
|---|---|---|
| Equipos | Grupos `tienda-devs@`, `guardia@`, roles por proyecto | Altas/bajas simples |
| Microservicios en GKE | Roles directos a cada KSA | Sin llaves ni cuentas extra |
| Cloud Run | Cuenta de servicio por servicio | Mínimo privilegio |
| CI | Federación con condición repositorio + rama | Sin secretos en el CI |
| Guardia | Suplantación auditada | Diagnosticar con permisos de la app |

## Orden recomendado de adopción
1. Grupos y roles predefinidos; quitar roles básicos.
2. Políticas de organización: sin llaves de cuentas de servicio, sin concesiones automáticas.
3. Una cuenta de servicio por app; Workload Identity en GKE.
4. Federación para el CI.
5. Condiciones de tiempo para accesos temporales; revisión mensual con el recomendador.

## Reglas transversales
- Cero llaves de cuentas de servicio.
- Mínimo privilegio en el recurso más pequeño.
- `iam_member` (aditivo) en Terraform.
- Toda suplantación queda en Audit Logs.
- Lo temporal vence solo.

## Java en IAM: qué construye cada `uso-en-java.md`
| Unidad | Qué construyes | Patrón común |
|---|---|---|
| Roles y políticas | Auditor de bindings | Lógica pura + adaptador |
| Cuentas de servicio | Emisor de tokens suplantados con reglas | `IamCredentialsClient` |
| Workload Identity GKE | Prueba de humo de identidad del pod | Metadatos + política |
| Federación | Réplica de la condición + intercambio real | `GoogleCredentials.fromStream` |

## Cómo se relaciona con otros capítulos
- [Red](../01-red/README.md): reglas de firewall por cuenta de servicio.
- [Secretos](../03-secretos/README.md): quién lee cada secreto.
- [Compute](../04-compute/README.md): identidad de cada plataforma.
- [Gobierno](../09-gobierno/README.md): políticas de organización y Audit Logs.
- [Terraform](../10-terraform/README.md): federación del pipeline.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos, troubleshooting, repaso y prompt de NotebookLM.
