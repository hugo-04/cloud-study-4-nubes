# 10 · Políticas y gobierno

Cómo se **imponen las reglas** a toda la organización: **Azure Policy**, Management Groups y Locks, con sus equivalentes en **AWS** (SCP, Config, Control Tower), **OCI** (Security Zones, Cloud Guard) y **GCP** (Organization Policy).

---

## 1. Qué es (con analogía)

| Pieza | Analogía |
|---|---|
| **IAM** | La **llave**: quién puede entrar |
| **Política (Policy)** | El **reglamento de construcción**: aunque tengas la llave, **no puedes construir un cuarto sin salida de emergencia** |
| **Management Group / OU / Carpeta** | Los **pisos y edificios** del conjunto, donde se aplican reglamentos por zona |
| **Lock (bloqueo)** | El **candado en el interruptor general**: nadie lo apaga por accidente |
| **Presupuesto** | El **medidor de luz con alarma** |

**IAM responde: ¿quién puede hacer qué?**
**Policy responde: ¿qué está permitido que exista?**

> Un *Owner* con todos los permisos de IAM puede ser **bloqueado por una política** si intenta crear una IP pública donde está prohibido.

---

## 2. Para qué sirve y cuándo NO usarlo

**Sirve para**
- **Prevenir** errores caros (IP pública en una base, región no permitida).
- **Detectar** lo que ya está mal (auditoría de cumplimiento).
- **Corregir** automáticamente (agregar etiquetas, activar diagnósticos).
- **Escalar** el criterio de seguridad a cientos de equipos sin revisar a mano.

**Cuándo NO**
- Para "arreglar" un diseño de permisos: usa IAM.
- Con reglas **tan estrictas** que todo equipo pida excepciones: empieza en modo **auditar**.
- Como único control: es una **barrera**, no un sustituto del diseño.

---

## 3. Conceptos clave

| Término | Definición simple |
|---|---|
| **Definición de política** | La regla (condición + efecto) |
| **Iniciativa** | Un conjunto de políticas con un objetivo (por ejemplo, "cumplimiento de seguridad") |
| **Asignación** | Aplicar una política o iniciativa a un **alcance** |
| **Alcance (scope)** | Dónde aplica: grupo de administración, suscripción, grupo de recursos |
| **Efecto** | Qué hace la política: auditar, denegar, modificar, desplegar |
| **Parámetros** | Valores configurables de una política (regiones permitidas, nombre de etiqueta) |
| **Exención** | Excepción temporal y documentada para un recurso |
| **Cumplimiento** | Informe de qué recursos cumplen y cuáles no |
| **Remediación** | Corregir recursos que ya existen y no cumplen |
| **Guardarraíl (guardrail)** | Regla preventiva o de detección sobre configuraciones peligrosas |
| **Landing zone** | Entorno base ya gobernado (red, identidad, políticas) donde aterrizan las cargas |

---

## 4. Equivalencias en las 4 nubes

| Necesidad | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| Jerarquía de gobierno | Management Groups | Organizations + OUs | Compartimentos (anidados) | Organización + carpetas |
| **Impedir** acciones o configuraciones | **Azure Policy** (`Deny`) | **SCP** (techo de permisos) | **Security Zones** | **Organization Policy** (constraints) |
| **Auditar** cumplimiento | Azure Policy (`Audit`) / Defender for Cloud | **AWS Config** | **Cloud Guard** | Security Command Center / Cloud Asset Inventory |
| **Corregir** automáticamente | `Modify` / `DeployIfNotExists` + tarea de remediación | Config + remediación (SSM) | Cloud Guard responders | Políticas + automatización (Cloud Functions) |
| Paquete de guardarraíles | Iniciativas (por ejemplo, Microsoft cloud security benchmark) | **Control Tower** (guardarraíles) | Security Zone recipes | Policy constraints predefinidos |
| Etiquetas obligatorias | Policy (`Deny` si falta) / `Modify` | **Tag Policies** (+ SCP) | Tag defaults y tag namespaces obligatorios | Policy de etiquetas / labels (con automatización) |
| Límites de cuota/capacidad | Policy (SKU permitidos) y cuotas | Service Quotas + SCP | **Quotas** por compartimento | Cuotas y Org Policy |
| Bloqueo anti-borrado | **Locks** | Termination protection / políticas | Políticas y retención | Retention / Lien |
| Evitar exfiltración de datos | Private Endpoints + Policy | VPC endpoints + SCP | Security Zones | **VPC Service Controls** |
| Presupuestos y alertas | Cost Management Budgets | AWS Budgets | Budgets | Billing Budgets |

### Diferencias reales

- Una **SCP no concede** permisos: solo fija el **máximo** que puede llegar a tener una cuenta. Azure Policy **evalúa propiedades de los recursos** (por ejemplo, "el campo `publicNetworkAccess` debe ser `Disabled`"), lo que es más fino.
- **Organization Policy (GCP)** funciona con **constraints** ya definidos (listas y booleanos), no con reglas libres.
- **Security Zones (OCI)** aplican una *receta* de reglas a un **compartimento**: las acciones que la incumplen **se rechazan**.
- **AWS Config** *detecta* y puede remediar; la **prevención** la hace una SCP o IAM.

---

## 5. Azure Policy en detalle

### 5.1 Efectos

| Efecto | Qué hace | Cuándo |
|---|---|---|
| **Audit** | Marca como "no cumple", no bloquea | **Primer paso** al introducir una regla |
| **AuditIfNotExists** | Audita si **falta** un recurso relacionado | "Debe existir configuración de diagnóstico" |
| **Deny** | **Rechaza** la creación o cambio | Guardarraíl firme |
| **Modify** | Cambia propiedades (por ejemplo, agrega una etiqueta) | Corrección automática |
| **DeployIfNotExists** | Despliega un recurso relacionado si falta | Activar diagnósticos, agentes |
| **Append** | Añade campos al recurso | Casos puntuales |
| **DenyAction** | Impide una acción (por ejemplo, borrar) | Protección |
| **Disabled** | Apaga la regla | Pruebas |

> **Ciclo recomendado:** `Audit` → revisar el impacto → `Deny` (con excepciones documentadas).

### 5.2 Cuándo se evalúa

- Al **crear o modificar** un recurso (efectos `Deny`, `Append`, `Modify`).
- Con un **ciclo de cumplimiento** periódico (aproximadamente cada 24 horas) y tras asignar o cambiar una política (puede tardar un rato en reflejarse).
- Bajo demanda con `az policy state trigger-scan`.

### 5.3 Ejemplo 1: negar cuentas de storage con acceso público de red

```json
{
  "mode": "Indexed",
  "policyRule": {
    "if": {
      "allOf": [
        { "field": "type", "equals": "Microsoft.Storage/storageAccounts" },
        { "field": "Microsoft.Storage/storageAccounts/publicNetworkAccess", "notEquals": "Disabled" }
      ]
    },
    "then": { "effect": "Deny" }
  }
}
```

### 5.4 Ejemplo 2: etiqueta obligatoria con parámetro

```json
{
  "mode": "Indexed",
  "parameters": {
    "nombreEtiqueta": {
      "type": "String",
      "metadata": { "displayName": "Nombre de la etiqueta" },
      "defaultValue": "owner"
    }
  },
  "policyRule": {
    "if": {
      "field": "[concat('tags[', parameters('nombreEtiqueta'), ']')]",
      "exists": "false"
    },
    "then": { "effect": "Deny" }
  }
}
```

### 5.5 Crear y asignar (CLI)

```bash
SUB=<ID_DE_SUSCRIPCION>

az policy definition create --name deny-storage-publico \
  --display-name "Negar storage con acceso público de red" \
  --mode Indexed --rules regla-storage.json --subscription $SUB

az policy assignment create --name deny-storage-publico \
  --policy deny-storage-publico \
  --scope /subscriptions/$SUB/resourceGroups/rg-dev

# Ver cumplimiento
az policy state summarize --resource-group rg-dev

# Excepción temporal y documentada
az policy exemption create --name excepcion-demo \
  --policy-assignment <ID_DE_LA_ASIGNACION> \
  --exemption-category Waiver --expires-on 2026-12-31T00:00:00Z \
  --scope <ID_DEL_RECURSO>
```
> El alias de la propiedad (`publicNetworkAccess`) y los parámetros dependen del tipo de recurso: búscalos en el catálogo de aliases de Azure Policy y valida con una asignación en modo **Audit** antes de usar `Deny`.

### 5.6 Políticas integradas útiles (busca el nombre exacto en *Definitions*)

- "Allowed locations" (regiones permitidas).
- "Network interfaces should not have public IPs".
- "Storage accounts should disable public network access".
- "Azure Key Vaults should use private link".
- "Inherit a tag from the resource group if missing" (`Modify`).
- "Kubernetes cluster containers should not run privileged".
- "Allowed VM size SKUs".

### 5.7 Locks

```bash
az lock create --name no-borrar --lock-type CanNotDelete --resource-group rg-prod
```
| Tipo | Efecto |
|---|---|
| `CanNotDelete` | Se puede leer y modificar, **no borrar** |
| `ReadOnly` | Solo lectura (puede bloquear operaciones inesperadas; úsalo con cuidado) |

### 5.8 Estructura recomendada (adaptada de las *landing zones* de Azure)

```
Tenant Root
 └─ Management Group "ModaLima"
     ├─ Plataforma
     │    ├─ Identidad
     │    ├─ Conectividad   (hub, firewall, DNS)
     │    └─ Gestión        (logs centralizados, monitoreo)
     ├─ Landing Zones
     │    ├─ Corp           (apps internas, sin IP pública)
     │    └─ Online         (apps expuestas a internet)
     ├─ Sandbox             (pruebas, con presupuesto y límites)
     └─ Desmantelado
```

Las políticas se asignan **en el nivel más alto que corresponda** y bajan por herencia: por ejemplo, "región permitida" en la raíz de la organización; "sin IP pública" en `Corp`.

> **Azure Blueprints** fue retirado; para empaquetar entornos usa plantillas (Bicep / Terraform), *Template Specs*, *Deployment Stacks* y políticas. Verifica el estado vigente.

### 5.9 Azure Policy para Kubernetes

Aplica reglas estilo **Gatekeeper** dentro de AKS: impedir contenedores privilegiados, exigir `requests/limits`, permitir solo imágenes de tu ACR, impedir `hostNetwork`.

---

## 6. AWS: SCP, Config y Control Tower

### 6.1 SCP: solo regiones aprobadas

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "SoloRegionesAprobadas",
    "Effect": "Deny",
    "NotAction": ["iam:*", "organizations:*", "route53:*", "cloudfront:*", "support:*", "sts:*"],
    "Resource": "*",
    "Condition": {
      "StringNotEquals": { "aws:RequestedRegion": ["us-east-1", "us-east-2"] }
    }
  }]
}
```
Los servicios **globales** se dejan fuera con `NotAction` para que sigan funcionando.

### 6.2 Otras herramientas

| Herramienta | Para qué |
|---|---|
| **AWS Config** | Reglas que detectan (por ejemplo, "bucket S3 con lectura pública") |
| **Control Tower** | Guardarraíles preventivos (SCP) y de detección (Config) + cuentas base |
| **Tag Policies** | Estandarizar claves y valores de etiquetas |
| **Permissions boundaries** | Techo por rol o usuario |
| **Service Quotas** | Límites de capacidad |

---

## 7. OCI: Security Zones y Cloud Guard

| Herramienta | Qué hace |
|---|---|
| **Security Zones** | Se asocian a un **compartimento** con una *receta*; **rechazan** acciones que incumplen (por ejemplo, un bucket público o recursos sin cifrar con clave propia) |
| **Cloud Guard** | **Detecta** configuraciones y comportamientos de riesgo y puede responder automáticamente |
| **Quotas** | Limitan la cantidad de recursos por compartimento |
| **Tag defaults** | Etiquetas por defecto o **obligatorias** en un compartimento |
| **Políticas de IAM** | Controlan **quién** (módulo 03) |

---

## 8. GCP: Organization Policy

| Constraint (ejemplos) | Efecto |
|---|---|
| `constraints/gcp.resourceLocations` | Restringe las regiones donde se crean recursos |
| `constraints/compute.vmExternalIpAccess` | Controla qué VM pueden tener IP externa |
| `constraints/storage.publicAccessPrevention` | Impide acceso público a buckets |
| `constraints/iam.disableServiceAccountKeyCreation` | Impide crear llaves de cuentas de servicio |
| `constraints/sql.restrictPublicIp` | Impide IP pública en Cloud SQL |

```yaml
# politica.yaml
name: projects/mi-proyecto/policies/storage.publicAccessPrevention
spec:
  rules:
    - enforce: true
```
```bash
gcloud org-policies set-policy politica.yaml
```

Complementos: **Security Command Center** (hallazgos), **Cloud Asset Inventory** (inventario) y **VPC Service Controls** (perímetros para evitar la exfiltración de datos).

---

## 9. De la política de red (módulo 02) a la implementación

| Regla | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| NET-02/03 Sin IP pública en los backends | Policy "NICs sin IP pública" + `Deny` | SCP que niega asociar IP elásticas / Config | Security Zone (sin IP pública) | `compute.vmExternalIpAccess` |
| NET-03 PaaS con acceso público deshabilitado | Policies de `publicNetworkAccess` por servicio | SCP / Config / políticas de recurso | Security Zone / reglas | `storage.publicAccessPrevention`, `sql.restrictPublicIp` |
| NET-05 Sin claves de larga duración | Policy para deshabilitar claves locales | SCP que niega `iam:CreateAccessKey` | Reglas de IAM | `iam.disableServiceAccountKeyCreation` |
| NET-08 Logs de flujo activos | `DeployIfNotExists` para flow logs | Config + remediación | Cloud Guard / automatización | Constraint + automatización |
| NET-12 Región permitida | "Allowed locations" | SCP por `aws:RequestedRegion` | Quotas / políticas | `gcp.resourceLocations` |

---

## 10. Gobierno de costos

| Medida | Cómo |
|---|---|
| **Presupuesto con alerta** | Por suscripción / cuenta / proyecto, con avisos al 50 / 80 / 100 % |
| **Etiquetas obligatorias** | `owner`, `env`, `app`, `cost-center` con `Deny` o `Modify` |
| **SKU permitidos** | Política que impide tamaños muy caros en dev/QA |
| **Apagado programado** | Automatización para apagar entornos de prueba de noche |
| **Detección de anomalías** | Alertas de gasto inusual |
| **Informes por equipo** | *Showback* (mostrar) o *chargeback* (cobrar) por etiqueta |

Herramientas: **Cost Management + Budgets** (Azure), **Cost Explorer + Budgets** (AWS), **Cost Analysis + Budgets** (OCI), **Billing reports + Budgets** (GCP).

---

## 11. Casos de uso de vida real

### Caso 1 · "Nadie crea IP públicas en Corp"
- **Problema:** una VM de pruebas con IP pública y RDP abierto quedó olvidada durante meses.
- **Solución:** política `Deny` en el grupo de administración `Corp`; las excepciones pasan por una exención con fecha.
- **Resultado:** cero IP públicas nuevas; las pruebas se hacen por Bastion.
- **Lección:** prevenir es mejor que detectar.

### Caso 2 · Etiquetas obligatorias para saber quién gasta
- **Problema:** nadie sabía de quién eran el 30 % de los recursos.
- **Solución:** política de etiqueta `owner` (primero `Audit` un mes, luego `Deny`) y `Modify` que hereda `env` del grupo de recursos.
- **Resultado:** informes de costo por equipo.
- **Lección:** introduce la regla **auditando** antes de bloquear.

### Caso 3 · Regiones por normativa
- **Problema:** los datos de clientes solo podían estar en ciertas regiones.
- **Solución:** "Allowed locations" en la raíz (Azure), SCP por región (AWS) o `gcp.resourceLocations` (GCP).
- **Lección:** el límite geográfico se pone **arriba** de todo.

### Caso 4 · "El despliegue falló por una política"
- **Problema:** un pipeline devolvía `RequestDisallowedByPolicy`.
- **Cómo se resuelve:** el error indica la **asignación** que bloqueó; se revisa qué propiedad incumple (por ejemplo, `publicNetworkAccess`) y se corrige la plantilla. Una excepción solo si hay motivo y fecha.
- **Lección:** el mensaje del error ya dice qué regla y qué campo; léelo completo.

### Caso 5 · 200 recursos antiguos que no cumplen
- **Problema:** al activar una política, el informe mostró cientos de incumplimientos preexistentes.
- **Solución:** **tarea de remediación** para lo que puede corregirse automáticamente (`Modify`/`DeployIfNotExists`) y plan por equipo para el resto.
- **Lección:** `Deny` afecta lo **nuevo**; lo **existente** se corrige con remediación.

---

## 12. Qué hacer / qué NO hacer

**Qué hacer**
- Empezar con `Audit`, medir y luego `Deny`.
- Asignar políticas **arriba** y usar parámetros.
- Agrupar en **iniciativas** y versionar las definiciones como código.
- Documentar y **caducar** las exenciones.
- Combinar **prevención + detección + remediación**.
- Revisar el cumplimiento de forma periódica.
- Reservar un entorno **sandbox** con reglas más laxas y presupuesto estricto.

**Qué NO hacer**
- Activar `Deny` masivo sin avisar a los equipos.
- Crear exenciones permanentes y sin dueño.
- Usar políticas para compensar un diseño de permisos pobre.
- Aplicar políticas distintas por proyecto sin criterio común.
- Usar `ReadOnly` locks sin probar: pueden romper operaciones normales (por ejemplo, escalar o rotar claves).
- Olvidar la identidad de remediación (la tarea fallará por falta de permisos).

---

## 13. Troubleshooting

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| Azure `RequestDisallowedByPolicy` | Una política `Deny` bloqueó el recurso | El mensaje incluye la asignación y la política | Corregir la configuración o pedir exención con fecha |
| La política no evalúa un recurso | Modo `Indexed` vs `All`, alias o alcance | Definición y asignación | Ajustar el modo/alias y el alcance |
| Cumplimiento no se actualiza | Ciclo de evaluación pendiente | Estado de la asignación | `az policy state trigger-scan` y esperar |
| La remediación falla | La identidad de la asignación no tiene permisos | Roles de la identidad | Darle el rol necesario en el alcance |
| AWS "explicit deny in a service control policy" | Una SCP del nivel superior | Árbol de OUs y SCP asociadas | Ajustar la SCP o mover la cuenta |
| GCP "constraint … violated" | Org Policy bloquea la acción | Políticas efectivas del proyecto | Cumplir la restricción o aprobar excepción en el nivel adecuado |
| OCI rechaza crear recurso en Security Zone | La receta lo prohíbe | Mensaje de violación | Cumplir la receta o usar otro compartimento |
| Operación bloqueada que "debería funcionar" | Lock `ReadOnly` | `az lock list` | Quitar el bloqueo con control de cambios |

---

## 14. IAM del módulo

| Quién | Qué hace | Rol mínimo (Azure) |
|---|---|---|
| Equipo de gobierno | Crear y asignar políticas | Resource Policy Contributor |
| Administradores de la organización | Gestionar la jerarquía | Management Group Contributor |
| Auditoría | Ver cumplimiento | Reader + Security Reader |
| Identidad de remediación | Corregir recursos | Rol mínimo según la remediación (por ejemplo, Contributor acotado) |

Equivalentes: administradores de Organizations (AWS), políticas de IAM de la tenancy (OCI) y *Organization Policy Administrator* (GCP).

---

## 15. Repaso y entrevista

**Repaso**
1. ¿Qué diferencia hay entre IAM y política?
2. ¿Por qué se empieza en `Audit` y no en `Deny`?
3. ¿Qué hace una SCP y qué **no** puede hacer?
4. ¿Cómo corriges recursos que ya existían antes de la política?
5. ¿Qué equivale a Azure Policy en OCI y GCP?

**Entrevista**
- Diseña los guardarraíles mínimos para una organización nueva en la nube.
- Un equipo reporta que "la política le bloquea el despliegue": ¿cómo lo diagnosticas?
- ¿Cómo evitas que alguien cree una base de datos con IP pública en las 4 nubes?
