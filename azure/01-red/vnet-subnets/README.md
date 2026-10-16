# Azure · Red · VNet y Subnets

## 1. Qué es

**Una VNet (Virtual Network) es el edificio privado de tu empresa dentro de Azure.** Las **subnets** son los pisos. Dentro del edificio las oficinas se comunican entre sí; hacia la calle (internet) solo se sale por las puertas que tú abres.

| Pieza | Analogía |
|---|---|
| VNet | El edificio |
| Address space (espacio de direcciones) | El terreno que ocupa el edificio, en rangos de IP privadas |
| Subnet | Un piso |
| NIC (tarjeta de red) | La puerta de cada oficina |
| IP privada | El número de la oficina |

---

## 2. Cómo funciona por dentro

```
VNet vnet-modalima-prod-eus2  (10.10.0.0/16)       ← regional: vive en UNA región
 ├── snet-web   10.10.0.0/24                         ← regional: cruza las zonas de la región
 ├── snet-app   10.10.1.0/24
 ├── snet-data  10.10.2.0/24
 ├── snet-pe    10.10.9.0/27                         ← solo Private Endpoints
 └── GatewaySubnet 10.10.255.0/27                    ← nombre obligatorio para VPN/ExpressRoute
```

**Qué hace Azure por ti dentro de una VNet**
- **Enrutamiento automático:** todas las subnets de una VNet se ven entre sí sin configurar rutas (rutas del sistema).
- **Asignación de IP privada** (DHCP de Azure): las IP las entrega la plataforma, no instalas un DHCP.
- **DNS:** por defecto usa el DNS que entrega Azure (`168.63.129.16` es la IP virtual de la plataforma que resuelve nombres). Puedes configurar tus propios servidores DNS en la VNet.
- **Aislamiento:** una VNet no se ve con otra a menos que la conectes (peering, VPN, etc.).

### Alcance
- La VNet es **regional**: vive en una región. Sus subnets abarcan todas las zonas de disponibilidad de esa región.
- Una VNet pertenece a **una suscripción y un Resource Group**.

### IP reservadas por subnet
Azure reserva **5 direcciones** de cada subnet (la de red, la de broadcast y 3 para uso interno de la plataforma). Una `/24` tiene `256 − 5 = 251` direcciones útiles. Una `/28` solo `16 − 5 = 11`.

### Tamaños de CIDR de referencia

| CIDR | IP totales | IP útiles en Azure | Uso típico |
|---|---|---|---|
| /16 | 65.536 | 65.531 | Toda la VNet |
| /20 | 4.096 | 4.091 | Subnet grande (nodos AKS con modelo clásico) |
| /22 | 1.024 | 1.019 | Subnet mediana |
| /24 | 256 | 251 | Subnet normal |
| /26 | 64 | 59 | Firewall, Bastion |
| /27 | 32 | 27 | Gateway de VPN, subnet de Private Endpoints pequeña |
| /28 | 16 | 11 | Subnets muy pequeñas |

**Rangos privados (RFC 1918):** `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`. Azure también reserva algunos rangos que no puedes usar en una VNet (por ejemplo `168.63.129.16`). Verifica la lista actual.

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- Aislar entornos (dev, qa, prod).
- Controlar quién habla con quién (con NSG).
- Dar acceso privado a PaaS (Private Endpoint).
- Conectar con on-premises (VPN/ExpressRoute).
- Cumplir normativa que prohíbe IP públicas.

**Cuándo NO necesitas diseñarla a fondo:** pruebas rápidas con servicios PaaS públicos y sin datos sensibles. En producción, siempre debe haber diseño de red.

**Alternativa en Azure:** para cargas sin red propia puedes usar PaaS con acceso público + firewall del servicio, pero pierdes aislamiento.

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Address space** | Rangos CIDR que la VNet "posee" | `10.10.0.0/16` |
| **Subnet** | Porción del espacio asignada a un grupo de recursos | `10.10.1.0/24` |
| **Delegación de subnet** | La subnet queda reservada para un servicio que la administra | `Microsoft.Web/serverFarms` para App Service |
| **Subnet con nombre obligatorio** | Servicios que exigen un nombre exacto | `GatewaySubnet`, `AzureFirewallSubnet`, `AzureBastionSubnet` |
| **IP privada dinámica / estática** | Asignada por Azure / fijada por ti | Dinámica por defecto |
| **Service Endpoint** | Ruta optimizada a un PaaS por la red troncal de Azure | `Microsoft.Storage` |
| **Default outbound access** | Salida a internet implícita para VMs sin NAT ni IP pública | En retirada: define salida explícita |
| **DNS personalizado** | Servidores DNS propios en la VNet | Para resolver nombres on-premises |
| **VNet flow logs** | Registro de tráfico de la VNet | Auditoría y diagnóstico |

### Subnets que exigen nombre o dedicación

| Servicio | Nombre / requisito | Tamaño mínimo recomendado |
|---|---|---|
| Azure Firewall | `AzureFirewallSubnet` | /26 |
| Firewall Management (modo forzado) | `AzureFirewallManagementSubnet` | /26 |
| VPN / ExpressRoute Gateway | `GatewaySubnet` | /27 |
| Azure Bastion | `AzureBastionSubnet` | /26 |
| Application Gateway | Subnet **dedicada** (nombre libre) | /24 recomendado para v2 |
| API Management (modos VNet) | Subnet dedicada (nombre libre) | Según SKU; verifica |
| App Service (integración VNet) | Subnet **delegada** a `Microsoft.Web/serverFarms` | /26 o mayor recomendado (verifica) |
| Container Apps | Subnet delegada o dedicada según el tipo de entorno | Verifica requisitos vigentes |
| PostgreSQL Flexible (acceso privado) | Subnet delegada a `Microsoft.DBforPostgreSQL/flexibleServers` | /28 o mayor |
| AKS | Subnet propia; con CNI clásico, IP por pod | Según el modelo de red |

> Los tamaños mínimos cambian con las versiones de cada servicio. Verifícalos en la doc oficial antes de dimensionar.

---

## 5. Cómo se usa

### 5.1 Portal
1. Crear **Resource Group**.
2. **Virtual networks → Create**: región, nombre y espacio de direcciones (`10.10.0.0/16`).
3. En **IP addresses**, agregar subnets: `snet-web`, `snet-app`, `snet-data`, `snet-pe`.
4. (Opcional) Habilitar **flow logs**.
5. Verificar en **Subnets** y en la pestaña de **Connected devices**.

### 5.2 CLI
Ver [`ejemplos/cli/vnet.sh`](ejemplos/cli/vnet.sh).

### 5.3 Terraform
Ver [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).

### 5.4 Cómo comprobar que quedó bien

```bash
az network vnet show -g rg-estudio-red -n vnet-estudio \
  --query "{espacio:addressSpace.addressPrefixes, subnets:subnets[].{n:name,cidr:addressPrefix}}" -o json

# ¿Está libre esa IP dentro de la VNet?
az network vnet check-ip-address -g rg-estudio-red -n vnet-estudio --ip-address 10.10.1.4
```

---

## 6. Seguridad

### IAM (plano de control)
| Necesidad | Rol de Azure RBAC | Alcance |
|---|---|---|
| Crear y editar redes | **Network Contributor** | Resource Group de red |
| Solo ver redes | **Reader** | Resource Group |
| Permitir que un servicio se una a una subnet | Permiso `Microsoft.Network/virtualNetworks/subnets/join/action` (incluido en Network Contributor) | La subnet |

Ejemplo de asignación mínima:

```bash
az role assignment create --assignee <ID-DEL-GRUPO-O-PRINCIPAL> \
  --role "Network Contributor" \
  --scope /subscriptions/<SUB>/resourceGroups/rg-estudio-red
```

### Políticas de red recomendadas
- No permitir IP públicas en NICs de VM de aplicación (Azure Policy: *Network interfaces should not have public IPs*).
- Exigir NSG en todas las subnets (excepto las que no lo admiten, como `GatewaySubnet`).
- Prohibir address spaces fuera de los rangos aprobados.

---

## 7. Qué hacer

- Planificar rangos IP **antes** de crear nada y documentarlos en una hoja compartida.
- Subnets **separadas por función**: web, app, datos, endpoints privados.
- Reservar una subnet **solo para Private Endpoints**.
- Dejar espacio de crecimiento (no usar todo el `/16` el primer día).
- Elegir rangos que **no se solapen** con otras VNets ni con on-premises.
- Definir **salida a internet explícita** (NAT Gateway) en vez de depender de la implícita.
- Activar **VNet flow logs** en subnets críticas.

## 8. Qué NO hacer

- Usar rangos solapados (no podrás hacer peering ni VPN después).
- Subnets demasiado pequeñas para AKS, APIM o Application Gateway.
- Poner IP públicas "temporales" y olvidarlas.
- Mezclar servicios con requisitos distintos en una misma subnet (por ejemplo, delegada y no delegada).
- Cambiar el address space sin revisar peerings y recursos dependientes.

---

## 9. Límites, costos y versiones

- La VNet en sí **no tiene costo**; se cobran los servicios que pones dentro (NAT Gateway, Private Endpoint, Firewall, Bastion, VPN).
- El tráfico **entre regiones** y el de **salida a internet** se cobra; el de dentro de la misma VNet/zona suele no cobrarse (verifica).
- Hay cuotas por suscripción (número de VNets, subnets, IP públicas): consulta `az network list-usages -l eastus2 -o table`.
- **Acceso de salida predeterminado:** Azure está retirando la salida implícita para subnets nuevas; verifica el estado vigente y define NAT Gateway.
