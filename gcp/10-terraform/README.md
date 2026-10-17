# Google Cloud · 10 Terraform

¿Cómo gestiono todo lo anterior como código, en equipo y sin llaves? (Lo genérico de Terraform/OpenTofu está en [transversal/terraform](../../transversal/terraform/README.md).)

| Unidad | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Estado remoto](estado-remoto/README.md) | ¿Dónde vive el estado y cómo evito pisarnos? | Plano oficial en la caja fuerte | Backend `gcs` con bloqueo |
| [Módulos y entornos](modulos-y-entornos/README.md) | ¿Cómo reutilizo patrones y separo dev de prod? | Planos tipo de una cadena | Microservicios iguales, prod distinto |
| [Autenticación y pipelines](autenticacion-y-pipelines/README.md) | ¿Cómo corre Terraform en CI sin llaves? | Credencial temporal de mantenimiento | WIF, plan/apply, políticas |

## Árbol de decisión: «quiero…»

```
¿Trabajar en equipo sobre la misma infraestructura?     → Backend gcs (bucket por entorno, versionado, CMEK)
¿Repetir el mismo patrón en muchos servicios?           → Módulo versionado con validaciones
¿Separar entornos?                                      → Directorio raíz + proyecto + SA por entorno
¿Ejecutar desde CI?                                     → WIF → SA de plan (PR) / SA de apply (main + aprobación)
¿Evitar desastres en el apply?                          → Plan guardado + política sobre plan.json
```

## Comparativa

| Aspecto | Estado remoto | Módulos y entornos | Pipelines |
|---|---|---|---|
| **Protege de** | Pisarse y perder estado | Copiar y pegar, cambios cruzados | Llaves, applies no revisados |
| **Pieza principal** | Bucket + `.tflock` | `source ?ref=` + validaciones | Pool/proveedor + SAs |
| **Error típico** | Bucket abierto | `ref=main` | Una SA owner |
| **Control en Java** | Auditor del bucket | Deriva en Cloud Run | Política del plan |

## La receta ModaLima
| Necesidad | Pieza | Por qué |
|---|---|---|
| Estado de prod | `modalima-tfstate-prod` con CMEK y 30 versiones | Recuperable y privado |
| Microservicios | Módulo `microservicio` v1.x | Igual para todos |
| Entornos | `entornos/dev`, `entornos/prod` en proyectos separados | Aislamiento |
| CI | WIF por repo; apply solo con entorno protegido | Sin llaves |
| Seguridad del apply | Política de plan en prod | Nada de destruir datos |

## Orden recomendado de adopción
1. Bootstrap del bucket del estado.
2. WIF y SAs por entorno.
3. Pipeline plan/apply con plan guardado.
4. Módulos versionados.
5. Políticas sobre el plan y detección de deriva.

## Reglas transversales
- Nada se aplica desde laptops en prod.
- El estado es un secreto.
- Versiones fijas (módulos, providers, Terraform).
- Lectura en PR, escritura al fusionar.
- Todo lo que el ojo pierde, lo revisa una regla.

## Java en Terraform: qué construye cada `uso-en-java.md`
| Unidad | Qué construyes | Patrón común |
|---|---|---|
| Estado remoto | Auditor del bucket y candados | Solo lectura |
| Módulos y entornos | Reglas por entorno y deriva | Mismas reglas que el módulo |
| Pipelines | Política sobre `plan.json` | Núcleo puro empaquetable como CLI |

## Cómo se relaciona con otros capítulos
- [IAM](../02-iam/README.md): Workload Identity Federation y suplantación.
- [Secretos](../03-secretos/README.md): CMEK del estado y secretos fuera del código.
- [Gobierno](../09-gobierno/README.md): políticas y labels obligatorios.
- [Casos integrados](../11-casos-integrados/README.md): todo junto.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos, troubleshooting, repaso y prompt de NotebookLM.
