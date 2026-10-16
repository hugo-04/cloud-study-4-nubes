# Azure · Red · NSG, Rutas (UDR) y NAT Gateway

## 1. Qué es

Tres piezas que deciden **qué tráfico pasa, por dónde va y cómo sale a internet**.

| Pieza | Analogía | Qué decide |
|---|---|---|
| **NSG** (Network Security Group) | El guardia del piso con una lista de reglas | ¿Se permite o se niega este paquete? |
| **Route Table / UDR** (User-Defined Route) | Las señales "por aquí se sale" | ¿Por qué camino va el paquete? |
| **NAT Gateway** | La puerta de salida con un mismo número de teléfono | ¿Con qué IP pública salen mis recursos a internet? |

---

## 2. Cómo funciona por dentro

### 2.1 NSG: reglas, prioridades y estado

Un NSG es una lista de **reglas de seguridad**. Cada regla tiene:

| Campo | Qué es | Ejemplo |
|---|---|---|
| Prioridad | Número entre 100 y 4096. **Menor número = se evalúa primero** | 100 |
| Dirección | Entrante (Inbound) o saliente (Outbound) | Inbound |
| Origen | IP/CIDR, etiqueta de servicio o ASG | `10.10.1.0/24` |
| Destino | Igual que origen | `*` |
| Protocolo | TCP, UDP, ICMP, `*` | TCP |
| Puerto destino | Un puerto, rango o `*` | 1433 |
| Acción | Allow o Deny | Allow |

- **Con estado (stateful):** si permites una conexión de entrada, la respuesta sale sin otra regla.
- **La primera regla que coincide gana** y deja de evaluarse.

**Reglas por defecto (no se pueden borrar, solo superar con prioridad menor):**

| Prioridad | Nombre | Dirección | Acción |
|---|---|---|---|
| 65000 | AllowVnetInBound | Entrante | Allow desde `VirtualNetwork` |
| 65001 | AllowAzureLoadBalancerInBound | Entrante | Allow desde `AzureLoadBalancer` |
| 65500 | DenyAllInBound | Entrante | Deny todo |
| 65000 | AllowVnetOutBound | Saliente | Allow hacia `VirtualNetwork` |
| 65001 | AllowInternetOutBound | Saliente | Allow hacia `Internet` |
| 65500 | DenyAllOutBound | Saliente | Deny todo |

> **Consecuencia clave:** dentro de una VNet todo se habla por defecto (`AllowVnetInBound`). Para que la subnet de datos reciba **solo** de la subnet de aplicación, necesitas una regla Allow (100) **y** una regla Deny `VirtualNetwork` (por ejemplo 4000).

### 2.2 Dónde se asocia el NSG y en qué orden se evalúa

Un NSG puede asociarse a una **subnet** y/o a una **NIC**. Cuando hay ambos:

```
Tráfico ENTRANTE:   NSG de la subnet  →  NSG de la NIC  →  VM
Tráfico SALIENTE:   VM  →  NSG de la NIC  →  NSG de la subnet
```
Ambos deben permitir el paso. Recomendación: **NSG por subnet** (más simple); NSG por NIC solo para excepciones.

### 2.3 Etiquetas de servicio y ASG

| Elemento | Qué es | Ejemplo |
|---|---|---|
| **Service tag** | Grupo de IP de un servicio de Azure, mantenido por Microsoft | `Storage`, `Sql`, `AzureKeyVault`, `AzureActiveDirectory`, `ApiManagement`, `AzureLoadBalancer`, `Internet`, `VirtualNetwork` |
| **ASG** (Application Security Group) | Grupo lógico de NIC que defines tú | `asg-web`, `asg-app` |

Con ASG escribes reglas como "los de `asg-web` pueden hablar con los de `asg-app` por 8080" sin depender de IP.

### 2.4 Rutas: sistema y UDR

Azure crea **rutas del sistema** automáticamente:

| Destino | Siguiente salto | Para qué |
|---|---|---|
| Rango de la VNet | Virtual network | Tráfico interno |
| `0.0.0.0/0` | Internet | Salida (según el caso) |
| Rangos privados no usados | None | Se descartan |

Con una **Route Table** (UDR) puedes **sobrescribirlas**:

| Tipo de siguiente salto | Cuándo |
|---|---|
| `VirtualAppliance` | Forzar el tráfico por un firewall o NVA (IP privada del firewall) |
| `VirtualNetworkGateway` | Enviar a on-premises por VPN/ExpressRoute |
| `VnetLocal` | Mantener local |
| `Internet` | Salida directa |
| `None` | Descartar el tráfico (bloquear) |

**Regla de selección:** gana la ruta con el **prefijo más largo** (más específico). A igual prefijo: UDR > BGP > ruta del sistema.

Patrón típico: ruta `0.0.0.0/0 → VirtualAppliance 10.10.250.4` para que **toda la salida** pase por Azure Firewall.

> **Ruteo asimétrico:** si la ida pasa por el firewall y la vuelta no, el firewall descarta la respuesta y verás timeouts. Asegura que ambos sentidos pasen por el mismo dispositivo.

### 2.5 NAT Gateway: salida controlada

- Se asocia a **una o más subnets**.
- Todos los recursos de esas subnets salen a internet con **las IP públicas del NAT Gateway** (una o varias, o un prefijo).
- Resuelve el **agotamiento de puertos SNAT**: cada IP pública aporta un bloque grande de puertos (del orden de decenas de miles; verifica el número vigente).
- Tiene un **idle timeout** configurable (por defecto unos 4 minutos; verifica).
- Es **por zona o regional** según el SKU; revisa el comportamiento de zonas en la doc.

| Opción de salida | Cuándo |
|---|---|
| NAT Gateway | Salida simple, IP fija, muchas conexiones |
| Azure Firewall (UDR) | Además necesitas **filtrar** destinos (FQDN) |
| Load Balancer outbound | Heredado; con riesgo de agotar SNAT |
| IP pública en la VM | Evitar; expone la máquina |

---

## 3. Para qué sirve y cuándo NO usarlo

| Pieza | Sirve para | Cuándo NO |
|---|---|---|
| NSG | Filtrar L3/L4 (IP, puerto, protocolo) por subnet o NIC | No filtra por URL/FQDN ni inspecciona contenido: usa Azure Firewall o WAF |
| UDR | Forzar salida por firewall, enviar a on-premises, bloquear | No lo uses si no tienes un dispositivo que reciba y devuelva el tráfico |
| NAT Gateway | IP de salida fija y muchas conexiones | No filtra destinos |

---

## 4. Conceptos clave

| Término | Definición simple |
|---|---|
| Stateful | El firewall recuerda las conexiones abiertas |
| Next hop | El "siguiente salto" que se da a un paquete |
| Prefijo más largo | La ruta más específica gana |
| Effective rules / routes | Lo que **de verdad** se aplica a una NIC, sumando todo |
| SNAT | Traducir la IP privada de salida a una IP pública |
| Flow log | Registro de conexiones aceptadas y negadas |

---

## 5. Cómo se usa

- CLI: [`ejemplos/cli/nsg-udr-nat.sh`](ejemplos/cli/nsg-udr-nat.sh)
- Terraform: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf)

**Comprobar lo que de verdad aplica a una máquina**
```bash
az network nic list-effective-nsg -g rg-estudio-red --name nic-vm-test
az network nic show-effective-route-table -g rg-estudio-red -n nic-vm-test -o table
```
En el portal: la NIC → **Help → Effective security rules / Effective routes**.

**Probar si un flujo está permitido (Network Watcher)**
```bash
az network watcher test-ip-flow -g rg-estudio-red --vm vm-test \
  --direction Outbound --protocol TCP \
  --local 10.10.1.4:50000 --remote 10.10.2.4:1433
```

---

## 6. Seguridad

### IAM
| Necesidad | Rol | Alcance |
|---|---|---|
| Crear y editar NSG, rutas y NAT | Network Contributor | Resource Group de red |
| Solo auditar | Reader | Resource Group |
| Usar Network Watcher | Network Watcher Contributor (o Reader para ver) | Suscripción / grupo de Network Watcher |

### Políticas recomendadas (Azure Policy)
- Subnets deben tener NSG asociado.
- Denegar reglas que abran `0.0.0.0/0` a puertos 22, 3389 o de bases de datos.
- Denegar NIC con IP pública.

---

## 7. Qué hacer

- Un **NSG por subnet** y nombres claros (`nsg-data`).
- Reglas **mínimas** y con **prioridades espaciadas** (100, 110, 120…) para poder insertar.
- Regla **Deny `VirtualNetwork`** de prioridad ~4000 en subnets sensibles.
- Usar **service tags** y **ASG** en vez de listas de IP.
- Activar **VNet flow logs** con retención definida.
- Probar con **Effective rules** y **IP flow verify** antes de culpar a la aplicación.
- NAT Gateway para salida con IP fija.

## 8. Qué NO hacer

- Abrir `*` desde `Internet` a puertos de administración o de bases de datos.
- Confiar en que "como es la misma VNet, está protegido".
- Crear reglas con prioridades iguales o pegadas sin espacio.
- Poner `0.0.0.0/0 → VirtualAppliance` sin comprobar el retorno.
- Olvidar que un NSG en la NIC **y** otro en la subnet se suman.
- Depender de la salida implícita.

---

## 9. Límites, costos y versiones

- Hay un máximo de reglas por NSG y de NSG por suscripción: consulta los límites vigentes.
- NSG y UDR **no tienen costo**; NAT Gateway se cobra por hora y por GB procesado.
- **Los NSG flow logs están en retiro y los reemplazan los VNet flow logs:** verifica las fechas vigentes.
