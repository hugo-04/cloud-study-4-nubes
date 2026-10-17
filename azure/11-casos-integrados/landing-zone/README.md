# Azure · Caso integrado · Landing zone (zona de aterrizaje) de ModaLima

Una **landing zone** es el terreno ya preparado donde aterriza cada equipo nuevo: jerarquía, red, identidades, políticas, presupuesto y registro **listos desde el primer día**, para que nadie tenga que inventarlos (ni equivocarse). Este caso junta los capítulos de red, IAM, gobierno y Terraform en un proceso repetible: **«un equipo pide un espacio y lo recibe en horas, igual que los demás»** (*subscription vending*).

## 1. Qué es

**Analogía:** un barrio planificado. El municipio (plataforma) ya instaló las calles (red hub), el alumbrado (registro central), las normas de construcción (políticas) y los medidores (presupuestos). Cuando llega una familia (equipo), recibe un **lote numerado que no choca con otros** (bloque de red), con su medidor y su llave, y construye lo que quiera dentro de las normas.

```
 Tenant ── mg-modalima ─┬─ Plataforma ─┬─ Conectividad (hub, DNS, firewall)
                        │              ├─ Gestión (Log Analytics central)
                        │              └─ Identidad
                        ├─ Zonas de aterrizaje ─┬─ Corp   (privado: sin IP pública)
                        │                       └─ Online (de cara a internet, con WAF)
                        ├─ Sandbox   (laboratorios, presupuesto bajo, SKU limitado)
                        └─ Desmantelado (solo lectura, a la espera de borrarse)

 Suscripción nueva ──► [módulo suscripcion-de-carga] ──► grupo de administración + grupos de recursos
                                                        + VNet (bloque asignado) + peering al hub
                                                        + registro de actividad → central
                                                        + roles al grupo del equipo + presupuesto + bloqueo (prod)
```

## 2. Cómo funciona por dentro

### El proceso de punta a punta

| # | Paso | Quién | Qué sale |
|---|---|---|---|
| 1 | El equipo envía la solicitud (nombre, entorno, responsable, centro de costo, presupuesto, tamaño) | Persona | [`solicitud-aterrizaje.json`](ejemplos/json/solicitud-aterrizaje.json) |
| 2 | El portal valida y **asigna un bloque de red libre** | Portal (Java) | Bloque `10.40.0.0/22` guardado en la base |
| 3 | Se genera `terraform.tfvars.json` | Portal | [`terraform.tfvars.json`](ejemplos/json/terraform.tfvars.json) en un PR |
| 4 | La suscripción se crea con el proceso de facturación de la empresa | Compras/FinOps | ID de suscripción (verifica el método de tu contrato) |
| 5 | Revisión del cambio | Plataforma | Aprobación |
| 6 | El pipeline aplica el módulo | Terraform (identidad del pipeline) | Todo lo de la lista anterior |
| 7 | **Verificación** | Script + checklist | [`verificar-aterrizaje.sh`](ejemplos/cli/verificar-aterrizaje.sh) |
| 8 | El equipo recibe el aviso con lo que tiene y lo que NO puede hacer | Plataforma | Documento de bienvenida |

### Qué hace el módulo ([`suscripcion-de-carga`](ejemplos/terraform/modulos/suscripcion-de-carga/main.tf))

| Recurso | Para qué | Capítulo |
|---|---|---|
| Asociación a grupo de administración | De ahí hereda **políticas y roles** | [09](../../09-gobierno/grupos-de-administracion/README.md) |
| `rg-red-<equipo>-<env>` y `rg-<equipo>-<env>` | Separar la red compartida de la carga del equipo | [00](../../00-fundamentos/README.md) |
| VNet con bloque asignado + subredes `snet-app` y `snet-pe` | Red propia sin solapar | [01](../../01-red/vnet-subnets/README.md) |
| Peering en **ambos sentidos** | Conectar al hub (un lado en cada suscripción) | [01](../../01-red/peering-hub-spoke/README.md) |
| Configuración de diagnóstico de la suscripción | Registro de actividad al espacio central | [01](../../01-red/diagnostico-conectividad/README.md) |
| `Contributor` solo en el grupo de recursos de la carga; `Reader` en la suscripción | Permisos mínimos para un **grupo**, no personas | [02](../../02-iam/rbac/README.md) |
| Presupuesto mensual (80 % real, 100 % pronosticado) | Aviso antes del susto | [09](../../09-gobierno/cost-management/README.md) |
| Bloqueo `CanNotDelete` en la red de producción | Protección contra borrado accidental | [09](../../09-gobierno/bloqueos-de-recursos/README.md) |

Las **políticas** no están en el módulo a propósito: se asignan **una vez** en el grupo de administración y la suscripción las hereda al asociarse ([Azure Policy](../../09-gobierno/azure-policy/README.md)). Así una norma nueva alcanza a todos sin tocar cada módulo.

### El problema de las direcciones
Dos equipos con el mismo bloque `10.40.0.0/22` **no pueden conectarse al mismo hub**. Por eso el bloque se asigna por un servicio con una tabla (clave primaria) y no a mano. Detalle y código: [`uso-en-java.md`](uso-en-java.md).

### Proveedores: uno por suscripción
Terraform no permite proveedores dinámicos: cada suscripción destino lleva su bloque `provider` con alias. Es verboso, pero explícito. Para decenas de equipos: generar el archivo por plantilla desde el portal, un repositorio por zona o una herramienta de orquestación (verifica la que use tu empresa).

## 3. Para qué sirve y cuándo NO

| Situación | ¿Landing zone completa? | Alternativa |
|---|---|---|
| 5+ equipos, varios entornos, auditoría | ✅ | — |
| Una startup con una sola aplicación | ⚠️ Excesivo | Una suscripción, un grupo de administración, políticas básicas y presupuesto |
| Regulación estricta (finanzas, salud) | ✅ con más controles | Añade políticas de cifrado, residencia y registro inmutable |
| Experimentos de aprendizaje | ✅ solo **Sandbox** | Presupuesto bajo con freno |
| Migración de decenas de aplicaciones antiguas | ✅ + zonas Corp | Primero el hub y la identidad; luego mover cargas |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Landing zone** | Suscripción preparada con red, identidad, políticas y presupuesto estándar |
| **Subscription vending** | Proceso automático para «vender» (entregar) suscripciones nuevas ya configuradas |
| **Hub y spoke** | El hub concentra servicios comunes; cada spoke es la red de un equipo |
| **Plataforma / Carga** | Lo común a todos / lo propio de cada equipo |
| **Herencia** | Políticas y roles bajan por la jerarquía |
| **Guardarraíl** | Norma que permite hacer rápido y bien, sin pedir permiso cada vez |
| **Deriva** | Diferencia entre lo declarado en código y lo que hay |
| **Alias de proveedor** | Una segunda configuración de Terraform para otra suscripción |

## 5. Cómo se usa

1. **Una vez:** jerarquía, políticas en `Audit`, hub, Log Analytics central y el pipeline (capítulos [09](../../09-gobierno/README.md) y [10](../../10-terraform/README.md)).
2. **Por equipo:** solicitud → bloque de red → `tfvars` → PR → aplicación → [`verificar-aterrizaje.sh`](ejemplos/cli/verificar-aterrizaje.sh).
3. **Siempre:** consultas de inventario ([`kql-aterrizaje.md`](ejemplos/kql/kql-aterrizaje.md)) y el checklist programado.
4. **Composición:** [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf) llama al módulo para `pedidos-prod` y `catalogo-dev` con sus proveedores; variables de ejemplo en `terraform.tfvars.ejemplo`.

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Pipeline de la plataforma | Contributor + User Access Administrator **acotado** sobre las zonas; permisos en el grupo de administración para asociar | — |
| Equipo de carga (grupo) | `Contributor` solo en `rg-<equipo>-<env>`; `Reader` en la suscripción | Lo que su aplicación necesite, asignado por ellos con identidades administradas |
| Seguridad/auditoría | `Reader` en la raíz intermedia | Ninguno |
| Portal de solicitudes | Ninguno sobre Azure | — |

| Amenaza | Defensa |
|---|---|
| Un equipo se da permisos de dueño | Sin `Owner`/`User Access Administrator` para equipos; política que audita asignaciones privilegiadas |
| Red de un equipo solapada | Asignación centralizada con clave primaria |
| Recursos públicos por descuido | Política `Deny` en Corp; `Audit` en Online con WAF |
| Gasto sin responsable | Etiquetas obligatorias y presupuesto desde el primer día |
| Cambio manual en el portal | Políticas + alertas del registro de actividad + deriva programada |
| Pipeline con demasiado poder | Identidades separadas por zona y aprobaciones por entorno |

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Empezar con 4–5 grupos de administración | Copiar el organigrama de la empresa |
| Políticas en `Audit`, luego `Deny` | `Deny` desde el primer día |
| Entregar permisos a **grupos** y en el alcance mínimo | `Owner` a todo el equipo «para que no molesten» |
| Un módulo para todas las suscripciones de carga | Un Terraform distinto por equipo |
| Verificar con script al terminar | Dar por bueno lo que aplicó el pipeline |
| Registrar quién pidió qué y cuándo | Solicitudes por chat |
| Sandbox con presupuesto y freno | Experimentos en producción |

## 8. Límites, costos y versiones
- **Costo:** los grupos de administración, políticas y bloqueos no cuestan; sí el hub (firewall, puertas de enlace, DNS), el espacio central y cada peering (datos). **Pon el hub bajo presupuesto propio.**
- **Límites:** profundidad de la jerarquía y asignaciones por alcance tienen cuotas: verifica en la doc oficial.
- **Creación de suscripciones:** depende del contrato (EA, MCA, CSP) y de permisos de facturación: verifica el procedimiento de tu empresa.
- **Versiones:** Terraform/OpenTofu con `azurerm` 4.x; Java 21, Spring Boot 4.1, Quarkus 3.40.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
