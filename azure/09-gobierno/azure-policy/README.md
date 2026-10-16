# Azure · Gobierno · Azure Policy

## 1. Qué es

**Azure Policy es el servicio que define y hace cumplir las reglas sobre cómo pueden ser los recursos de Azure.** Compara cada recurso con una regla ("las cuentas de almacenamiento deben tener el acceso de red público desactivado") y, según el *efecto* elegido, **lo audita, lo rechaza, lo corrige o despliega lo que falta**. Mientras que el control de acceso (RBAC) responde *"¿quién puede hacer qué?"*, Policy responde *"¿qué está permitido que exista y con qué configuración?"*.

Analogía: **el reglamento de construcción y el inspector de la obra**. Tener la llave del terreno (un rol *Owner*) no te deja construir un cuarto sin salida de emergencia: el inspector revisa los planos (cada solicitud al construir), rechaza lo que incumple, revisa de vez en cuando los edificios ya levantados, y puede ordenar reformas.

```
        Definición  ─────►  Iniciativa (conjunto)  ─────►  Asignación (a un ALCANCE)
        (la regla)          (paquete con un objetivo)       + parámetros + identidad + modo
                                                                   │
                                  ┌────────────────────────────────┼─────────────────────────┐
                                  ▼                                ▼                         ▼
                      al CREAR/MODIFICAR un recurso     cada 24 h y bajo demanda      excepciones
                      (Deny / Append / Modify)          (Audit, AuditIfNotExists,     (Exención con fecha,
                                                         estado de cumplimiento)       notScopes)
                                                                   │
                                                                   ▼
                                                      Tarea de REMEDIACIÓN (recursos ya existentes)
                                                      con la identidad administrada de la asignación
```

Jerarquía donde se aplica (las asignaciones **bajan por herencia**):

```
Grupo raíz del tenant
 └─ Grupo de administración ModaLima          ← "Ubicaciones permitidas", "etiquetas"
     ├─ Plataforma
     ├─ Landing Zones
     │    ├─ Corp                              ← "Sin IP pública", "Private Endpoint"
     │    └─ Online
     └─ Sandbox                                ← reglas más laxas, presupuesto estricto
          └─ Suscripción → Grupo de recursos → Recurso
```

---

## 2. Cómo funciona por dentro

### 2.1 Los objetos
| Objeto | Qué es | Dónde vive |
|---|---|---|
| **Definición de política** | La regla: condición (`if`) + efecto (`then`) + parámetros | Grupo de administración o suscripción (integradas: globales) |
| **Iniciativa (conjunto de definiciones)** | Paquete de políticas con parámetros comunes y un objetivo (cumplimiento, seguridad de red) | Igual que la definición |
| **Asignación** | Aplica una definición/iniciativa a un **alcance**; lleva parámetros, modo de aplicación, identidad y mensaje | Alcance asignado (MG, suscripción, grupo de recursos o recurso) |
| **Exención** | Excepción **con fecha** para un recurso o contenedor ante una asignación | Alcance de la exención |
| **Atestación** | Respuesta manual a políticas con efecto `Manual` (p. ej., "se hizo la revisión de acceso") | Recurso o contenedor |
| **Estado de cumplimiento** | Resultado de evaluar cada recurso: *Compliant*, *NonCompliant*, *Exempt*, *Unknown*… | Servicio PolicyInsights |
| **Tarea de remediación** | Corrige recursos **existentes** no conformes de políticas `Modify`/`DeployIfNotExists` | Alcance de la asignación |

### 2.2 Anatomía de una definición
```json
{
  "properties": {
    "displayName": "Exigir etiqueta en recursos",
    "description": "Rechaza recursos sin la etiqueta indicada.",
    "mode": "Indexed",
    "metadata": { "category": "Tags", "version": "1.0.0" },
    "parameters": {
      "nombreEtiqueta": { "type": "String", "metadata": { "displayName": "Nombre de la etiqueta" }, "defaultValue": "owner" },
      "efecto": { "type": "String", "allowedValues": ["Audit", "Deny", "Disabled"], "defaultValue": "Audit" }
    },
    "policyRule": {
      "if":   { "field": "[concat('tags[', parameters('nombreEtiqueta'), ']')]", "exists": "false" },
      "then": { "effect": "[parameters('efecto')]" }
    }
  }
}
```
- **`mode`**
  - `All`: evalúa grupos de recursos, suscripciones y todos los tipos de recurso (lo recomendado para casi todo).
  - `Indexed`: solo tipos que admiten **etiquetas y ubicación** (úsalo en reglas de etiquetas/ubicación para no marcar como incumplidos recursos que no las soportan).
  - **Modos de proveedor de recursos:** `Microsoft.Kubernetes.Data` (AKS/Arc: reglas dentro del clúster), `Microsoft.KeyVault.Data` (certificados y claves de Key Vault), `Microsoft.Network.Data` (Virtual Network Manager); otros en vista previa.
- **`parameters`:** valores que cambian al asignar (regiones permitidas, nombre de la etiqueta, el **efecto**). Tipos: `String`, `Array`, `Object`, `Boolean`, `Integer`, `Float`, `DateTime`. `strongType` permite elegir en el portal (p. ej., `location`).
- **`policyRule.if`:** condiciones combinables con `allOf` (Y), `anyOf` (O) y `not`.
  - **Campos (`field`):** `type`, `name`, `location`, `tags['x']`, `kind`, `id` y los **alias** de propiedades (p. ej., `Microsoft.Storage/storageAccounts/publicNetworkAccess`).
  - **Operadores:** `equals`, `notEquals`, `like`/`notLike`, `match`/`matchInsensitively`, `contains`/`notContains`, `in`/`notIn`, `containsKey`, `less`/`greater` (y con igualdad), `exists`.
  - **`count`:** cuenta elementos de un arreglo que cumplen una condición (p. ej., "reglas de NSG que abren el puerto 22 a Internet").
  - **Funciones:** `concat`, `field()`, `requestContext().apiVersion`, `ipRangeContains`, `utcNow()` (solo en valores por defecto), `addDays`…
- **Alias:** nombre estable de una propiedad de un tipo de recurso, independiente de la versión de la API. **Cómo descubrirlos:** extensión *Azure Policy* de VS Code, `az provider show --namespace Microsoft.Storage --expand "resourceTypes/aliases"`, o el catálogo de alias en el portal. *Valida siempre el alias con una asignación en `Audit` antes de usar `Deny`.*
- **Versiones:** las definiciones (integradas y personalizadas, esta última en vista previa) pueden tener varias versiones `Mayor.Menor.Parche`: cambios que rompen = mayor; lógica o parámetros = menor; textos = parche. La asignación puede fijar la versión. *Verifica el estado vigente de las versiones personalizadas.*
- **Tipos de política (`policyType`):** `BuiltIn` (de Microsoft, miles), `Custom` (tuyas), `Static` (cumplimiento regulatorio).

### 2.3 Efectos
| Efecto | Qué hace | Cuándo se usa |
|---|---|---|
| **Audit** | Marca el recurso como *no conforme*; **no bloquea** | **Primer paso** de cualquier regla nueva |
| **AuditIfNotExists** | Marca no conforme si **falta** un recurso relacionado (p. ej., configuración de diagnóstico) | "Debe existir…" |
| **Deny** | **Rechaza** la solicitud de crear o cambiar el recurso | Guardarraíl firme |
| **DenyAction** | Impide una **acción** concreta (hoy, `delete`) | Proteger contra borrados (parecido a un bloqueo) |
| **Modify** | Agrega, cambia o quita **propiedades/etiquetas** al crear o actualizar; se remedia en recursos existentes con una tarea | Heredar etiquetas, activar `minTls`, cerrar acceso público |
| **Append** | Agrega campos a la solicitud al crear/actualizar (no corrige lo existente) | Casos puntuales; **`Modify` suele ser mejor** |
| **DeployIfNotExists (DINE)** | Despliega un recurso relacionado si falta (tras crear/actualizar) | Activar diagnósticos, agentes, Private Endpoint |
| **Manual** | Cumplimiento por **atestación** de una persona | Controles de proceso |
| **Disabled** | Apaga la regla (útil para pruebas o como valor de parámetro) | Pausas |
| **Mutate** | Efecto de los modos de Kubernetes: modifica objetos al admitirlos | Políticas de AKS |
| **AddToNetworkGroup** | Agrega redes virtuales a grupos de Virtual Network Manager | Redes administradas |

**Orden de evaluación:** primero `Disabled`; luego `Append` y `Modify` (pueden cambiar la solicitud); después `Deny` (antes que `Audit` para no registrar doble), `Audit`, `Manual`, `AuditIfNotExists` y por último `DenyAction`. `AuditIfNotExists` y `DeployIfNotExists` se evalúan **cuando el proveedor del recurso devuelve éxito**.

> **Ciclo recomendado:** `Audit` → medir el impacto → avisar a los equipos → `Deny` (con exenciones con fecha) → `Modify`/DINE + remediación para lo ya existente.

### 2.4 Cuándo se evalúa
| Disparador | Tiempo aproximado |
|---|---|
| Se crea o actualiza una **asignación** | Unos minutos hasta aplicarse en el alcance (~5 min) y después se evalúa; en alcances grandes tarda más |
| Se **crea/actualiza un recurso** (portal, ARM, CLI, SDK, Terraform) | `Deny`/`Append`/`Modify`: **en la propia solicitud**; el estado de cumplimiento aparece en ~15 min |
| Una suscripción se crea o mueve bajo un grupo con políticas | ~30 min |
| Se crea/cambia/borra una exención | Se reevalúa la asignación |
| **Ciclo estándar** | Cada **24 horas** se reevalúan todas las asignaciones |
| **Bajo demanda** | `az policy state trigger-scan` (grupo de recursos) o la API `triggerEvaluation` (suscripción) |

*Verifica los tiempos en la documentación vigente: son aproximados y dependen del tamaño del alcance.*

### 2.5 Alcance, herencia y exclusiones
- Las asignaciones **se heredan hacia abajo** (grupo de administración → suscripción → grupo de recursos → recurso). Asigna **lo más arriba que tenga sentido** y **excluye** hacia abajo si hace falta.
- **Ubicación de la definición:** una definición creada en un grupo de administración se puede asignar a sus hijos; si la creas en una suscripción, solo se asigna dentro de ella. Crea tus definiciones en un grupo cercano a la raíz.
- **`notScopes` (exclusión):** excluye por completo un subalcance de la evaluación (no cuenta en el cumplimiento). Para algo **permanente y amplio** (un sandbox).
- **Exención:** el recurso **sí se evalúa** pero aparece como *Exempt*; lleva **categoría** (`Waiver` = se acepta el riesgo, `Mitigated` = se resolvió por otra vía), **fecha de caducidad** y descripción. Para casos **puntuales y temporales**.

### 2.6 Asignaciones: lo que las hace seguras de desplegar
- **`enforcementMode`:** `Default` (se aplica) o `DoNotEnforce` (se evalúa y se informa, **sin bloquear ni remediar**): permite ver el impacto de un `Deny` antes de activarlo.
- **Mensaje de no conformidad:** texto que se muestra cuando una solicitud es rechazada (con el motivo y a quién pedir ayuda).
- **Identidad administrada:** necesaria para `Modify` y `DeployIfNotExists` (ver 2.7).
- **Selectores de recursos (`resourceSelectors`) y sobrescrituras (`overrides`):** despliegue **gradual** (por región o tipo de recurso) y cambio del efecto por subconjunto sin tocar la definición. *Verifica la disponibilidad actual.*
- **Parámetros** por asignación: la misma definición con efectos distintos en Corp y Sandbox.

### 2.7 Remediación
- Los efectos `Modify` y `DeployIfNotExists` actúan sobre lo **nuevo** automáticamente; lo **existente** se corrige con una **tarea de remediación** (portal, CLI, API o Terraform).
- **Identidad:** cada asignación tiene **una** identidad administrada (asignada por el sistema, o asignada por el usuario). Las definiciones traen `details.roleDefinitionIds` (los roles necesarios). Si creas la asignación desde el **portal**, Azure concede esos roles en el alcance; con **SDK/Terraform/CLI debes concederlos tú**, o la remediación falla.
- Solo **una** política `Modify`/DINE por tarea. Se puede filtrar por ubicación y recurso.
- Las políticas `Deny` **no** tienen remediación: lo existente sigue ahí y se muestra como no conforme hasta que se corrija a mano o con otra herramienta.

### 2.8 Azure Policy para Kubernetes
Un complemento (en AKS) o extensión (en clústeres con Azure Arc) instala **Gatekeeper v3** (Open Policy Agent) y evalúa los objetos al admitirlos. Las definiciones usan el modo `Microsoft.Kubernetes.Data` y efectos `audit`, `deny`, `disabled` (y `mutate`). Ejemplos de las políticas integradas: no permitir contenedores privilegiados, exigir `requests`/`limits`, permitir solo imágenes de tu registro, impedir `hostNetwork`, exigir etiquetas. Ver [AKS](../../04-compute/aks/README.md).

### 2.9 Con quién se relaciona
- **Microsoft Defender for Cloud:** usa Policy para sus recomendaciones y para las iniciativas de cumplimiento (por ejemplo, *Microsoft cloud security benchmark*, ISO 27001, PCI).
- **Azure Resource Graph:** tabla `policyresources` con los estados de cumplimiento para consultarlos con KQL a escala (ver [KQL](ejemplos/kql/kql-policy.md)).
- **Registro de actividad:** cada `Deny` y `Audit` queda registrado (categoría *Policy*).
- **Event Grid:** eventos de cambio de estado de cumplimiento (`Microsoft.PolicyInsights.PolicyStateChanged`…) para automatizar avisos. *Verifica los tipos de evento.*
- **Bloqueos** y **asignaciones de denegación**: ver [Bloqueos de recursos](../bloqueos-de-recursos/README.md).
- **Grupos de administración:** donde se asigna a escala, ver [Grupos de administración](../grupos-de-administracion/README.md).

### 2.10 Política como código
Trata las definiciones, iniciativas, asignaciones y exenciones como **código**: repositorio Git, revisión de cambios, *pipeline* que despliega con Terraform/Bicep o herramientas específicas (por ejemplo, Enterprise Policy as Code). Estructura sugerida:

```
politicas/
 ├─ definiciones/   etiquetas-obligatorias.json, servicebus-sin-acceso-publico.json
 ├─ iniciativas/    modalima-guardarrailes-red.tf
 ├─ asignaciones/   raiz.tf (región), corp.tf (sin IP pública), sandbox.tf
 ├─ exenciones/     exenciones.tf  (cada una con dueño, motivo y fecha)
 └─ pruebas/        casos que DEBEN fallar y casos que DEBEN pasar (despliegues de prueba)
```
Terraform: [ejemplos/terraform/main.tf](ejemplos/terraform/main.tf).

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- **Prevenir** errores caros: IP pública en una base de datos, región no permitida, cuentas de almacenamiento sin TLS.
- **Detectar** lo que ya está mal y medir el cumplimiento con un número (porcentaje de recursos conformes).
- **Corregir** automáticamente: heredar etiquetas, activar diagnósticos, cerrar acceso público.
- **Escalar** criterios de seguridad y costos a decenas de suscripciones sin revisar a mano.
- **Demostrar cumplimiento** (auditorías) con iniciativas regulatorias.

| NO lo uses para | Alternativa |
|---|---|
| "Arreglar" un diseño de permisos | RBAC: [Azure RBAC](../../02-iam/rbac/README.md) |
| Impedir **borrados** accidentales de un recurso concreto | [Bloqueos](../bloqueos-de-recursos/README.md) (o `DenyAction`) |
| Controlar **qué datos** hay dentro de un servicio | Controles de datos del servicio |
| Bloquear **todo** desde el primer día | Empezar en `Audit` / `DoNotEnforce` |
| Ser el **único** control de seguridad | Defender for Cloud, red privada, identidades administradas |
| Detener el **gasto** | [Presupuestos y alertas](../cost-management/README.md) (Policy puede limitar SKU y regiones, pero no apaga recursos) |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Definición** | La regla en JSON | "Storage sin acceso público de red" |
| **Iniciativa** | Paquete de definiciones con un objetivo | "Guardarraíles de red de ModaLima" |
| **Asignación** | Poner la regla a trabajar en un alcance | Iniciativa en el grupo `Corp` |
| **Alcance (*scope*)** | Dónde aplica (MG, suscripción, grupo de recursos, recurso) | `/subscriptions/…` |
| **Efecto** | Qué hace la regla al incumplirse | `Deny` |
| **Alias** | Nombre estable de una propiedad | `Microsoft.Storage/storageAccounts/publicNetworkAccess` |
| **Modo** | Qué recursos evalúa | `All`, `Indexed` |
| **Exención** | Excepción con fecha | Waiver hasta 31-dic |
| **`notScopes`** | Exclusión permanente de un subalcance | Grupo de recursos sandbox |
| **`DoNotEnforce`** | Evaluar sin bloquear | Ensayo de un `Deny` |
| **Cumplimiento** | % de recursos conformes | 94 % |
| **Remediación** | Tarea que corrige lo existente | Poner `minTlsVersion` |
| **Identidad de la asignación** | Identidad administrada con roles para `Modify`/DINE | Contributor en la suscripción |
| **Atestación** | Respuesta manual a una política `Manual` | "Revisión de accesos hecha" |
| **Landing zone** | Entorno base ya gobernado | `Corp`, `Online` |

---

## 5. Cómo se usa (ruta de adopción)

1. **Define los guardarraíles** (qué es inaceptable): el catálogo [NET-01…NET-12](catalogo-net-01-12.md) de ModaLima es un ejemplo.
2. **Mapea cada regla a una política integrada** (busca primero en *Definiciones*); crea una personalizada solo si no existe.
3. **Agrupa en una iniciativa** con parámetros (efecto, regiones, etiquetas).
4. **Asigna en `DoNotEnforce`/`Audit`** en el nivel alto correcto y espera un ciclo de evaluación.
5. **Lee el cumplimiento:** ¿cuántos recursos incumplen y de quién son? (portal, Resource Graph, [KQL](ejemplos/kql/kql-policy.md)).
6. **Comunica** a los equipos: qué cambia, cuándo y cómo pedir una exención.
7. **Activa `Deny`** (cambia el efecto o el modo de aplicación) y **crea tareas de remediación** para lo existente.
8. **Opera:** revisión mensual de cumplimiento, exenciones que vencen, alertas ante nuevas violaciones.
9. **Todo como código**, con pruebas de que la política bloquea lo que debe y deja pasar lo demás.

Archivos: [Terraform](ejemplos/terraform/main.tf) · [CLI](ejemplos/cli/azure-policy.sh) · [JSON de definiciones](ejemplos/json/) · [KQL y Resource Graph](ejemplos/kql/kql-policy.md) · [Catálogo NET-01…12](catalogo-net-01-12.md).

---

## 6. Seguridad

- **Quién puede cambiar las reglas es lo que más importa:** asignar o excluir políticas equivale a poder desactivar el guardarraíl. Reserva `Resource Policy Contributor` (y *Owner* en los grupos de administración) a un equipo pequeño y exige revisión de cambios.
- **Asigna arriba:** una asignación en el grupo de administración **no puede ser quitada** por el dueño de una suscripción hija (solo puede pedir una exención).
- **Mínimo privilegio en la identidad de remediación:** concede solo los roles de `roleDefinitionIds` y en el alcance necesario.
- **Las exenciones son decisiones de seguridad:** dueño, motivo, **fecha de caducidad**, revisión periódica.
- **Mensajes de no conformidad:** sin datos sensibles.
- **Auditoría:** registro de actividad de las operaciones `policyAssignments`, `policyExemptions` y `policyDefinitions` hacia Log Analytics, con alertas de cambios.
- **Policy no ve dentro de los datos** y no impide a un administrador *con permisos* usar otra vía no cubierta por una regla: complementa, no sustituye, a RBAC y a la red privada.

### IAM de este servicio

| Plano | Quién | Qué hace | Rol/permiso mínimo |
|---|---|---|---|
| **Control** | Equipo de gobierno | Crear definiciones, iniciativas y asignaciones | *Resource Policy Contributor* en el grupo de administración (o rol personalizado `Microsoft.Authorization/policy*/write`) |
| **Control** | Administrador de acceso | Conceder roles a la identidad de la asignación | *Role Based Access Control Administrator* (acotado) o *User Access Administrator* |
| **Control** | Equipo de aplicación | Pedir/gestionar **exenciones** | Rol personalizado con `Microsoft.Authorization/policyExemptions/write` y `…/policyAssignments/exempt/action` en su alcance (normalmente lo hace el equipo de gobierno) |
| **Control** | Auditoría / FinOps | Leer cumplimiento | *Reader* + *Security Reader* (o *Resource Policy Contributor* solo si debe crear remediaciones) |
| **Control** | Remediación | Corregir recursos | La **identidad de la asignación**, con los roles de `roleDefinitionIds` |
| **Control** | Pipeline de despliegue | Aplicar la política como código | Identidad federada (OIDC) con *Resource Policy Contributor* en el alcance de las políticas |
| **Datos** | — | Azure Policy no tiene plano de datos propio (salvo los modos `Microsoft.KeyVault.Data` y `Microsoft.Kubernetes.Data`) | — |

> Crear una exención exige **dos permisos**: escribir la exención en el alcance y la acción `exempt` sobre la asignación. Así el que administra un recurso no puede eximirse solo.

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- **Empezar en `Audit`/`DoNotEnforce`**, medir, avisar, y después `Deny`.
- Asignar **arriba** (grupos de administración) y usar **parámetros** para variar el efecto por entorno.
- Preferir **políticas integradas**; crear personalizadas solo si hace falta, y validarlas con **despliegues de prueba**.
- Agrupar en **iniciativas** y versionar todo como código.
- Escribir **mensajes de no conformidad** útiles (qué falló, cómo corregir, a quién escribir).
- **Exenciones con dueño, motivo y fecha**; revisarlas.
- Combinar **prevención (`Deny`) + detección (`Audit`) + corrección (`Modify`/DINE)**.
- Usar `Indexed` para reglas de etiquetas/ubicación.
- Crear **tareas de remediación** para lo existente y vigilar su resultado.
- Alertar sobre cambios en asignaciones y exenciones.

**Qué NO hacer**
- Activar `Deny` masivo sin avisar ni ensayar.
- Exenciones permanentes y sin dueño.
- Asignar a nivel de suscripción lo que debería ir en el grupo de administración (o duplicar reglas por proyecto).
- Usar un alias sin comprobarlo (la regla "no hace nada" y nadie se entera).
- Olvidar la **identidad y los roles** de las políticas `Modify`/DINE.
- Contar con `Deny` para arreglar lo existente.
- Poner demasiadas condiciones complejas: son difíciles de depurar y tienen límites.
- Usar políticas para compensar un diseño pobre de permisos.
- Dar *Owner* de la suscripción a quien solo debe operar recursos.

---

## 8. Límites, costos y versiones

| Límite (*verifica la tabla vigente*) | Valor |
|---|---|
| Definiciones de política por alcance (MG o suscripción) | 500 |
| Definiciones de iniciativa por alcance / por tenant | 200 / 2 500 |
| Asignaciones (política o iniciativa) por alcance | 200 |
| Exenciones por alcance | 1 000 |
| Parámetros por definición | 20 |
| Políticas por iniciativa / parámetros por iniciativa | 1 000 / 400 |
| Exclusiones (`notScopes`) por asignación | 400 |
| Condiciones anidadas en una regla | 512 |
| Recursos por tarea de remediación | 50 000 |
| Tamaño de la solicitud de definición/asignación | 1 MB |

- **Costo:** Azure Policy **no tiene cargo** propio. Se pagan los recursos que despliegan las políticas DINE (por ejemplo, el envío de diagnósticos a Log Analytics) y servicios relacionados (Defender for Cloud, Azure Policy para Arc). *Verifica precios.*
- **Versiones y retiros:** **Azure Blueprints se retira el 31 de enero de 2027** (con etapas desde el 31-jul-2026): migra a **Deployment Stacks** (con `deny settings`), *template specs* y políticas como código. *Verifica la fecha vigente.*
- **Cambios frecuentes:** efectos nuevos, modos de proveedor de recursos, versionado de definiciones y selectores de recursos siguen evolucionando.

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [catálogo NET-01…12](catalogo-net-01-12.md).
