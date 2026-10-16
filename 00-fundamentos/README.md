# 00 · Fundamentos de nube

Base común para las 4 nubes: **Azure**, **AWS**, **Oracle Cloud (OCI)** y **Google Cloud (GCP)**. Si entiendes este módulo, el resto se vuelve "lo mismo con otro nombre".

---

## 1. ¿Qué es "la nube"?

**Definición simple:** alquilar capacidad de cómputo, red, almacenamiento y servicios de otra empresa, pagando por lo que usas, y manejándola por internet o API.

**Analogía:** la luz de tu casa. Antes cada fábrica tenía su generador (servidores propios, *on-premises*). Ahora te conectas a la red eléctrica: no te preocupas por la turbina, solo por cuánto consumes.

| Antes (on-premises) | Nube |
|---|---|
| Compras servidores por adelantado | Pagas por uso |
| Semanas para tener un servidor | Minutos |
| Tú cambias discos y cables | El proveedor lo hace |
| Capacidad fija | Crece o baja según demanda |

**Cuándo NO conviene:** carga muy estable y predecible 24/7 por años con hardware ya pagado, o datos que por ley no pueden salir de tu país (a veces se resuelve con una región local; otras veces no).

---

## 2. IaaS, PaaS, FaaS, SaaS (la analogía de la pizza)

| Modelo | Analogía | Tú manejas | Ejemplo |
|---|---|---|---|
| On-premises | Pizza hecha en casa | Todo | Tu data center |
| **IaaS** | Compras la masa y horneas | SO, runtime, app, datos | Máquina virtual |
| **PaaS** | Pides delivery | App y datos | App Service, RDS |
| **FaaS** | Pides solo una porción | Solo tu función | Functions, Lambda |
| **SaaS** | Vas al restaurante | Solo usas | Microsoft 365, Gmail |

Equivalencias por modelo:

| Modelo | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| Máquina virtual (IaaS) | Virtual Machines | EC2 | Compute | Compute Engine |
| Web/API administrada (PaaS) | App Service | App Runner / Elastic Beanstalk | Container Instances / Compute | Cloud Run / App Engine |
| Kubernetes administrado | AKS | EKS | OKE | GKE |
| Funciones (FaaS) | Function Apps | Lambda | Functions | Cloud Run functions (antes Cloud Functions) |
| Base de datos administrada | Azure SQL / PostgreSQL | RDS / Aurora | Autonomous DB / MySQL HeatWave | Cloud SQL / AlloyDB |

> Regla práctica: **cuanto más PaaS, menos operas y menos controlas**. Elige el nivel más alto que cubra tu necesidad.

---

## 3. Regiones y zonas

| Concepto | Qué es | Azure | AWS | OCI | GCP |
|---|---|---|---|---|---|
| Región | Zona geográfica con varios data centers | Region | Region | Region | Region |
| Zona de disponibilidad | Data center(s) aislados dentro de la región | Availability Zone | Availability Zone | Availability Domain (algunas regiones tienen uno solo) + Fault Domain | Zone |

**Cómo elegir región (en este orden):**
1. **Latencia** hacia tus usuarios.
2. **Normativa** de datos.
3. **Servicios disponibles** (no todo está en todas las regiones).
4. **Costo** (varía por región).
5. **Región de respaldo** para recuperación ante desastres.

**Alta disponibilidad (HA) vs recuperación ante desastres (DR):**

| | HA | DR |
|---|---|---|
| Protege contra | Falla de un servidor o zona | Caída de una región completa |
| Cómo | Varias zonas | Otra región |
| Costo | Medio | Más alto |

- **RPO:** cuántos datos puedes perder (en tiempo).
- **RTO:** cuánto tiempo puedes estar caído.

---

## 4. Jerarquía de recursos (¿dónde "vive" cada cosa?)

| Nivel | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| Identidad raíz | Tenant (Microsoft Entra ID) | Organization (root) | Tenancy | Organization |
| Agrupación de gobierno | Management Group | Organizational Unit (OU) | Compartment padre | Folder |
| Unidad de facturación y aislamiento | **Subscription** | **Account** | **Compartment** (dentro de la tenancy) | **Project** |
| Agrupación de recursos | Resource Group | (tags / CloudFormation stacks) | Compartment | Project |
| Recurso | VM, VNet, etc. | EC2, VPC, etc. | Instance, VCN, etc. | VM, VPC, etc. |

```
Azure:  Tenant → Management Group → Subscription → Resource Group → Recurso
AWS:    Organization → OU → Account → Recurso (por región)
OCI:    Tenancy → Compartment (anidables) → Recurso
GCP:    Organization → Folder → Project → Recurso
```

**Por qué importa:** permisos, políticas y costos se **heredan hacia abajo**. Un permiso en el nivel alto aplica a todo lo que cuelga.

**Diferencias reales:**
- En **Azure** el Resource Group es un contenedor lógico y los permisos suelen darse ahí.
- En **AWS** el aislamiento fuerte es la **cuenta**; muchas empresas usan una por entorno.
- En **OCI** el **compartimento** es la pieza central: las políticas se escriben apuntando a un compartimento.
- En **GCP** el **proyecto** es la unidad principal de recursos, APIs y facturación.

**Buena práctica común:** separar producción de no producción en suscripciones / cuentas / proyectos distintos.

---

## 5. Responsabilidad compartida

La nube asegura la infraestructura; **tú aseguras lo que pones encima**.

| Capa | IaaS | PaaS | SaaS |
|---|---|---|---|
| Datos y accesos | Tú | Tú | Tú |
| Aplicación | Tú | Tú | Proveedor |
| Sistema operativo | Tú | Proveedor | Proveedor |
| Red virtual (reglas) | Tú | Compartido | Proveedor |
| Hardware y data center | Proveedor | Proveedor | Proveedor |

**Lo que casi siempre es tu responsabilidad:** quién tiene acceso, qué está público, cifrado de tus datos, secretos, parches de lo que instalas.

---

## 6. Cómo se habla con la nube

| Forma | Para qué | Cuándo |
|---|---|---|
| Portal web | Explorar y aprender | Primeros pasos |
| CLI | Comandos reproducibles | Labs, scripts |
| SDK | Desde tu código Java | Aplicaciones |
| IaC (Terraform, Bicep…) | Infraestructura como código | Todo lo serio |
| API REST | Integraciones | Casos avanzados |

| | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| CLI | `az` | `aws` | `oci` | `gcloud` |
| Login | `az login` | `aws configure` o `aws sso login` | `oci session authenticate` | `gcloud auth login` |
| Elegir destino | `az account set --subscription <id>` | `--profile` o variable `AWS_PROFILE` | `--profile` | `gcloud config set project <id>` |
| Consola en el navegador | Cloud Shell | CloudShell | Cloud Shell | Cloud Shell |

> **Regla de oro:** si lo haces dos veces por portal, ya debería ser código.

---

## 7. Costos

**Modelos de pago:**

| Modelo | Idea | Cuándo |
|---|---|---|
| Bajo demanda (pay as you go) | Pagas por uso | Pruebas, cargas variables |
| Reservado / compromiso | Descuento por comprometer 1–3 años | Carga estable |
| Spot / preemptible | Muy barato, pueden quitártelo | Procesos tolerantes a fallos |

**Herramientas de costo:**

| Azure | AWS | OCI | GCP |
|---|---|---|---|
| Cost Management + Budgets | Cost Explorer + Budgets | Cost Analysis + Budgets | Billing reports + Budgets |

**Lo que más sorprende en la factura:** tráfico de salida a internet, IPs públicas ociosas, discos sin adjuntar, clústeres encendidos de noche, logs sin límite de retención.

---

## 8. Etiquetas (tags / labels)

Pares clave–valor para saber **de quién es** y **cuánto cuesta** cada recurso.

| Azure | AWS | OCI | GCP |
|---|---|---|---|
| Tags | Tags | Tags (freeform y defined) | Labels |

Mínimo recomendado: `owner`, `env` (dev/qa/prod), `app`, `cost-center`.

---

## 9. Convenciones de nombres

Un patrón: `<tipo>-<app>-<entorno>-<región>`.

| Tipo | Prefijo Azure (ejemplo) |
|---|---|
| Resource Group | `rg-modalima-prod-eus2` |
| VNet | `vnet-modalima-prod-eus2` |
| Subnet | `snet-app` |
| NSG | `nsg-app` |
| AKS | `aks-modalima-prod` |
| Key Vault | `kv-modalima-prod` |
| Storage | `stmodalimaprod` (sin guiones, minúsculas) |

Los nombres de **storage** y algunos servicios son **únicos globalmente**: tendrás que variarlos.

---

## 10. Caso real inventado: ModaLima

**Empresa:** tienda online de ropa, 6 personas de tecnología.

- **Problema:** en campaña, el servidor propio se caía; en meses normales, estaba ocioso.
- **Primer paso:** mover el sitio a un servicio PaaS (App Service / equivalente) con escalado automático.
- **Segundo paso:** base de datos administrada, con backups automáticos.
- **Tercer paso:** separar `dev`, `qa` y `prod` en suscripciones distintas y poner un presupuesto con alerta.
- **Resultado:** cero caídas en la siguiente campaña y factura previsible.
- **Lección:** la nube no es "poner el servidor en otro lado"; es **cambiar a servicios administrados, separar entornos y controlar costos**.

---

## 11. Qué hacer / qué NO hacer

**Qué hacer**
- Activar **MFA** en todas las cuentas administradoras.
- Crear un **presupuesto con alerta** el primer día.
- Separar entornos (suscripción / cuenta / proyecto distinto).
- Usar **etiquetas** y **convenciones de nombres** desde el inicio.
- Dar **mínimo privilegio** a personas y aplicaciones.
- Guardar todo en **código** (Terraform) y en Git.

**Qué NO hacer**
- Usar la cuenta raíz o el administrador global para el día a día.
- Dejar recursos de prueba encendidos.
- Poner IP pública a todo "para que funcione".
- Guardar claves o secretos en el repositorio.
- Crear recursos a mano en producción sin dejar rastro.
- Elegir región sin revisar servicios disponibles.

---

## 12. Glosario

| Término | Significado simple |
|---|---|
| Tenant / Tenancy | Tu "empresa" dentro del proveedor, con sus identidades |
| Suscripción / Cuenta / Proyecto | Contenedor de recursos y facturación |
| Región | Zona geográfica |
| Zona de disponibilidad | Data center aislado dentro de una región |
| IaaS / PaaS / SaaS | Cuánto administras tú vs el proveedor |
| IaC | Infraestructura definida en código |
| IAM | Quién puede hacer qué |
| Mínimo privilegio | Dar solo los permisos necesarios |
| Recurso | Cualquier cosa creada (VM, red, base de datos) |
| SLA | Disponibilidad prometida por el proveedor |
| RPO / RTO | Datos que puedes perder / tiempo que puedes estar caído |
| Escalado horizontal | Más instancias |
| Escalado vertical | Instancia más grande |
| Serverless | Sin administrar servidores; pagas por ejecución |

---

## 13. Preguntas de repaso

1. ¿Qué diferencia hay entre IaaS y PaaS? Da un ejemplo en cada nube.
2. ¿Qué equivale a una Suscripción de Azure en AWS, OCI y GCP?
3. ¿Qué es la responsabilidad compartida y qué parte siempre es tuya?
4. ¿Qué diferencia hay entre HA y DR?
5. Nombra tres cosas que suelen inflar la factura sin que lo notes.

**Entrevista**
- ¿Cómo organizarías cuentas/suscripciones para una empresa con dev, qa y prod?
- ¿Por qué usar IaC en lugar del portal?
- ¿Cuándo elegirías PaaS y cuándo Kubernetes?

---

## 14. Resumen de equivalencias de nombres

| Concepto | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| Red virtual | VNet | VPC | VCN | VPC |
| Kubernetes | AKS | EKS | OKE | GKE |
| Funciones | Function Apps | Lambda | Functions | Cloud Run functions |
| Objetos | Blob Storage | S3 | Object Storage | Cloud Storage |
| Secretos | Key Vault | Secrets Manager + KMS | Vault | Secret Manager + KMS |
| Identidad | Entra ID + RBAC | IAM | IAM + Compartments | Cloud IAM |
| API gateway | API Management | API Gateway | API Gateway | API Gateway / Apigee |
| Streaming | Event Hubs | Kinesis / MSK | Streaming | Pub/Sub / Managed Kafka |
| Políticas | Azure Policy | SCP / Config | Security Zones | Organization Policy |
