# Azure · Gobierno · Grupos de administración (Management Groups)

## 1. Qué es

**Un grupo de administración (*management group*) es un contenedor de suscripciones —y de otros grupos— que sirve para aplicar políticas y permisos una sola vez y que se hereden hacia abajo.** Está **por encima** de la suscripción: si la suscripción es una carpeta de recursos, el grupo de administración es la carpeta que contiene carpetas.

Analogía: **el organigrama de un edificio de oficinas con reglamento por piso**. El reglamento del edificio (raíz) vale para todos; el del piso de "Contabilidad" (un grupo) vale solo para sus oficinas (suscripciones); y cada oficina decide el resto. Cambiar una oficina de piso es cambiar de grupo: hereda el reglamento del piso nuevo.

```
Tenant Root Group  (su ID = el ID del tenant de Entra; no se puede mover ni borrar)
└── mg-modalima                     ← raíz intermedia de la empresa (aquí van las políticas de TODA la empresa)
    ├── mg-modalima-plataforma
    │   ├── mg-modalima-identidad       sub: sub-identidad
    │   ├── mg-modalima-conectividad    sub: sub-hub-red  (firewall, DNS privado, Bastion)
    │   └── mg-modalima-gestion         sub: sub-observabilidad (Log Analytics)
    ├── mg-modalima-landingzones
    │   ├── mg-modalima-corp            sub: sub-tienda-prod, sub-pagos-prod, sub-tienda-dev…  (solo red privada)
    │   └── mg-modalima-online          sub: sub-web-publica…                                  (con un punto de entrada público)
    ├── mg-modalima-sandbox             sub: sub-laboratorio-*                                 (pruebas con límites de costo)
    └── mg-modalima-desmantelado        sub: las que se dan de baja
```

> Los nombres siguen la guía de *zonas de aterrizaje* (landing zones) de Azure: **plataforma** (identidad, conectividad, gestión), **landing zones** (Corp/Online), **sandboxes** y **decommissioned**.

---

## 2. Cómo funciona por dentro

### 2.1 Una jerarquía por tenant, con límites
- Cada directorio (tenant de Microsoft Entra) tiene **una sola jerarquía** con todos los grupos y suscripciones.
- **Cada grupo o suscripción tiene un solo padre.** Un grupo puede tener muchos hijos.
- Hasta **10 000 grupos** por directorio y hasta **seis niveles de profundidad** (sin contar la raíz ni el nivel de la suscripción). *Verifica los límites vigentes.*
- Todas las suscripciones de un grupo deben confiar en el **mismo tenant** de Entra.
- El **ID del grupo no se puede cambiar** tras crearlo (el nombre visible sí). Elige el ID con cuidado (`mg-modalima-corp`, no `grupo1`).
- **Borrar** un grupo exige que esté **vacío** (sin hijos ni suscripciones).

### 2.2 El grupo raíz (*Tenant Root Group*)
- Hay **exactamente uno** por directorio; su ID es el del tenant. Nombre por defecto: *Tenant root group*.
- **No se puede mover ni borrar.** Cambiar su nombre requiere Owner o Contributor sobre él.
- La primera vez que se usan los grupos de administración, Azure crea la raíz y **todas las suscripciones existentes pasan a colgar de ella**.
- **Por defecto, nadie puede administrarla.** Solo un administrador global de Entra puede **elevar su acceso** (rol *User Access Administrator* en la raíz) y a partir de ahí asignar roles. Es un acto excepcional y auditable.
- Lo que se asigne en la raíz aplica a **todo el tenant**: déjala casi vacía (solo lo imprescindible) y trabaja desde una **raíz intermedia** (`mg-modalima`).

### 2.3 Herencia: lo que baja por el árbol
| Qué se asigna en el grupo | Efecto |
|---|---|
| **Azure RBAC** (cualquier rol) | Se hereda en todos los grupos, suscripciones, grupos de recursos y recursos de abajo. Ejemplo: *VM Contributor* en un grupo vale para todas las máquinas debajo |
| **Azure Policy** (definiciones, iniciativas, asignaciones) | Se hereda hacia abajo; **los dueños de las suscripciones no pueden quitarlas ni saltárselas**. Es el uso principal. Ver [Azure Policy](../azure-policy/README.md) |
| **Definiciones personalizadas** (políticas, iniciativas, roles) | Se guardan en un grupo y se pueden asignar en él y en sus descendientes |
| **Despliegues** a nivel de grupo | Con plantillas a ese alcance (`az deployment mg create`) |
| **Consultas** (Resource Graph) | Se puede acotar una consulta a uno o varios grupos |

Las **etiquetas no se heredan** ni consolidan asignaciones: sirven como criterio de política, no como forma de agrupar.

### 2.4 Qué puede hacer cada rol sobre el grupo
| Rol (en el alcance del grupo) | Crear / renombrar / mover / borrar grupos | Asignar acceso | Asignar políticas | Leer |
|---|---|---|---|---|
| **Owner** | Sí | Sí | Sí | Sí |
| **Contributor** | Sí | No | No | Sí |
| **Management Group Contributor** (solo en este alcance) | Sí (mover con restricciones) | No | No | Sí |
| **Reader** / **Management Group Reader** (solo en este alcance) | No | No | No | Sí |
| **Resource Policy Contributor** | No | No | Sí | — |
| **User Access Administrator** | No | Sí | Sí | — |

### 2.5 Mover suscripciones y grupos
Para mover una suscripción (o un grupo) a otro grupo hacen falta permisos **en tres sitios**:

| Dónde | Permisos |
|---|---|
| **El elemento que se mueve** | `Microsoft.Management/managementGroups/write`, `…/subscriptions/write` (solo suscripciones), `Microsoft.Authorization/roleAssignments/write` y `…/delete`, `Microsoft.Management/register/action` (p. ej., *Owner*) |
| **Grupo destino** y **grupo origen** | `Microsoft.Management/managementGroups/write` (p. ej., *Owner*, *Contributor* o *Management Group Contributor*) |
| **Excepción** | Si el origen o el destino es la **raíz**, no se exigen estos permisos |

Detalles que sorprenden:
- Si tu *Owner* sobre la suscripción es **heredado**, solo puedes moverla a un grupo donde también seas *Owner*; si es **directo**, a cualquier grupo donde seas *Contributor*.
- ARM **cachea la jerarquía hasta 30 minutos**: el portal o una política pueden tardar en reflejar el cambio.
- Una asignación de política en el grupo antiguo **deja de aplicar** y la del nuevo **empieza** (puede cambiar el cumplimiento de golpe). Ensaya con `DoNotEnforce` antes de mover suscripciones importantes.

### 2.6 Configuración de la jerarquía (*hierarchy settings*)
Dos ajustes que se hacen **solo sobre la raíz**:

| Ajuste | Por defecto | Qué hace |
|---|---|---|
| **Grupo predeterminado** (`defaultManagementGroup`) | La raíz | Dónde caen las **nuevas** suscripciones. Conviene apuntarlo a un grupo restrictivo (p. ej., *sandbox*), para que ninguna suscripción nueva quede bajo la raíz sin reglas. No mueve las existentes |
| **Exigir autorización para crear grupos** (`requireAuthorizationForGroupCreation`) | Desactivado: **cualquiera puede crear grupos** | Si se activa, crear grupos bajo la raíz exige `Microsoft.Management/managementGroups/write` en la raíz |

Para administrarlos hace falta `Microsoft.Management/managementgroups/settings/write` y `…/read` en la raíz; el rol integrado **Hierarchy Settings Administrator** los incluye. Se cambian en el portal (raíz → *Settings*), con REST (`…/managementGroups/{raíz}/settings/default`), con la CLI (`az account management-group hierarchy-settings`), con PowerShell (`*-AzManagementGroupHierarchySetting`) y con Terraform mediante el proveedor AzAPI (tipo `Microsoft.Management/managementGroups/settings`).

### 2.7 Roles personalizados en un grupo
Un grupo puede ser alcance asignable de un rol personalizado (`/providers/Microsoft.Management/managementgroups/{id}`; usa el **ID**, no el nombre visible). Limitaciones:
- Un rol nuevo solo puede listar **un** grupo en sus alcances asignables.
- Los roles con **acciones de datos** no se pueden asignar a nivel de grupo.
- ARM **no valida** que el grupo exista: un error de tipeo se acepta en silencio.
- Si mueves una suscripción **fuera** del alcance del rol y tenía una asignación de ese rol, falla: quita la asignación antes, amplía el alcance o crea un rol equivalente en la otra rama.

### 2.8 Auditoría
Los eventos de los grupos (cambios de políticas y roles hechos en ellos) aparecen en el **registro de actividad**. Para enviarlos a Log Analytics, almacenamiento o Event Hubs, la configuración de diagnóstico se crea con la **API REST de ARM** sobre `/providers/Microsoft.Management/managementGroups/{id}`.

### 2.9 Diseño recomendado
| Hacer | No hacer (anti-patrones) |
|---|---|
| Jerarquía **plana**: 3–4 niveles | Copiar el organigrama de la empresa en un árbol profundo |
| Agrupar por **tipo de carga** (Corp, Online, Sandbox) y por **plataforma** | Un grupo por **entorno** (producción, pruebas, desarrollo): separa los entornos en **suscripciones** dentro del mismo grupo |
| Usar los grupos para **políticas** | Usarlos para facturación o para dar permisos a equipos de carga |
| Dar permisos a equipos de carga en **suscripción o grupo de recursos** (idealmente con la creación automatizada de suscripciones) | Dar RBAC de equipos de carga en un grupo de administración (sobre-permisos por herencia) |
| **Pocas** políticas en la raíz; la mayoría en la raíz intermedia y los grupos | Muchas políticas en la raíz: difícil depurar lo heredado |
| Definir un **grupo predeterminado** restrictivo (p. ej., *sandbox*) | Dejar suscripciones nuevas bajo la raíz |
| **Exigir autorización** para crear grupos | Dejar que cualquiera cree grupos |
| Un grupo por **región** solo si hay requisito legal de residencia | Grupos por región "por si acaso" |

### 2.10 Los grupos y el resto de los servicios
| Servicio | Relación |
|---|---|
| **Azure Policy** | Es el motivo principal; asignar aquí es lo que evita que un dueño de suscripción quite una regla. Ver [catálogo NET](../azure-policy/catalogo-net-01-12.md) |
| **Azure RBAC** | Útil para equipos de **plataforma** y seguridad (con PIM); evítalo para equipos de carga |
| **Resource Graph** | Inventario y consultas por grupo ([KQL](ejemplos/kql/kql-grupos.md)) |
| **Costos** | Cost Management permite ver costos por jerarquía según el tipo de contrato; los presupuestos se ponen en suscripción o grupo de recursos. Ver [Costos](../cost-management/README.md) |
| **Microsoft Defender for Cloud** | Puntuación de seguridad por grupo (ver [KQL](ejemplos/kql/kql-grupos.md)); los planes se activan por suscripción |
| **Bloqueos de recursos** | **No** se pueden poner en un grupo de administración. Ver [Bloqueos](../bloqueos-de-recursos/README.md) |

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- **Aplicar políticas** a muchas suscripciones a la vez (regiones permitidas, etiquetas, red privada, diagnósticos).
- **Dar permisos amplios a plataforma y seguridad** (lectura en toda la empresa) en un solo lugar.
- **Separar** cargas con requisitos distintos (internas, expuestas, de laboratorio) y **suscripciones de plataforma** de las de aplicaciones.
- **Dar de alta suscripciones nuevas** ya gobernadas: nacen en el grupo correcto y heredan todo (*subscription vending*).
- **Inventario y reportes** por rama de la organización.

| NO lo uses para | Alternativa |
|---|---|
| Modelar el **organigrama** o los centros de costo | Etiquetas (`cost-center`, `owner`) y Cost Management |
| Dar permisos a **equipos de carga** | RBAC en suscripción/grupo de recursos |
| Separar **entornos** (dev/test/prod) | Suscripciones distintas dentro del mismo grupo |
| Proteger recursos del borrado | [Bloqueos](../bloqueos-de-recursos/README.md) o `DenyAction` |
| Limitar el gasto | Presupuestos y alertas; políticas de SKU/regiones |
| Una sola suscripción pequeña | Basta con políticas en la suscripción; los grupos ayudan desde ~3–5 suscripciones |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Grupo de administración** | Contenedor de suscripciones y grupos | `mg-modalima-corp` |
| **Tenant Root Group** | Grupo raíz del directorio (ID = ID del tenant) | No se mueve ni se borra |
| **Raíz intermedia** | Grupo propio de la empresa bajo la raíz | `mg-modalima` |
| **Herencia** | Lo asignado arriba vale abajo | Política de regiones |
| **Landing zone (zona de aterrizaje)** | Suscripción ya preparada y gobernada para una carga | `sub-pagos-prod` |
| **Platform** | Grupo de suscripciones compartidas (red, identidad, gestión) | `mg-modalima-plataforma` |
| **Corp / Online** | Cargas internas (red privada) / expuestas a Internet | `mg-modalima-corp` |
| **Sandbox** | Grupo de pruebas con reglas más laxas y límites de costo | `mg-modalima-sandbox` |
| **Decommissioned** | Grupo de suscripciones dadas de baja | `mg-modalima-desmantelado` |
| **Subscription vending** | Alta automatizada de suscripciones | Terraform + facturación |
| **Grupo predeterminado** | Dónde caen las suscripciones nuevas | `mg-modalima-sandbox` |
| **Hierarchy settings** | Ajustes de la raíz (grupo predeterminado y autorización) | Ver §2.6 |
| **Elevar acceso** | El administrador global se da *User Access Administrator* en la raíz | Acto excepcional |
| **Alcance (scope)** | Nivel al que se aplica algo | `/providers/Microsoft.Management/managementGroups/{id}` |

---

## 5. Cómo se usa

1. **Decide la estructura** (3–4 niveles): raíz intermedia → plataforma / landing zones (Corp, Online) / sandbox / desmantelado. No hagas grupos por entorno ni por equipo.
2. **Crea la raíz intermedia y los grupos como código** ([Terraform](ejemplos/terraform/main.tf)). El ID es permanente: usa un prefijo de la empresa.
3. **Configura la raíz:** grupo predeterminado = *sandbox* y exigir autorización para crear grupos (con el rol *Hierarchy Settings Administrator* para quien lo administre).
4. **Asigna políticas por capas:** pocas en la raíz intermedia (regiones, etiquetas), reglas de red privada en Corp, excepciones documentadas en Online, límites en Sandbox. Empieza en `Audit`/`DoNotEnforce` (ver el [catálogo NET](../azure-policy/catalogo-net-01-12.md)).
5. **Da permisos:** *Reader* (con PIM) a plataforma y seguridad en la raíz intermedia; a los equipos de carga, **solo en su suscripción**.
6. **Automatiza el alta de suscripciones** (*subscription vending*): crear la suscripción, asociarla al grupo, dar roles al equipo, poner presupuesto y red.
7. **Opera:** consultas de inventario ([KQL](ejemplos/kql/kql-grupos.md)); revisión mensual de suscripciones bajo la raíz o en el grupo equivocado; alerta de cambios en la jerarquía.
8. **Da de baja con orden:** mover la suscripción a *desmantelado*, cancelar, y dejar que Azure la elimine tras el periodo de retención.

Archivos: [Terraform](ejemplos/terraform/main.tf) · [CLI](ejemplos/cli/grupos.sh) · [KQL](ejemplos/kql/kql-grupos.md).

---

## 6. Seguridad

- **La raíz es el punto más sensible del tenant.** Quien tenga *Owner* o *User Access Administrator* allí controla todo. Acceso solo a un grupo de cuentas de emergencia/seguridad, con PIM y alertas.
- **Elevar acceso es un evento crítico:** alerta en el registro de Entra y de actividad cada vez que alguien lo hace.
- **Exige autorización para crear grupos** (si no, cualquiera crea grupos y puede ensuciar la jerarquía).
- **Sin RBAC de carga en grupos:** un permiso de equipo heredado por muchas suscripciones es una brecha esperando ocurrir.
- **Grupo predeterminado restrictivo** para que una suscripción nueva no nazca sin reglas.
- **Cambios por código y revisión:** la jerarquía es infraestructura crítica; un `terraform apply` que mueve una suscripción cambia sus políticas de golpe.
- **Cuidado con los roles personalizados:** un error tipográfico en el alcance asignable no se detecta.

### IAM de este servicio

| Plano | Quién | Qué hace | Rol/permiso mínimo |
|---|---|---|---|
| **Control (jerarquía)** | Plataforma | Crear, renombrar, mover y borrar grupos | *Management Group Contributor* en la raíz intermedia (o Contributor/Owner) |
| **Control (jerarquía)** | Pipeline de gobierno | Aplicar la jerarquía como código | Identidad federada con *Management Group Contributor* en la raíz intermedia (y *Owner*/*Resource Policy Contributor* si también asigna políticas) |
| **Control (ajustes)** | Seguridad | Grupo predeterminado y autorización de creación | Rol **Hierarchy Settings Administrator** en la raíz |
| **Control (permisos)** | Seguridad | Asignar roles en grupos | *User Access Administrator* o *Owner* en el grupo |
| **Control (políticas)** | Gobierno | Asignar políticas en grupos | *Resource Policy Contributor* en el grupo |
| **Control (lectura)** | Auditoría, inventario | Ver la jerarquía y consultar | *Management Group Reader* o *Reader* en la raíz intermedia |
| **Control (mover suscripciones)** | Proceso de alta/baja | Mover suscripciones | Permisos de movimiento de §2.5 en origen, destino y suscripción |
| **Emergencia** | Administrador global de Entra | Elevar acceso a la raíz | Acción manual excepcional; revertir después |
| **Datos** | — | Los grupos no tienen plano de datos | — |

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- Jerarquía **plana y por tipo de carga**; entornos en suscripciones separadas.
- **Raíz intermedia** con prefijo de la empresa; la raíz del tenant casi vacía.
- **Grupo predeterminado** restrictivo y **autorización para crear grupos** activada.
- Políticas **arriba** y en modo de ensayo primero; permisos de carga **abajo**.
- Todo **como código** y con revisión; alerta de cambios y de elevaciones de acceso.
- **Automatizar** el alta de suscripciones (*vending*).
- Revisar mensualmente **suscripciones sin grupo esperado** (bajo la raíz).

**Qué NO hacer**
- Reproducir el **organigrama** o crear un grupo por equipo/región/entorno.
- **RBAC de equipos** en grupos de administración.
- Asignar **muchas políticas en la raíz** del tenant.
- Dejar que **cualquiera** cree grupos o que las suscripciones nuevas caigan bajo la raíz.
- Mover una suscripción importante **sin ensayar** el efecto de las políticas del nuevo grupo.
- Usar roles personalizados con **alcances asignables** sin verificar que el grupo existe.
- Confiar en que un grupo protege del borrado (no admite bloqueos).

---

## 8. Límites, costos y versiones
- **Costo:** los grupos de administración **no tienen cargo**.
- **Límites:** 10 000 grupos por directorio; 6 niveles de profundidad (sin raíz ni suscripciones); un padre por elemento. *Verifica los vigentes.*
- **Propagación:** la jerarquía se cachea hasta **30 minutos**; las políticas heredadas tardan en reflejar un movimiento (ver ciclos de evaluación en [Azure Policy](../azure-policy/README.md)).
- **Registro del proveedor:** `Microsoft.Management` debe estar registrado (la CLI y el portal lo hacen al primer uso).
- **API:** `Microsoft.Management/managementGroups` (`2021-04-01` para grupos, suscripciones y ajustes).
- **SDK de Java:** el paquete `azure-resourcemanager-managementgroups` solo existe en **versión beta** (1.0.0-beta.2); para producción usa **Resource Graph** (lecturas) y **REST con el pipeline de azure-core** (escrituras), como en [uso en Java](uso-en-java.md).
- **Terraform:** `azurerm_management_group` (con el padre), `azurerm_management_group_subscription_association` (no uses el atributo `subscription_ids` del grupo a la vez), y AzAPI para los ajustes de la raíz.

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
