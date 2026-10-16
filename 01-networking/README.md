# 01 · Networking: VNet, subnets, NSG, rutas, peering y Private Endpoint

Todo lo que se comunica en la nube viaja por una red virtual. Este módulo explica sus piezas en **Azure** y su equivalente en **AWS**, **OCI** y **GCP**.

---

## 1. Qué es (con analogía)

**Una red virtual es el edificio privado de tu empresa.** Las **subnets** son los pisos, las **reglas de seguridad** son los guardias de cada piso, las **tablas de rutas** son las señales que dicen por qué pasillo salir, y el **Private Endpoint** es una puerta interna hacia un servicio externo, sin salir a la calle.

| Pieza | Analogía |
|---|---|
| VNet / VPC / VCN | El edificio |
| Subnet | Un piso |
| NSG / Security Group | El guardia del piso |
| Tabla de rutas (UDR) | Las señales de "por aquí se sale" |
| NAT Gateway | La puerta de salida para visitas salientes |
| Peering | Un puente entre dos edificios |
| Private Endpoint | Una puerta interna al servicio de otro |
| DNS privado | La guía telefónica interna |

---

## 2. Para qué sirve y cuándo NO usarlo

**Sirve para:** aislar entornos, controlar quién habla con quién, evitar IP públicas, conectar con on-premises, cumplir normativa.

**Cuándo NO hace falta diseñar red:** pruebas rápidas con servicios PaaS públicos y sin datos sensibles. Aun así, en producción siempre debe haber un diseño de red.

---

## 3. Conceptos clave

### 3.1 Rangos privados y CIDR

Rangos privados estándar (RFC 1918): `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`.

| CIDR | IP totales | Uso típico |
|---|---|---|
| /16 | 65.536 | Toda la VNet |
| /20 | 4.096 | Subnet grande (nodos + pods) |
| /22 | 1.024 | Subnet mediana |
| /24 | 256 | Subnet normal |
| /26 | 64 | Subnets especiales (Firewall, Bastion) |
| /27 | 32 | Gateway de VPN |
| /28 | 16 | Subnet pequeña |

**IP reservadas por subnet (no las puedes usar):**

| Azure | AWS | OCI | GCP |
|---|---|---|---|
| 5 | 5 | 3 | 4 |

Una subnet `/24` en Azure tiene `256 - 5 = 251` direcciones útiles.

**Regla de oro:** planifica los rangos **antes** de crear nada y que **no se solapen** con otras redes ni con on-premises. Cambiarlo después duele mucho.

### 3.2 Alcance de la red y de las subnets

| | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| La red es... | Regional | Regional | Regional | **Global** |
| La subnet es... | Regional (cruza zonas) | De **una** zona (AZ) | Regional (recomendado) o por AD | Regional |

La VPC de GCP es global: una sola red puede tener subnets en varias regiones, sin peering entre ellas.

### 3.3 ¿Subnet pública o privada?

- **AWS:** una subnet es "pública" si su tabla de rutas tiene salida a un Internet Gateway.
- **OCI:** la subnet se declara pública o privada explícitamente.
- **Azure y GCP:** no existe ese rótulo; lo que hace "pública" a una máquina es **tener IP pública** y reglas que lo permitan.

### 3.4 Subnets con nombre obligatorio (Azure)

| Servicio | Nombre exacto de la subnet | Tamaño mínimo recomendado |
|---|---|---|
| Azure Firewall | `AzureFirewallSubnet` | /26 |
| VPN / ExpressRoute Gateway | `GatewaySubnet` | /27 |
| Azure Bastion | `AzureBastionSubnet` | /26 |

Otros servicios (APIM, AKS, Application Gateway) piden subnets **dedicadas**, aunque el nombre sea libre.

---

## 4. Componentes y equivalencias

| Concepto | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| Red virtual | VNet | VPC | VCN | VPC |
| Subnet | Subnet | Subnet | Subnet | Subnet |
| Filtro por recurso | NSG (en NIC) | Security Group | NSG | Reglas de firewall (por tag o service account) |
| Filtro por subnet | NSG (en subnet) | Network ACL | Security List | Reglas de firewall de la VPC |
| Rutas | Route Table (UDR) | Route Table | Route Table | Routes |
| Salida a internet | IP pública / NAT Gateway | Internet Gateway / NAT Gateway | Internet Gateway / NAT Gateway | IP externa / Cloud NAT |
| Peering entre redes | VNet Peering | VPC Peering | LPG (misma región) / RPC (otra región) | VPC Network Peering |
| Hub central (varias redes) | Hub VNet / Virtual WAN | Transit Gateway | DRG | Network Connectivity Center / Shared VPC |
| Acceso privado a servicio | **Private Endpoint** | **PrivateLink** (Interface Endpoint) | Private Endpoint | **Private Service Connect** |
| Acceso privado a storage/DB de la nube | Service Endpoint | Gateway Endpoint (S3, DynamoDB) | Service Gateway | Private Google Access |
| DNS privado | Private DNS Zone | Route 53 Private Hosted Zone | Private DNS | Cloud DNS (zona privada) |
| VPN | VPN Gateway | Site-to-Site VPN | Site-to-Site VPN | Cloud VPN |
| Conexión dedicada | ExpressRoute | Direct Connect | FastConnect | Cloud Interconnect |
| Firewall administrado | Azure Firewall | Network Firewall | Network Firewall | Cloud NGFW |
| Acceso admin sin IP pública | Azure Bastion | Systems Manager Session Manager | Bastion | IAP (Identity-Aware Proxy) |

### Diferencias reales (no son 1 a 1)

- **Security Group (AWS) vs NSG (Azure):** el SG de AWS solo **permite** (no tiene reglas deny); la NACL sí permite y niega, y es **sin estado**. El NSG de Azure permite y niega, con estado.
- **Todo habla con todo dentro de una VNet de Azure** por defecto (regla `AllowVnetInBound`). En AWS, un Security Group nuevo **no** permite entrada hasta que lo abras.
- **GCP** aplica el firewall a nivel de red virtual y lo dirige por etiquetas o service accounts, no por subnet.
- **OCI** tiene Security Lists y NSG a la vez; las reglas de ambos se **suman**.

---

## 5. Cómo funciona un NSG de Azure (el que más se usa mal)

Cada NSG trae reglas por defecto que no puedes borrar, solo superar con otra de menor número:

| Prioridad | Nombre | Qué hace |
|---|---|---|
| 65000 | AllowVnetInBound | Permite todo lo que venga de la misma VNet |
| 65001 | AllowAzureLoadBalancerInBound | Permite el balanceador de Azure |
| 65500 | DenyAllInBound | Niega todo lo demás |
| 65000 | AllowVnetOutBound | Permite salida dentro de la VNet |
| 65001 | AllowInternetOutBound | Permite salida a internet |
| 65500 | DenyAllOutBound | Niega todo lo demás |

**Cómo se evalúa:** de **menor número a mayor**. La primera regla que coincide **gana** y se deja de evaluar.

**Consecuencia importante:** si quieres que la subnet de datos **solo** reciba tráfico desde la subnet de aplicación, no basta con una regla de permitir. Debes agregar una regla **de negar** con número menor que 65000, porque si no, `AllowVnetInBound` deja pasar a todos los de la VNet.

Ejemplo de reglas para la subnet de datos (puerto 1433):

| Prioridad | Nombre | Origen | Destino/puerto | Acción |
|---|---|---|---|---|
| 100 | allow-app-to-sql | 10.10.1.0/24 | 1433 | Allow |
| 4000 | deny-vnet-inbound | VirtualNetwork | cualquiera | Deny |

---

## 6. Casos de uso de vida real

### Caso 1 · App en tres capas para "Café Andino"

- **Problema:** una cafetería con pedidos online. La base de datos estaba accesible desde internet "porque era más fácil".
- **Solución:** una VNet `10.10.0.0/16` con tres subnets:
  - `snet-web` (10.10.0.0/24): recibe tráfico desde internet vía balanceador.
  - `snet-app` (10.10.1.0/24): solo acepta tráfico desde `snet-web` por el 443.
  - `snet-data` (10.10.2.0/24): solo acepta tráfico desde `snet-app` por el puerto de la base de datos. Sin IP pública.
- **Resultado:** la base de datos dejó de ser alcanzable desde internet; un escaneo externo no encontró nada.
- **Lección:** segmenta por capas y niega por defecto entre ellas.

### Caso 2 · Peering entre desarrollo y servicios compartidos

- **Problema:** "Café Andino" tenía una VNet `dev` y otra `shared` con el servidor de logs. Querían que `dev` enviara logs a `shared`.
- **Solución:** peering en **ambos sentidos** (hacia un lado y hacia el otro).
- **Sorpresa:** `dev` se conectó a `shared`, pero `qa`, que estaba peeriada con `shared`, **no** podía hablar con `dev`.
- **Resultado:** se entendió que el peering **no es transitivo**. Para que `dev` y `qa` se vean hay que peerearlas entre sí o usar un hub con firewall.
- **Lección:** peering = conexión punto a punto, nada más.

### Caso 3 · Base de datos "privada" que seguía saliendo por internet

- **Problema:** crearon un Private Endpoint para la base de datos, pero la aplicación seguía conectándose por la IP pública y fallaba cuando se deshabilitó el acceso público.
- **Causa:** la **zona DNS privada** no estaba enlazada a la VNet de la aplicación, así que el nombre resolvía a la IP pública.
- **Solución:** crear el enlace de la zona DNS privada a la VNet.
- **Resultado:** el nombre resolvió a `10.x.x.x` y todo volvió a funcionar sin exponer nada.
- **Lección:** Private Endpoint **sin DNS correcto = no funciona**. Siempre se revisa DNS primero.

---

## 7. Cómo se usa

### 7.1 Portal (idea general)

1. Crear **Resource Group**.
2. Crear **Virtual Network** con el espacio `10.10.0.0/16`.
3. Agregar subnets (`snet-web`, `snet-app`, `snet-data`).
4. Crear **NSG** por subnet y asociarlo.
5. Revisar **Effective security rules** en una NIC para confirmar qué reglas aplican de verdad.

### 7.2 Azure CLI

```bash
RG=rg-estudio-net
LOC=eastus2

az group create -n $RG -l $LOC

az network vnet create -g $RG -n vnet-estudio \
  --address-prefixes 10.10.0.0/16 \
  --subnet-name snet-web --subnet-prefixes 10.10.0.0/24

az network vnet subnet create -g $RG --vnet-name vnet-estudio \
  -n snet-app --address-prefixes 10.10.1.0/24

az network vnet subnet create -g $RG --vnet-name vnet-estudio \
  -n snet-data --address-prefixes 10.10.2.0/24

# NSG de la subnet de datos
az network nsg create -g $RG -n nsg-data

az network nsg rule create -g $RG --nsg-name nsg-data -n allow-app-to-sql \
  --priority 100 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes 10.10.1.0/24 --destination-port-ranges 1433

az network nsg rule create -g $RG --nsg-name nsg-data -n deny-vnet-inbound \
  --priority 4000 --direction Inbound --access Deny --protocol '*' \
  --source-address-prefixes VirtualNetwork --destination-port-ranges '*'

az network vnet subnet update -g $RG --vnet-name vnet-estudio \
  -n snet-data --network-security-group nsg-data
```

Peering (hay que crear **los dos sentidos**):

```bash
az network vnet peering create -g $RG -n hub-to-spoke \
  --vnet-name vnet-hub --remote-vnet vnet-spoke --allow-vnet-access

az network vnet peering create -g $RG -n spoke-to-hub \
  --vnet-name vnet-spoke --remote-vnet vnet-hub --allow-vnet-access
```

Limpieza:

```bash
az group delete -n $RG --yes --no-wait
```

### 7.3 Terraform (Azure)

```hcl
resource "azurerm_resource_group" "rg" {
  name     = "rg-estudio-net"
  location = "eastus2"
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-estudio"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.10.0.0/16"]
}

resource "azurerm_subnet" "data" {
  name                 = "snet-data"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.2.0/24"]
}

resource "azurerm_network_security_group" "data" {
  name                = "nsg-data"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "allow-app-to-sql"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefix      = "10.10.1.0/24"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-vnet-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "data" {
  subnet_id                 = azurerm_subnet.data.id
  network_security_group_id = azurerm_network_security_group.data.id
}
```

### 7.4 Los mismos conceptos en las otras tres nubes

<details>
<summary>AWS (Terraform)</summary>

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "vpc-estudio" }
}

resource "aws_subnet" "data" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.20.2.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "snet-data" }
}

resource "aws_security_group" "data" {
  name   = "sg-data"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "Base de datos solo desde la subnet de aplicacion"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.20.1.0/24"]
  }
}
```
</details>

<details>
<summary>OCI (Terraform)</summary>

```hcl
resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = ["10.30.0.0/16"]
  display_name   = "vcn-estudio"
  dns_label      = "estudio"
}

resource "oci_core_subnet" "data" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = "10.30.2.0/24"
  display_name               = "snet-data"
  prohibit_public_ip_on_vnic = true
}

resource "oci_core_network_security_group" "data" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "nsg-data"
}

resource "oci_core_network_security_group_security_rule" "db_from_app" {
  network_security_group_id = oci_core_network_security_group.data.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "10.30.1.0/24"
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 1521
      max = 1521
    }
  }
}
```
</details>

<details>
<summary>GCP (Terraform)</summary>

```hcl
resource "google_compute_network" "vpc" {
  name                    = "vpc-estudio"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "data" {
  name                     = "snet-data"
  region                   = "us-central1"
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = "10.40.2.0/24"
  private_ip_google_access = true
}

resource "google_compute_firewall" "db_from_app" {
  name      = "allow-app-to-db"
  network   = google_compute_network.vpc.name
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  source_ranges = ["10.40.1.0/24"]
  target_tags   = ["db"]
}
```
</details>

---

## 8. Private Endpoint, Service Endpoint y DNS privado

**Problema:** servicios como Storage o SQL tienen por defecto una dirección **pública**. Si quieres que tu app hable con ellos sin salir a internet, hay dos formas.

| | Service Endpoint | Private Endpoint |
|---|---|---|
| Qué hace | Sigue usando IP pública del servicio, pero el tráfico viaja por la red troncal y el servicio solo acepta tu subnet | Le da al servicio **una IP privada dentro de tu subnet** |
| ¿IP privada? | No | **Sí** |
| Alcanza on-premises | No | **Sí** (vía VPN/ExpressRoute) |
| Costo | Gratis | Se cobra por hora y por datos |
| Recomendado | Casos simples | **Producción** |

**Zonas DNS privadas más usadas en Azure** (la zona correcta depende del servicio):

| Servicio | Zona DNS privada |
|---|---|
| Blob Storage | `privatelink.blob.core.windows.net` |
| Azure SQL | `privatelink.database.windows.net` |
| PostgreSQL | `privatelink.postgres.database.azure.com` |
| Cosmos DB (SQL) | `privatelink.documents.azure.com` |
| Key Vault | `privatelink.vaultcore.azure.net` |
| Service Bus / Event Hubs | `privatelink.servicebus.windows.net` |
| Container Registry | `privatelink.azurecr.io` |
| App Service / Functions | `privatelink.azurewebsites.net` |
| API Management | `privatelink.azure-api.net` |

> Verifica la lista actual en la documentación oficial; los servicios agregan zonas con el tiempo.

Cómo se arma, paso a paso, está en el módulo [02](../02-comunicacion-privada-y-diagnostico/README.md).

---

## 9. Qué hacer

- Planificar rangos IP **antes** de crear nada y documentarlos en una hoja.
- Usar subnets **separadas por función** (web, app, datos, endpoints privados).
- Reservar una subnet solo para **Private Endpoints**.
- Aplicar **negar por defecto** entre capas, con reglas explícitas de permitir.
- Usar **NAT Gateway** para salida controlada y con IP pública fija.
- Habilitar **registros de flujo** (VNet flow logs / VPC Flow Logs) para auditar.
- Usar **Bastion** o equivalente para administrar máquinas, sin IP pública.
- Dejar espacio de crecimiento: una subnet de AKS con muchos pods necesita bloques grandes.

## 10. Qué NO hacer

- Usar rangos que se solapen con otras VNets o con on-premises (no se pueden conectar después).
- Subnets demasiado pequeñas para AKS, APIM o App Gateway.
- Abrir `0.0.0.0/0` hacia puertos de administración (22, 3389) o de bases de datos.
- Asumir que "como es privada, es segura": dentro de la VNet todo se habla por defecto en Azure.
- Esperar que el peering sea transitivo.
- Crear Private Endpoint y **olvidar el DNS**.
- Poner IP pública a máquinas "temporalmente" y no quitarla.
- Depender del acceso de salida **predeterminado** de Azure: la plataforma lo está retirando en subnets nuevas, así que define una salida explícita (NAT Gateway). Verifica fechas en la doc oficial.

---

## 11. Troubleshooting

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| Dos VNets peeriadas no se ven | Peering solo en un sentido o estado "Disconnected" | Estado del peering en ambos lados | Crear el peering faltante |
| Peering no se deja crear | Espacios de direcciones solapados | Comparar rangos | Rediseñar rangos |
| No hay salida a internet desde una VM | Sin NAT / IP pública, o NSG/UDR bloquea | Effective routes y NSG efectivo | Agregar NAT Gateway, revisar rutas |
| "Todo se ve con todo" dentro de la VNet | Falta regla de negar (`AllowVnetInBound`) | NSG efectivo de la NIC | Regla Deny de prioridad menor a 65000 |
| El nombre resuelve a IP pública pese al Private Endpoint | Zona DNS privada sin enlace a la VNet | `nslookup` desde dentro de la VNet | Crear el link de la zona |
| Una subnet "se llenó" | CIDR chico o muchos pods | IP disponibles en la subnet | Subnet más grande / modo overlay en AKS |
| Tráfico on-premises no llega a Azure | Rutas o rangos solapados | Tabla de rutas y rangos | Corregir rangos o rutas |

---

## 12. IAM del módulo

- Para crear redes basta el rol **Network Contributor** (Azure) sobre el grupo de recursos o la subnet, no hace falta Owner.
- Para **unirse a una subnet** (por ejemplo, que AKS cree un balanceador en tu subnet) la identidad del servicio necesita permiso sobre esa subnet.
- Equivalentes: `ec2:*` acotado en AWS IAM, políticas `manage virtual-network-family` en OCI, `roles/compute.networkAdmin` en GCP.
- Las **políticas de red** (que obligan a no tener IP pública) se imponen con Azure Policy / SCP / Security Zones / Organization Policy (módulo 10).

---

## 13. Labs sugeridos (con limpieza)

1. **Lab 1:** crear VNet con tres subnets y un NSG para la subnet de datos. Verificar con "Effective security rules".
2. **Lab 2:** crear dos VNets, peerearlas y probar conectividad entre dos VMs pequeñas. Luego romper el peering a propósito y ver el síntoma.
3. **Lab 3:** crear un Private Endpoint a una cuenta de Storage y comprobar el `nslookup` antes y después de enlazar la zona DNS (se detalla en el módulo 02).

Limpieza: `az group delete -n <rg> --yes --no-wait`.

---

## 14. Repaso y entrevista

**Repaso**
1. ¿Cuántas IP útiles tiene una subnet `/24` en Azure, AWS, OCI y GCP?
2. ¿Por qué hace falta una regla Deny aunque exista una regla Allow?
3. ¿Qué significa que el peering no sea transitivo?
4. ¿En qué se diferencia un Private Endpoint de un Service Endpoint?
5. ¿Qué es lo primero que revisas si un nombre no resuelve a una IP privada?

**Entrevista**
- Diseña la red de una aplicación con web, API y base de datos con acceso solo privado.
- ¿Cómo conectarías cinco VNets con un único punto de salida controlado?
- Explica la diferencia entre Security Group y Network ACL en AWS.
