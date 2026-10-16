# Azure · 00 Fundamentos

Todo lo que necesitas entender de Azure **antes** de tocar un servicio concreto: dónde vive cada recurso, cómo se organizan los permisos y los costos, cómo se habla con la nube y cómo se nombran las cosas.

---

## 1. Qué es Azure (con analogía)

**Azure es el edificio de oficinas de Microsoft donde alquilas pisos, salas y servicios por uso.** No compras el edificio: pagas lo que ocupas, y Microsoft se encarga del mantenimiento, la electricidad y la seguridad de la puerta principal. Tú decides quién entra a tu piso y qué guardas dentro.

---

## 2. Cómo funciona por dentro: la jerarquía de recursos

Todo recurso de Azure (una VNet, un AKS, una base de datos) vive dentro de esta cadena:

```
Tenant (Microsoft Entra ID)           ← tu "empresa" y sus identidades
  └── Management Group                ← agrupa suscripciones, hereda políticas y permisos
        └── Subscription              ← contenedor de facturación y límites
              └── Resource Group      ← carpeta lógica de recursos
                    └── Recurso       ← VM, VNet, Key Vault, AKS...
```

| Nivel | Qué es | Para qué lo usas |
|---|---|---|
| **Tenant** | Instancia de Microsoft Entra ID (antes Azure AD). Guarda usuarios, grupos y aplicaciones | Identidad de toda la empresa |
| **Management Group** | Contenedor de suscripciones, anidable | Aplicar una política o rol a muchas suscripciones a la vez |
| **Subscription** | Unidad de **facturación**, **cuotas** y **aislamiento** | Separar prod de no-prod, o un equipo de otro |
| **Resource Group** | Carpeta lógica. Todo recurso pertenece a **uno** | Agrupar lo que vive y muere junto; asignar permisos |
| **Recurso** | El servicio en sí | — |

**Regla de herencia:** un permiso (RBAC), una política (Azure Policy) o un bloqueo puesto en un nivel **aplica a todo lo que cuelga debajo**.

**Resource Group: reglas que conviene saber**
- Un recurso está en un solo grupo, pero puede **hablar** con recursos de otros grupos.
- Borrar el grupo **borra todo lo que contiene** (por eso `az group delete` es tu comando de limpieza).
- La ubicación del grupo solo guarda sus metadatos; sus recursos pueden estar en otras regiones.
- Agrupa por **ciclo de vida**: lo que se despliega y se borra junto, va junto.

---

## 3. Regiones, zonas y pares de regiones

| Concepto | Qué es |
|---|---|
| **Región** | Zona geográfica con uno o más centros de datos (por ejemplo `eastus2`, `brazilsouth`) |
| **Availability Zone (AZ)** | Centros de datos físicamente separados dentro de una región. Protegen de la caída de un edificio |
| **Región emparejada** | Región "hermana" pensada para recuperación ante desastres (verifica los pares en la doc oficial) |

**Alta disponibilidad (HA) vs recuperación ante desastres (DR)**

| | HA | DR |
|---|---|---|
| Protege contra | Falla de un servidor o una zona | Caída de una región entera |
| Cómo en Azure | Recursos *zone-redundant* (varias AZ) | Otra región, replicación geográfica |
| Costo | Medio | Más alto |

- **RPO**: cuántos datos puedes perder (en tiempo).
- **RTO**: cuánto tiempo puedes estar caído.

**Cómo elegir región (en este orden):** latencia hacia tus usuarios → normativa de datos → servicios disponibles (no todo está en todas las regiones) → costo → región de respaldo.

> Para usuarios en Perú, revisa qué regiones de Sudamérica ofrecen los servicios que necesitas y compara latencia real; no asumas que la más cercana en mapa es la mejor.

---

## 4. Modelos de servicio con nombres de Azure

| Modelo | Tú manejas | Servicio de Azure |
|---|---|---|
| **IaaS** | SO, runtime, app, datos | Virtual Machines, VM Scale Sets |
| **CaaS / Kubernetes** | Contenedores y manifiestos | AKS, Container Apps |
| **PaaS** | App y datos | App Service, Azure SQL, PostgreSQL Flexible Server |
| **FaaS / Serverless** | Solo tu función | Azure Functions |
| **SaaS** | Solo usas | Microsoft 365 |

> Regla práctica: **cuanto más PaaS, menos operas y menos controlas**. Elige el nivel más alto que cubra tu necesidad.

---

## 5. Responsabilidad compartida

Azure asegura la infraestructura; **tú aseguras lo que pones encima**.

| Capa | IaaS (VM) | PaaS (App Service, SQL) | SaaS |
|---|---|---|---|
| Datos y accesos | Tú | Tú | Tú |
| Aplicación | Tú | Tú | Microsoft |
| Sistema operativo y parches | Tú | Microsoft | Microsoft |
| Red virtual (reglas, qué es público) | Tú | Compartido | Microsoft |
| Hardware y centro de datos | Microsoft | Microsoft | Microsoft |

**Siempre es tuyo:** quién tiene acceso, qué está público, el cifrado de tus datos, los secretos y los parches de lo que instalas.

---

## 6. Cómo se habla con Azure

| Forma | Para qué | Cuándo |
|---|---|---|
| **Portal** (portal.azure.com) | Explorar y aprender | Primeros pasos, revisar estado |
| **Cloud Shell** | Terminal en el navegador, ya autenticada | Probar rápido sin instalar nada |
| **Azure CLI** (`az`) | Comandos reproducibles | Labs y scripts |
| **PowerShell** (`Az`) | Lo mismo, estilo PowerShell | Equipos Windows |
| **SDK** (Java: `com.azure:*`) | Desde tu código | Aplicaciones |
| **IaC** (Terraform, Bicep) | Infraestructura como código | Todo lo serio |
| **REST API / Azure Resource Manager (ARM)** | Integraciones | Casos avanzados |

Todo pasa por **Azure Resource Manager (ARM)**: el portal, la CLI y Terraform le piden lo mismo a ARM. Por eso un recurso creado por el portal aparece al instante en la CLI.

```bash
az login                                      # inicia sesión
az account list -o table                      # ver suscripciones
az account set --subscription "<NOMBRE-O-ID>" # elegir sobre cuál trabajar
az account show                               # confirmar dónde estás parado
az group create -n rg-estudio -l eastus2
az group delete -n rg-estudio --yes --no-wait # limpieza
```

> **Antes de crear nada, ejecuta `az account show`.** El error más caro es crear recursos en la suscripción equivocada.

---

## 7. Costos

**Modelos de pago**

| Modelo | Idea | Cuándo |
|---|---|---|
| Pay-as-you-go | Pagas por uso | Pruebas, cargas variables |
| Reservations / Savings Plan | Descuento por comprometer 1 o 3 años | Carga estable |
| Spot | Muy barato; Azure puede quitártelo | Procesos tolerantes a fallos |

**Herramientas:** Microsoft Cost Management (análisis, presupuestos, alertas) y Azure Advisor (recomendaciones).

```bash
# Presupuesto mensual con alerta (verifica los parámetros vigentes en la doc oficial)
az consumption budget create --budget-name presupuesto-estudio \
  --amount 20 --time-grain Monthly \
  --start-date 2026-11-01 --end-date 2027-10-31 \
  --category cost
```

**Lo que más sorprende en la factura:** tráfico de salida, IP públicas y balanceadores ociosos, discos sin adjuntar, clústeres encendidos de noche, retención de logs sin límite, Private Endpoints olvidados.

---

## 8. Etiquetas y nombres

**Tags** (pares clave–valor) para saber de quién es y cuánto cuesta cada recurso. Mínimo: `owner`, `env`, `app`, `cost-center`.

```bash
az group create -n rg-modalima-dev-eus2 -l eastus2 \
  --tags owner=hugo env=dev app=modalima cost-center=ti
```

**Patrón de nombre:** `<tipo>-<app>-<entorno>-<región>`.

| Recurso | Ejemplo | Nota |
|---|---|---|
| Resource Group | `rg-modalima-prod-eus2` | |
| VNet | `vnet-modalima-prod-eus2` | |
| Subnet | `snet-app` | |
| NSG | `nsg-app` | |
| AKS | `aks-modalima-prod` | |
| Key Vault | `kv-modalima-prod` | Nombre único global, 3–24 caracteres |
| Storage Account | `stmodalimaprod` | Único global, 3–24, solo minúsculas y números |

---

## 9. Seguridad básica desde el día 1

- **MFA** en todas las cuentas con rol alto.
- No uses la cuenta de administrador global para el día a día.
- **Privileged Identity Management (PIM)** para roles elevados temporales (requiere licencia Entra ID P2: verifica).
- **Microsoft Defender for Cloud** para ver el estado de seguridad.
- **Activity Log** (quién hizo qué en el plano de control) enviado a un Log Analytics Workspace.

---

## 10. Caso real inventado: ModaLima

Tienda online de ropa, 6 personas de tecnología.

- **Problema:** en campaña el servidor propio se caía; el resto del año estaba ocioso.
- **Paso 1:** mover el sitio a **App Service** con escalado automático.
- **Paso 2:** base de datos **Azure SQL** con copias automáticas.
- **Paso 3:** separar `dev`, `qa` y `prod` en **suscripciones distintas** bajo un Management Group, con un presupuesto y alerta por cada una.
- **Resultado:** cero caídas en la siguiente campaña y factura predecible.
- **Lección:** la nube no es "poner el servidor en otro lado"; es cambiar a servicios administrados, separar entornos y controlar costos.

---

## 11. Qué hacer y qué NO hacer

**Qué hacer**
- Separar entornos en suscripciones distintas bajo Management Groups.
- Crear un presupuesto con alerta el primer día.
- Etiquetar y nombrar con convención desde el inicio.
- Dar **mínimo privilegio** y por Resource Group, no por suscripción entera.
- Todo en código (Terraform/Bicep) y en Git.

**Qué NO hacer**
- Trabajar con Owner a nivel de suscripción "para que no falle".
- Crear recursos en la suscripción equivocada por no verificar `az account show`.
- Dejar recursos de prueba encendidos.
- Poner IP pública a todo "para que funcione".
- Guardar claves en el repositorio.
- Elegir región sin revisar los servicios disponibles.

---

## 12. Glosario

| Término | Significado simple |
|---|---|
| Tenant | Tu "empresa" en Microsoft, con sus identidades (Entra ID) |
| Subscription | Contenedor de facturación y límites |
| Resource Group | Carpeta lógica de recursos |
| ARM | El servicio que recibe toda orden de crear o cambiar recursos |
| RBAC | Control de acceso por roles sobre recursos de Azure |
| Región / AZ | Zona geográfica / centro de datos aislado dentro de ella |
| SKU | Nivel o "talla" de un servicio (Basic, Standard, Premium) |
| SLA | Disponibilidad prometida por Microsoft para un servicio |
| RPO / RTO | Datos que puedes perder / tiempo que puedes estar caído |
| IaC | Infraestructura definida en código |
| Serverless | No administras servidores; pagas por ejecución |
