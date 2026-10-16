# Azure · 09 Gobierno

Gobernar no es poner obstáculos: es **dejar reglas claras y automáticas para que los equipos avancen rápido sin romper la seguridad, el orden ni el presupuesto**. Este capítulo reúne las cuatro piezas que, juntas, hacen eso en Azure.

| Servicio | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Grupos de administración](grupos-de-administracion/README.md) | ¿**Dónde** cuelgan las reglas y los permisos? | El reglamento de un edificio con normas por piso | Ordenar muchas suscripciones en una jerarquía y que lo que apliques arriba se **herede** hacia abajo |
| [Azure Policy](azure-policy/README.md) | ¿Este recurso **cumple la norma**? | El inspector que revisa (o impide) lo que se construye | Exigir región, etiquetas, Private Endpoint, TLS; auditar; corregir automáticamente |
| [Bloqueos de recursos](bloqueos-de-recursos/README.md) | ¿Se puede **borrar o cambiar** esto? | El candado en la puerta de la bodega | Proteger de borrados accidentales lo que no se puede reconstruir |
| [Cost Management](cost-management/README.md) | ¿**Cuánto gastamos** y quién? | El tablero de gastos de la casa, con alarma | Presupuestos, alertas, anomalías, exportaciones y reparto de costos por equipo |

> Las cuatro **se apoyan entre sí**: la jerarquía decide dónde se aplica cada política; la política impone las etiquetas que Cost Management necesita para repartir costos; los bloqueos protegen lo que las políticas permitieron crear; y los presupuestos avisan cuando algo se sale de lo esperado.

## Árbol de decisión: «quiero que…»

```
¿Quiero que NADIE cree recursos fuera de norma (región, SKU, sin etiqueta, sin Private Endpoint)?
   └─ Azure Policy con efecto Deny (primero Audit, luego Deny)

¿Solo quiero VER qué incumple, sin frenar a nadie todavía?
   └─ Azure Policy con efecto Audit (y el panel de cumplimiento)

¿Quiero CORREGIR solo (poner la etiqueta, activar el diagnóstico)?
   └─ Azure Policy con Modify o DeployIfNotExists (+ una tarea de corrección para lo existente)

¿Quiero que nadie BORRE por accidente el grupo de recursos o la base de producción?
   └─ Bloqueo CanNotDelete (y, si es un recurso concreto, la política DenyAction)

¿Quiero CONGELAR la configuración de algo?
   └─ Bloqueo ReadOnly (con cuidado: tiene efectos secundarios; lee su tabla)

¿Quiero aplicar la MISMA política o el MISMO rol a 15 suscripciones?
   └─ Grupo de administración: asigna una vez arriba y se hereda

¿Quiero separar qué equipo administra qué entorno?
   └─ Grupos de administración + RBAC (a grupos de Entra ID, no a personas)

¿Quiero que me AVISEN cuando el gasto se dispara?
   └─ Cost Management: presupuesto con umbral pronosticado + alerta de anomalías

¿Quiero repartir el costo por equipo?
   └─ Etiqueta obligatoria (Policy) + herencia de etiquetas + consultas/exportaciones (Cost Management)

¿Quiero FRENAR el gasto de un laboratorio al llegar al límite?
   └─ Presupuesto con grupo de acciones que apaga lo marcado (tú construyes el freno; el presupuesto solo avisa)
```

## Comparativa

| Característica | Grupos de administración | Azure Policy | Bloqueos | Cost Management |
|---|---|---|---|---|
| **Qué hace** | Organiza y hereda | Evalúa y hace cumplir reglas | Impide borrar o modificar | Mide, analiza y avisa del gasto |
| **Cuándo actúa** | No actúa solo: es el vehículo de la herencia | Al crear o actualizar (Deny/Modify) y en evaluaciones periódicas (Audit) | Al intentar borrar o cambiar | Con retraso: los datos llegan en 8–24 h |
| **Tipo de control** | Estructural | Preventivo, detectivo y correctivo | Preventivo | Detectivo y de aviso |
| **Alcance** | Tenant | Grupo de administración, suscripción, grupo de recursos | Suscripción, grupo de recursos, recurso (**no** grupos de administración) | Grupo de administración, suscripción, grupo de recursos |
| **Se hereda hacia abajo** | Es el mecanismo | Sí | Sí (gana el más restrictivo) | Los presupuestos **no** se heredan: se crean por alcance |
| **Plano que afecta** | Control (ARM) | Principalmente control; algunos modos también el plano de datos | **Solo control**: no impide leer ni escribir datos | — |
| **Quién lo configura** | Grupos de administración: roles propios; la raíz del tenant requiere elevar el acceso | Policy Contributor / Owner | Owner o User Access Administrator (permiso `locks/*`) | Cost Management Contributor / Contributor |
| **Costo** | Sin cargo | Sin cargo propio (verifica funciones aparte, como Guest Configuration en servidores Arc) | Sin cargo | Sin cargo para recursos de Azure; pagas el almacenamiento de las exportaciones y lo que despliegues para responder |
| **Error típico** | Copiar el organigrama o crear grupos por entorno | Poner `Deny` sin pasar por `Audit` | `ReadOnly` que rompe un servicio (p. ej., que no pueda renovar claves) | Presupuesto sin notificaciones |

## La receta ModaLima (cómo se ve junto)

| Nivel de la jerarquía | Qué se aplica allí |
|---|---|
| **Raíz intermedia** (`mg-modalima`) | Políticas globales: regiones permitidas, etiquetas obligatorias (primero `Audit`), diagnóstico a Log Analytics; roles de lectura para seguridad y auditoría; presupuesto de empresa (solo correo) |
| **Plataforma** (identidad, conectividad, gestión) | Bloqueos `CanNotDelete` en la red y los espacios de trabajo; políticas de red; acceso restringido a pocas personas |
| **Zonas de aterrizaje Corp / Online** | Private Endpoint obligatorio, sin IP pública, TLS mínimo, Entra ID en bases de datos (todo `Deny` tras su periodo de `Audit`); presupuestos por suscripción con pronóstico |
| **Sandbox** | Límites de SKU y región, etiquetas `owner` y `auto-apagar`; presupuesto bajo con **acción de apagado** al 100 % |
| **Desmantelado** | Política que **niega crear** recursos y bloqueo en lo que queda |

## Orden recomendado de adopción

1. **Jerarquía mínima** (no copies el organigrama): raíz intermedia, plataforma, zonas de aterrizaje, sandbox, desmantelado.
2. **Políticas en `Audit`** durante un ciclo completo; luego `Deny` donde el panel ya esté limpio; `Modify`/`DeployIfNotExists` para lo repetitivo.
3. **Etiquetas obligatorias** con valores permitidos (`owner`, `env`, `cost-center`) y herencia de etiquetas en Cost Management.
4. **Presupuestos con notificaciones** (50/80 % reales, 100 % real con acción, 110 % pronosticado) y **alerta de anomalías** por suscripción de producción.
5. **Bloqueos `CanNotDelete`** en lo irrecuperable (red, Key Vault, bases de producción), documentados con el motivo.
6. **Todo como código** (capítulo 10, Terraform en Azure): jerarquía, asignaciones, presupuestos y bloqueos versionados y revisados.

## Reglas transversales

- **Audit antes de Deny.** Un `Deny` sin ensayo bloquea despliegues legítimos un viernes por la tarde.
- **Asigna a grupos de Entra ID, nunca a personas**, y lo más arriba que tenga sentido, pero no más.
- **Los permisos de gobierno son poderosos:** crear políticas, bloqueos o presupuestos va a un proceso (identidad de *pipeline*), no a muchas manos.
- **Una excepción es una decisión con caducidad**, no un parche eterno (exenciones de política con fecha).
- **Los presupuestos avisan; el freno lo construyes tú** (reversible, acotado, con simulacro).
- **Nada de gobierno se cambia a mano en el portal en producción:** código, revisión y despliegue.
- **Documenta el porqué** de cada bloqueo, política y excepción en la descripción del propio recurso.

## Java en gobierno: qué hace cada `uso-en-java.md`

Son SDK de **administración**: latencias de cientos de milisegundos y cuotas, así que **nunca van en el camino caliente** de una API de clientes. Todos siguen el mismo molde.

| Servicio | Qué construyes desde Java | Patrón común |
|---|---|---|
| Azure Policy | Evaluar cumplimiento, resumen por política y recurso, tareas de corrección, exenciones con caducidad | Cliente del SDK + funciones puras de clasificación + caché |
| Bloqueos de recursos | Proteger y auditar bloqueos, borrado controlado con ticket, pilas de despliegue con `denySettings` | Operaciones idempotentes + guardas (no quitar bloqueos sin aprobación) |
| Grupos de administración | Leer el árbol, mover suscripciones con ticket, revisar la higiene de la jerarquía | REST con el *pipeline* de `azure-core` (el SDK está en beta) + Resource Graph |
| Cost Management | Costos por etiqueta, proyección de fin de mes, presupuestos como código, auditoría de presupuestos, freno de laboratorios | SDK estable + lectura por nombre de columna + caché de 1 h |

Reglas comunes: **identidad administrada** separada por función (leer, escribir, destruir), **funciones puras** para las reglas (se prueban sin red), **refresco en segundo plano** con *gauges* de Micrometer, y en reactivo todo lo bloqueante va a `boundedElastic` / pool de trabajadores / hilos virtuales.

## Cómo se relacionan con otros capítulos

- [Fundamentos](../00-fundamentos/README.md): la jerarquía de Azure (tenant, grupos, suscripciones, grupos de recursos) y los costos básicos.
- [Red](../01-red/README.md): políticas que exigen Private Endpoint y bloqueos en la red.
- [IAM](../02-iam/README.md): Azure RBAC y la herencia de roles por grupo de administración; identidades de los procesos de gobierno.
- [Secretos](../03-secretos/README.md): políticas de Key Vault (borrado suave, protección contra purga) y bloqueos.
- [Datos](../08-datos/README.md): políticas de Entra ID, cifrado y copias; bloqueos en las bases de producción.
- Terraform en Azure *(capítulo 10, por escribir)*: el gobierno como código.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos (CLI, Terraform, consultas y los específicos de cada servicio), troubleshooting, repaso y prompt de NotebookLM.
