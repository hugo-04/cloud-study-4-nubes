# Oracle OCI · Caso integrado · Landing zone para una nueva unidad

Café Andino abre una línea de negocio nueva («tostaduría en línea») y necesita, en un día y sin sorpresas: compartimentos prod/no-prod, red con CIDR que **no se solape** con nada existente, grupos y políticas, etiquetas obligatorias, cuotas, presupuesto, Cloud Guard y Audit con retención. Todo como código y **verificado** después.

## 1. Qué es

**Analogía:** abrir una sucursal nueva de una cadena con un manual de apertura. Se reserva el local (compartimentos), se conecta a la red de la central sin chocar con otras sucursales (CIDR), se dan llaves solo a su personal (IAM), se fija el presupuesto del mes y se instalan cámaras (Cloud Guard, Audit). Luego un inspector revisa la lista.

```
 Planificador (Java) ── lee VCN existentes ── propone CIDR libre 10.24.0.0/16 (sin solapes)
        ▼
 Terraform (módulo landing-unidad):
   tenancy/
    └─ tostaduria/            etiqueta por defecto Gobierno.centro_costo = tostaduria
         ├─ prod     (VCN 10.24.0.0/17, cuota, presupuesto, Security Zone)
         └─ no-prod  (VCN 10.24.128.0/17, cuota sin GPU)
   grupos: tostaduria-admins, tostaduria-devs  ·  políticas por compartimento
   Cloud Guard target  ·  Audit 365 días (tenancy)
        ▼
 Verificador (Java/CLI): ¿existe todo? ¿CIDR sin solapes? «no se pudo comprobar» = hallazgo
```

## 2. Cómo funciona por dentro

### Piezas y de dónde salen
| Pieza | Capítulo |
|---|---|
| Compartimentos, etiquetas, cuotas | [09 Gobierno](../../09-gobierno/compartimentos-etiquetas/README.md) |
| Grupos y políticas | [02 IAM](../../02-iam/README.md) |
| VCN, subredes, DRG para conectar con la central | [01 Red](../../01-red/README.md) |
| Presupuesto y alertas | [09 Costos](../../09-gobierno/budgets-costos/README.md) |
| Cloud Guard y Security Zones | [09 Seguridad](../../09-gobierno/cloud-guard-security-zones/README.md) |
| Estado y pipelines | [10 Terraform](../../10-terraform/README.md) |

### Orden de creación
1. Planificar CIDR (leer lo existente; el plan es determinista).
2. `plan` del módulo de la unidad → revisión → `apply` por el runner de plataforma.
3. Verificar: cada pieza existe y cumple; los fallos de lectura cuentan como hallazgos.
4. Entregar al equipo: compartimentos, grupos, estado remoto propio, runner de su entorno.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Nueva unidad, producto o equipo grande | **Este caso** |
| Un microservicio más dentro de un producto | Módulo `microservicio`, no una landing zone |
| Experimentos de un día | Compartimento *sandbox* con cuota y borrado automático |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Landing zone** | Base segura y repetible para recibir cargas |
| **Plan de direcciones (IPAM)** | Reparto de rangos IP sin solapes |
| **Guardarraíl** | Control que impide o detecta lo prohibido |
| **Verificación posterior** | Comprobar el resultado, no solo confiar en el `apply` |

## 5. Cómo se usa
1. Elige el CIDR con el planificador: [uso en Java](uso-en-java.md).
2. Aplica la unidad: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
3. Verifica: [`ejemplos/cli/verificar.sh`](ejemplos/cli/verificar.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Runner de plataforma | `manage` de compartimentos, grupos, políticas, red en el tenancy | — |
| Admins de la unidad | `manage` en `tostaduria` salvo IAM y red compartida | — |
| Devs de la unidad | `manage` en `tostaduria:no-prod`, `read` en prod | — |

- La unidad no puede modificar sus propias políticas ni la red compartida.
- Security Zone en prod desde el primer día.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| CIDR planificado contra lo existente | Elegir «10.0.0.0/16» porque sí |
| Unidad entera como un módulo versionado | Pasos manuales en consola |
| Verificación después del `apply` | Dar por hecho que todo quedó |
| Presupuesto y cuotas antes de entregar | Agregarlos «cuando haya gasto» |
| Tratar «no se pudo comprobar» como hallazgo | Ignorar errores de lectura |

## 8. Límites, costos y versiones
- **Costo:** casi nulo hasta que se crean cargas (la VCN y los controles no cuestan) *(verifica)*.
- **Límites** (verifica): profundidad de compartimentos, VCN por región, políticas por tenancy.
- **Terraform:** `oci_identity_compartment`, `oci_core_vcn`, `oci_identity_group`, `oci_identity_policy`, `oci_budget_budget`, `oci_limits_quota`.
- **SDK:** `VirtualNetworkClient` (`oci-java-sdk-core`) para leer VCN existentes.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
