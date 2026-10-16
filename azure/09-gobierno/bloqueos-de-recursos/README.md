# Azure · Gobierno · Bloqueos de recursos (Resource Locks)

## 1. Qué es

**Un bloqueo (*lock*) es una marca que Azure Resource Manager (ARM) pone sobre una suscripción, un grupo de recursos o un recurso para impedir que se borre —o que se modifique— aunque quien lo intente tenga permisos.** Se evalúa en ARM, por encima de RBAC: *"tienes rol de Owner, pero este recurso tiene candado"*.

Analogía: **el cubre-interruptor del tablero general**. El electricista (con todos los permisos) puede apagar la luz del edificio, pero para hacerlo tiene que levantar primero la tapa a propósito. No impide que lo haga alguien autorizado; evita que lo haga **por accidente** un script, un apuro o una pulsación equivocada.

Dos niveles:

| Nivel (CLI / portal) | Qué impide | Equivale a |
|---|---|---|
| **`CanNotDelete`** (*Delete*) | **Borrar**. Se puede leer y modificar | "No me lo tires" |
| **`ReadOnly`** (*Read-only*) | **Borrar y modificar** (solo lectura); sin embargo, muchas operaciones que parecen lectura usan `POST` y también se bloquean | Un rol *Reader* aplicado a todos |

```
Suscripción  ───────────── 🔒 (ReadOnly aquí congela TODO lo de abajo; casi nunca es buena idea)
 └─ Grupo de recursos rg-prod-datos ── 🔒 CanNotDelete  ← lo habitual: protege el grupo y todo su contenido
     ├─ Cosmos DB, SQL, Key Vault, Storage…            (heredan el candado, también lo que se cree después)
     └─ Recurso con 🔒 propio (ReadOnly)                (gana el MÁS restrictivo de la cadena)
```

---

## 2. Cómo funciona por dentro

### 2.1 Qué bloquea y qué no
- Un bloqueo es un recurso (`Microsoft.Authorization/locks`) con nombre, nivel y notas, creado **en el alcance** que protege.
- **Solo afecta al plano de control** (llamadas a `management.azure.com`): crear, modificar, borrar o mover *recursos de Azure*. **No afecta al plano de datos**: un bloqueo en una cuenta de almacenamiento **no** impide borrar blobs, colas o tablas; un `ReadOnly` en un servidor SQL no impide escribir datos en sus bases.
- Los bloqueos **anulan los permisos** de cualquier usuario y rol (a diferencia de RBAC, que concede).
- **No se pueden poner en grupos de administración**; solo en suscripción, grupo de recursos o recurso.

### 2.2 Herencia
- Un bloqueo en un alcance se **hereda por todo lo que contiene**, incluidos los recursos que se creen después.
- Si hay varios en la cadena, **gana el más restrictivo**.
- Los **recursos de extensión** (por ejemplo, una configuración de diagnóstico de una cuenta de almacenamiento) heredan el bloqueo del recurso al que están aplicados.
- **Borrar un grupo de recursos** con un bloqueo `CanNotDelete` en *cualquiera* de sus recursos **falla por completo** (no hay borrado parcial).

### 2.3 Quién puede crear y quitar bloqueos
Hace falta `Microsoft.Authorization/locks/*` (crear y borrar): lo tienen **Owner** y **User Access Administrator** (y algunos roles especializados). *Contributor no puede.* Esto permite una **separación de funciones**: el equipo de aplicación opera con *Contributor* y solo seguridad/plataforma administra los candados (con un rol personalizado, ver sección 6).

> Un bloqueo es un **freno**, no una pared: quien tiene permiso puede quitarlo y borrar después. Su valor es hacer el borrado **deliberado y auditable**, no imposible.

### 2.4 Lo que se rompe con los bloqueos (leerlo antes de aplicarlos)
Muchas operaciones que no parecen "modificar" usan `POST`; un `ReadOnly` las bloquea.

| Servicio / alcance | Efecto del bloqueo |
|---|---|
| **Cuenta de almacenamiento** (`ReadOnly`) | Bloquea *List Keys* (los clientes sin claves deben usar Entra ID), las asignaciones de roles a la cuenta o a un contenedor y la creación de contenedores por el plano de control |
| **Cuenta de almacenamiento** (cualquiera) | **No** protege blobs, colas, tablas ni archivos |
| **NSG** (`ReadOnly`) | Impide crear *flow logs* del NSG (`CanNotDelete` no) |
| **App Service** (`ReadOnly`) | Algunas herramientas no pueden mostrar archivos |
| **Grupo de recursos con plan de App Service** (`ReadOnly`) | **Bloquea escalar** (vertical y horizontal) |
| **Grupo de recursos con máquina virtual** (`ReadOnly`) | Bloquea **iniciar y reiniciar** máquinas |
| **Grupo de recursos** (`ReadOnly`) | Bloquea mover recursos hacia dentro o fuera |
| **Grupo con cuenta de Automation** (`ReadOnly`) | Bloquea **iniciar runbooks** |
| **Recurso o grupo** (`CanNotDelete`) | Bloquea **borrar asignaciones de roles** (la baja de personas puede fallar) |
| **Grupo de recursos** (`CanNotDelete`) | Impide que se borre solo el historial de despliegues: al llegar a **800 despliegues**, los nuevos fallan |
| **Grupo creado por Azure Backup** (`CanNotDelete`) | Las copias fallan porque no pueden limpiar puntos de restauración (máx. 18) |
| **Grupo con espacios de trabajo de Machine Learning** (`CanNotDelete`) | Los clústeres no reducen nodos ociosos |
| **Application Gateway** (`ReadOnly`) | Bloquea consultar el estado de salud de los backends (usa `POST`) |
| **AKS** (`ReadOnly`) | Limita el acceso a recursos de Kubernetes desde el portal |
| **Log Analytics** (`ReadOnly` / `CanNotDelete`) | `ReadOnly` bloquea ciertas funciones; `CanNotDelete` **no** impide purgar datos (quita el rol *Data Purger*) |
| **Suscripción** (`ReadOnly`) | Azure Advisor no puede guardar resultados |
| **VNet de PostgreSQL** | Bloqueos en la VNet o subredes pueden interferir con operaciones de red y DNS: quítalos para crear el servidor y vuélvelos a poner |
| **Aplicaciones administradas** (p. ej., Databricks) | El grupo de recursos administrado ya viene bloqueado; se elimina borrando el servicio |

*Esta lista cambia con el tiempo: verifica la página oficial de bloqueos antes de aplicar `ReadOnly`.*

### 2.5 Bloqueos e infraestructura como código
- **Terraform / Bicep / ARM** también chocan con los bloqueos: un `destroy` o un reemplazo de recurso falla si hay `CanNotDelete`; un `apply` que modifica falla con `ReadOnly`.
- **Patrón:** el bloqueo es un recurso más del código (`azurerm_management_lock`) con `depends_on` del recurso protegido; para destruir, se hace un **cambio revisado** que primero quita el bloqueo (variable `proteger = false`) y luego borra.
- No bloquees el grupo de recursos donde se **ejecuta el propio pipeline** de despliegue de ese grupo con `ReadOnly`.

### 2.6 Bloqueos frente a otras protecciones
| Mecanismo | Qué protege | Plano | Cuándo |
|---|---|---|---|
| **Bloqueo `CanNotDelete`** | Borrado de recursos y grupos | Control | Recursos de producción con estado o compartidos (red, DNS, Key Vault, bases de datos, Log Analytics) |
| **Bloqueo `ReadOnly`** | Cambios y borrado | Control | Pocos casos (recursos que casi nunca cambian), tras probar efectos secundarios |
| **Política `DenyAction`** | Borrado por regla (p. ej., "todo lo etiquetado `env=prod`") | Control | Proteger **a escala** sin crear un bloqueo por recurso. Ver [Azure Policy](../azure-policy/README.md) |
| **Deployment Stacks con `denySettings`** | Que nadie modifique ni borre lo que gestiona la pila (`denyDelete`, `denyWriteAndDelete`), con principales excluidos | Control | Entornos completos desplegados como una unidad (reemplaza a los bloqueos de Blueprints) |
| **Asignaciones de denegación (*deny assignments*)** | Bloqueo por rol/acción | Control | Las crea Azure por ti (pilas de despliegue, aplicaciones administradas); no se crean a mano |
| **Borrado suave, protección contra purga, versionado, inmutabilidad** | Datos dentro del servicio | **Datos** | Key Vault, Blob, bases de datos: lo que los bloqueos **no** cubren |
| **Copias de seguridad y restauración** | Recuperar tras un borrado | — | Siempre; un bloqueo no sustituye a una copia |
| **RBAC** | Quién puede qué | Control | Primero: que casi nadie tenga permiso de borrar en producción |

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- **Evitar el borrado accidental** de recursos críticos: bases de datos, Key Vault, redes, zonas DNS, Log Analytics, grupos de recursos de producción.
- **Hacer deliberado** un borrado peligroso: hay que quitar el bloqueo (queda en el registro de actividad).
- **Proteger recursos compartidos** de scripts de limpieza automáticos (por etiqueta o antigüedad).
- **Separar funciones:** quien opera los recursos no administra los candados.

| NO lo uses para | Alternativa |
|---|---|
| Proteger **datos** de borrado (blobs, filas, secretos) | Borrado suave, versionado, inmutabilidad, copias |
| Impedir que un administrador con permisos haga daño a propósito | RBAC mínimo, PIM, aprobaciones, alertas |
| `ReadOnly` "por si acaso" en grupos con VM, App Service, Automation, Backup | `CanNotDelete`, o `DenyAction` selectivo |
| Bloquear **cada recurso** a mano | Un bloqueo en el grupo de recursos, o una política `DenyAction` por etiqueta |
| Controlar costos | Presupuestos y alertas |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Bloqueo** | Marca de ARM que impide borrar (y/o modificar) | `lock-no-borrar` |
| **`CanNotDelete`** | Se lee y se modifica, no se borra | Grupo `rg-prod-datos` |
| **`ReadOnly`** | Solo lectura (afecta incluso a `POST`) | Zona DNS raíz |
| **Herencia** | El candado baja a hijos y a lo que se cree después | Candado en el grupo |
| **Más restrictivo gana** | Entre varios candados, vale el más estricto | `ReadOnly` > `CanNotDelete` |
| **Plano de control** | Operaciones de ARM sobre recursos | Crear un contenedor |
| **Plano de datos** | Operaciones sobre el contenido del servicio | Borrar un blob |
| **Recurso de extensión** | Recurso que cuelga de otro (diagnóstico, rol) | Diagnóstico de una cuenta |
| **`DenyAction`** | Efecto de política que impide el borrado | `env=prod` no se borra |
| **Pila de despliegue (*deployment stack*)** | Conjunto de recursos gestionado como una unidad | Entorno de un cliente |
| **`denySettings`** | Modo de bloqueo de una pila | `denyDelete` |
| **`ScopeLocked`** | Error de ARM cuando un bloqueo impide la operación | Intento de borrar |

---

## 5. Cómo se usa

1. **Clasifica** los recursos: ¿tiene estado?, ¿es compartido?, ¿cuesta reconstruirlo?, ¿hay datos que no están en otro lugar? Esos van con `CanNotDelete`.
2. **Un bloqueo por grupo de recursos de producción** (no por recurso), con **notas** (motivo, equipo, ticket) y nombre convencional (`lock-cannotdelete-<grupo>`).
3. **Excepciones por recurso** solo para lo que sí necesita `ReadOnly`, tras probar los efectos de la tabla 2.4.
4. **Como código:** `azurerm_management_lock` con `depends_on` ([Terraform](ejemplos/terraform/main.tf)).
5. **Roles:** crea un rol personalizado "Administrador de bloqueos" y asígnalo solo a plataforma/seguridad; los equipos de aplicación operan como *Contributor*.
6. **Procedimiento de borrado controlado:** solicitud aprobada → quitar bloqueo → borrar → (si procede) volver a poner → registro.
7. **Alertas:** aviso cuando se **crea o borra** un bloqueo (registro de actividad); verificación periódica de que los grupos de producción **tienen** bloqueo ([KQL](ejemplos/kql/kql-bloqueos.md)).
8. **Capa adicional:** política `DenyAction` para `env=prod`, y borrado suave/copias en los datos.

Archivos: [Terraform](ejemplos/terraform/main.tf) · [CLI](ejemplos/cli/bloqueos.sh) · [KQL](ejemplos/kql/kql-bloqueos.md).

---

## 6. Seguridad

- **Separación de funciones:** *Contributor* para operar; un rol personalizado con `Microsoft.Authorization/locks/*` solo para plataforma. Así quien despliega no puede quitar el candado.
- **Quitar un bloqueo debe ser un evento visible:** alerta del registro de actividad (`Microsoft.Authorization/locks/delete`) a un canal del equipo de seguridad.
- **PIM / acceso justo a tiempo** para el rol que puede quitar candados en producción.
- **No es un control de acceso:** quien pueda quitarlo, puede borrar; combina con RBAC mínimo y aprobaciones.
- **Notas del bloqueo:** sin información sensible; con el motivo y la persona/equipo responsable.

### IAM de este servicio

| Plano | Quién | Qué hace | Rol/permiso mínimo |
|---|---|---|---|
| **Control** | Plataforma / seguridad | Crear y borrar bloqueos | Rol personalizado: `Microsoft.Authorization/locks/*` (más lectura del alcance); o *Owner* / *User Access Administrator* |
| **Control** | Equipos de aplicación | Operar recursos (desplegar, escalar) | *Contributor* (**no** puede crear ni borrar bloqueos) |
| **Control** | Lectura / auditoría | Ver bloqueos | *Reader* (`Microsoft.Authorization/locks/read`) |
| **Control** | Pipeline de despliegue | Aplicar el bloqueo como código | Identidad federada con el rol de administrador de bloqueos en el alcance, **o** pasos de "quitar/poner" con aprobación |
| **Control** | Proceso de borrado controlado | Quitar el bloqueo, borrar y volver a poner | Identidad con el rol de bloqueos y *Contributor*, accesible solo tras aprobación |
| **Datos** | — | Los bloqueos no existen en el plano de datos | — |

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- `CanNotDelete` en el **grupo de recursos** de producción y en recursos críticos compartidos.
- **Notas** claras y nombres convencionales; bloqueos como **código**.
- **Alertar** cuando se crea o borra un bloqueo.
- **Probar** un borrado de laboratorio para conocer el mensaje `ScopeLocked`.
- **Capas:** bloqueo + política `DenyAction` + borrado suave/copias + RBAC mínimo.
- Documentar el **procedimiento** para quitar el bloqueo y quién lo aprueba.
- Excluir del bloqueo lo que debe cambiar a menudo (o usar `CanNotDelete`, no `ReadOnly`).

**Qué NO hacer**
- `ReadOnly` en grupos con App Service, VM, Automation, Backup o AKS sin probar.
- Pensar que protegen **datos** (blobs, filas, secretos).
- Dar *Owner* a todo el mundo y confiar en el candado como control principal.
- Bloquear el grupo de recursos donde un proceso automático necesita escribir (diagnósticos, copias, escalado).
- Poner bloqueos manuales fuera del código (nadie sabe por qué están ahí).
- Dejar la suscripción entera en `ReadOnly`.
- Olvidar que el bloqueo **impide borrar asignaciones de roles** con `CanNotDelete` (afecta a las bajas de personas).

---

## 8. Límites, costos y versiones
- **Costo:** los bloqueos **no tienen costo**.
- **Límite:** hasta **20 bloqueos por alcance único** (*verifica el límite vigente*).
- **Propagación:** se aplican en cuestión de segundos/minutos; la herencia es automática.
- **Planos:** solo control (ARM). Para datos, usa las protecciones del servicio.
- **Alternativas vigentes:** `DenyAction` (política), **Deployment Stacks** con `denySettings` (sustituyen a los bloqueos de Azure Blueprints, que se retira el 31 de enero de 2027; *verifica la fecha vigente*).
- **API:** `Microsoft.Authorization/locks` (versión `2016-09-01` en los ejemplos oficiales; las herramientas recientes usan versiones más nuevas).

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
