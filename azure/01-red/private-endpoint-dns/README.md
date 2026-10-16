# Azure · Red · Private Endpoint y DNS privado

## 1. Qué es

**Un Private Endpoint es una puerta interna en tu edificio que da directo al servicio de otra empresa**, sin salir a la calle. Un servicio como Storage, SQL o Key Vault vive en direcciones públicas de Microsoft; con un Private Endpoint, ese servicio recibe **una IP privada dentro de tu subnet**.

**El DNS privado es la guía telefónica interna:** hace que el nombre `mistorage.blob.core.windows.net` apunte a esa IP privada **solo para quienes están dentro de tu red**.

> Sin DNS correcto, el Private Endpoint no sirve: la aplicación seguirá yendo a la IP pública. **Esta es la causa número uno de errores de red privada en Azure.**

---

## 2. Cómo funciona por dentro

```
Tu app (snet-app)
   │ 1. pregunta: ¿cuál es la IP de mistorage.blob.core.windows.net?
   ▼
DNS de la VNet (168.63.129.16 o tu servidor DNS)
   │ 2. el nombre es un CNAME hacia mistorage.privatelink.blob.core.windows.net
   │ 3. existe la zona privada "privatelink.blob.core.windows.net" enlazada a la VNet
   │    con un registro A:  mistorage → 10.10.9.4
   ▼
Tu app se conecta a 10.10.9.4:443  ──►  [Private Endpoint (NIC en snet-pe)] ──► Storage
```

### Piezas
| Pieza | Qué es |
|---|---|
| **Private Endpoint (PE)** | Recurso que crea una **NIC** con IP privada en tu subnet y la une al servicio destino |
| **Private Link** | La tecnología/red troncal de Microsoft que transporta el tráfico del PE al servicio |
| **Connection** | La relación PE ↔ recurso destino. Tiene estado: `Approved`, `Pending`, `Rejected`, `Disconnected` |
| **Group ID / sub-recurso** | Qué parte del servicio expones: `blob`, `file`, `queue`, `table`, `dfs`, `sqlServer`, `vault`, `namespace`, `sites`, `registry`... |
| **Private DNS Zone** | Zona `privatelink.*` con los registros A que apuntan a la IP del PE |
| **Virtual Network Link** | Enlace que hace que **una VNet** use esa zona. Sin enlace, la VNet no ve los registros |
| **DNS Zone Group** | Ata el PE a la zona y crea/actualiza el registro A automáticamente |

### Un PE por sub-recurso
Una Storage Account tiene varios endpoints (`blob`, `file`, `queue`, `table`, `dfs`). Si usas Blob y Queue, necesitas **dos PE** y **dos zonas** (`privatelink.blob...` y `privatelink.queue...`).

### Aprobación
- Si eres dueño del recurso destino, la conexión se **aprueba sola**.
- Si el destino es de **otra suscripción/tenant**, queda `Pending` hasta que su dueño la apruebe.

### Servicios y zonas DNS comunes
| Servicio | Group ID | Zona privada |
|---|---|---|
| Storage Blob | `blob` | `privatelink.blob.core.windows.net` |
| Storage Data Lake | `dfs` | `privatelink.dfs.core.windows.net` |
| Storage Queue | `queue` | `privatelink.queue.core.windows.net` |
| Azure SQL | `sqlServer` | `privatelink.database.windows.net` |
| PostgreSQL Flexible (modo PE) | `postgresqlServer` | `privatelink.postgres.database.azure.com` |
| Cosmos DB (SQL API) | `Sql` | `privatelink.documents.azure.com` |
| Key Vault | `vault` | `privatelink.vaultcore.azure.net` |
| Service Bus / Event Hubs | `namespace` | `privatelink.servicebus.windows.net` |
| Container Registry | `registry` | `privatelink.azurecr.io` |
| App Service / Functions | `sites` | `privatelink.azurewebsites.net` |
| API Management | `Gateway` | `privatelink.azure-api.net` |
| AKS API server (clúster privado) | — | `privatelink.<región>.azmk8s.io` |

> Verifica los nombres exactos y los group ID vigentes en la documentación de "Private endpoint DNS zone values".

---

## 3. Service Endpoint vs Private Endpoint

| | Service Endpoint | Private Endpoint |
|---|---|---|
| ¿IP privada para el servicio? | No (sigue siendo pública) | **Sí**, en tu subnet |
| Tráfico | Por la red troncal de Azure, desde tu subnet | Por la red troncal, a una IP privada |
| Se alcanza desde on-premises | No | **Sí** (por VPN/ExpressRoute) |
| Control de acceso | El servicio permite tu subnet | El servicio puede cerrar **todo** acceso público |
| Costo | Gratis | Por hora y por GB |
| Recomendado | Casos simples | **Producción** |

---

## 4. Arquitecturas de DNS

| Escenario | Qué hacer |
|---|---|
| **Una sola VNet** | Zona privada enlazada a esa VNet |
| **Hub-and-spoke** | Zonas privadas **centralizadas en el hub** y enlazadas a hub y spokes (o un Private DNS Resolver en el hub) |
| **DNS propio en la VNet** (servidores personalizados) | Esos servidores deben **reenviar** las zonas `privatelink` a `168.63.129.16` (solo funciona desde dentro de la VNet) o a un **Azure DNS Private Resolver** |
| **On-premises necesita resolver nombres de PE** | Reenviadores condicionales on-premises → *inbound endpoint* de DNS Private Resolver |
| **Varias regiones** | La misma zona privada sirve a VNets de varias regiones; un registro A por PE |

### Resolver (DNS Private Resolver)
Servicio administrado con dos endpoints: **inbound** (para que otros te consulten) y **outbound** (para reenviar hacia afuera). Evita mantener servidores DNS propios.

---

## 5. Para qué sirve y cuándo NO usarlo

**Sirve para**
- Cerrar el acceso público de bases de datos, storage y secretos.
- Que el tráfico no salga a internet.
- Cumplir normativa y reducir superficie de ataque.

**Cuándo NO**
- Pruebas descartables sin datos sensibles.
- Servicios que no soportan Private Link (revisa la lista actual).
- Cuando un **Service Endpoint** o la integración de VNet del servicio basta y evitas el costo.

---

## 6. Cómo se usa

- CLI: [`ejemplos/cli/private-endpoint.sh`](ejemplos/cli/private-endpoint.sh)
- Terraform: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf)

**Verificación (desde una VM o pod dentro de la VNet):**
```bash
nslookup mistorage.blob.core.windows.net
# Esperado:
#   mistorage.blob.core.windows.net  canonical name = mistorage.privatelink.blob.core.windows.net
#   Address: 10.10.9.4
```
- Responde **IP pública** → falta el enlace de la zona a la VNet, o el DNS no reenvía.
- **No resuelve** → problema de DNS de la VNet.
- Resuelve a IP privada pero hay **timeout** → NSG/ruta; o el PE no está `Approved`.

**Estado de la conexión**
```bash
az network private-endpoint show -g <rg> -n <pe> --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState"
```

---

## 7. Seguridad

### IAM
| Necesidad | Rol / permiso |
|---|---|
| Crear el PE en tu subnet | Network Contributor (permiso `.../subnets/join/action` y `privateEndpoints/write`) |
| Vincularlo al recurso destino | Permiso `Microsoft.<Servicio>/.../privateEndpointConnectionsApproval/action` sobre el recurso (Contributor lo incluye) |
| Gestionar zonas DNS privadas | **Private DNS Zone Contributor** |
| Aprobar conexiones de terceros | Dueño del recurso destino |

### Políticas recomendadas
- *Storage accounts should disable public network access*.
- *Azure Key Vaults should use private link*.
- DeployIfNotExists para crear automáticamente los DNS zone groups.

### Data exfiltration
Con el acceso público cerrado, un PE a **tu** recurso evita que alguien use otro storage externo desde tu red; combínalo con firewall de salida y Private Link solo hacia recursos aprobados.

---

## 8. Qué hacer

- Crear siempre el **DNS zone group** y verificar el `nslookup`.
- Una **subnet exclusiva** para PE (`snet-pe`).
- Centralizar las zonas en el hub y enlazarlas a todas las VNets que las usan.
- Poner `public network access = Disabled` **después** de verificar que el privado funciona.
- Un PE por servicio y por sub-recurso que uses.
- Documentar qué PE existe para qué recurso.

## 9. Qué NO hacer

- Crear PE y **olvidar el enlace DNS**.
- Cerrar el acceso público antes de probar el privado.
- Poner IP fija de PE en el código o en `hosts`: usa el nombre.
- Duplicar la misma zona privada en varias suscripciones sin control (resolverá distinto según la VNet).
- Conectar a la IP privada directamente: el certificado TLS está emitido para el **nombre**, no para la IP.

---

## 10. Límites, costos y versiones

- Costo: por PE-hora y por GB procesado; muchos PE olvidados inflan la factura.
- Cada PE consume **una IP** de la subnet (algunos servicios consumen más).
- Por defecto las **políticas de red** (NSG/UDR) no se aplican al PE; hay una opción de la subnet para habilitarlo. Verifica el comportamiento vigente.
- Los nombres de zona y los group ID cambian con nuevos servicios: consulta la doc.
