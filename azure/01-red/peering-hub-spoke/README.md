# Azure · Red · VNet Peering y Hub-and-Spoke

## 1. Qué es

**El peering es un puente privado entre dos edificios (VNets).** Los de un edificio llegan a los del otro por IP privada, por la red troncal de Microsoft, sin salir a internet. **Hub-and-spoke** es el diseño en el que un edificio central (hub) conecta con muchos edificios satélite (spokes) y concentra lo compartido: firewall, VPN, DNS.

```
                 On-premises
                     │ VPN / ExpressRoute
              ┌──────┴───────┐
              │  HUB VNet    │  Firewall · Gateway · DNS Resolver · Bastion
              └──┬────────┬──┘
        peering  │        │  peering
        ┌────────┴──┐  ┌──┴────────┐
        │ SPOKE dev │  │ SPOKE prod│        (dev y prod NO se ven entre sí)
        └───────────┘  └───────────┘
```

---

## 2. Cómo funciona por dentro

### 2.1 Reglas del peering
- Se crea **en ambos sentidos**: un recurso de peering en cada VNet. Si falta uno, el estado queda `Initiated` y no hay conectividad.
- Estados: `Initiated` (falta el otro lado), `Connected` (OK), `Disconnected` (se eliminó un lado).
- **No es transitivo:** si A↔B y B↔C, **A no llega a C**. Hay que usar un hub con firewall o crear A↔C.
- Los espacios de direcciones **no pueden solaparse**.
- El tráfico no cruza internet público; usa la red troncal de Microsoft.
- Funciona entre regiones (*global peering*), suscripciones y tenants (con permisos).

### 2.2 Opciones de cada sentido del peering

| Opción | Qué hace | Cuándo |
|---|---|---|
| `allow_virtual_network_access` | Permite el tráfico entre ambas VNets | Siempre `true` para conectar |
| `allow_forwarded_traffic` | Acepta tráfico que **no se originó** en la VNet vecina (por ejemplo reenviado por un firewall) | En spokes cuando el hub tiene firewall; en el hub para recibir tráfico reenviado |
| `allow_gateway_transit` | El **hub** comparte su VPN/ExpressRoute Gateway | Lado del hub |
| `use_remote_gateways` | El **spoke** usa el gateway del hub | Lado del spoke (no puede tener su propio gateway) |

### 2.3 Spoke a spoke a través del hub
Para que `dev` hable con `shared` pasando por el firewall del hub:
1. Peering spoke↔hub con `allow_forwarded_traffic = true`.
2. En cada spoke, una **Route Table** con `0.0.0.0/0` (o los rangos de otros spokes) → **VirtualAppliance** (IP del firewall).
3. El firewall tiene reglas que permiten ese tráfico.

### 2.4 Alternativas de conexión

| Opción | Cuándo |
|---|---|
| Peering directo | Pocas VNets, simple, baja latencia |
| Hub-and-spoke con firewall | Control central, muchas VNets |
| **Azure Virtual WAN** | Muchas sucursales/VNets, enrutamiento administrado |
| VPN Gateway VNet-to-VNet | Cuando no se puede hacer peering |
| Private Link | Exponer **un servicio**, no toda la red |

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**: conectar entornos, compartir servicios (logs, DNS, firewall), conectar con on-premises usando un solo gateway, segmentar prod y no-prod con un punto de control.

**Cuándo NO**
- Si solo quieres exponer **un servicio** a otra red: usa **Private Link**, no conectes redes enteras.
- Si los rangos IP se solapan: primero rediseña los rangos.
- Si tienes cientos de VNets y sucursales: valora **Virtual WAN**.

---

## 4. Conceptos clave

| Término | Definición simple |
|---|---|
| Peering | Conexión privada entre dos VNets |
| Hub | VNet central con servicios compartidos |
| Spoke | VNet de carga de trabajo conectada al hub |
| Gateway transit | El spoke usa el VPN/ExpressRoute del hub |
| NVA | Dispositivo virtual de red (firewall de terceros) |
| Forwarded traffic | Tráfico reenviado por un dispositivo intermedio |
| Global peering | Peering entre regiones distintas |

---

## 5. Cómo se usa

- CLI: [`ejemplos/cli/peering.sh`](ejemplos/cli/peering.sh)
- Terraform: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf)

**Comprobar**
```bash
az network vnet peering list -g rg-estudio-hub --vnet-name vnet-hub \
  --query "[].{n:name,estado:peeringState,sync:peeringSyncLevel}" -o table
```
`peeringState` debe ser `Connected` en **los dos** lados.

---

## 6. Seguridad

### IAM
| Necesidad | Rol |
|---|---|
| Crear peering dentro de la misma suscripción | Network Contributor en ambas VNets (acción `Microsoft.Network/virtualNetworks/virtualNetworkPeerings/write` y `.../peer/action` en la VNet remota) |
| Peering entre suscripciones o tenants | El principal necesita permiso en **ambos** lados (en tenants distintos, cuentas invitadas o aprobación del otro lado) |

### Políticas recomendadas
- Solo VNets aprobadas pueden hacer peering con el hub (Azure Policy o revisión por IaC).
- Prohibir IP públicas en spokes de datos.
- Registro de flujos habilitado en las VNets del hub y spokes.

### Firewall central
Con un firewall en el hub, la regla por defecto es **negar** spoke↔spoke y permitir solo lo necesario, por FQDN y puerto.

---

## 7. Qué hacer

- Planificar rangos IP **sin solapes** desde el inicio (incluye on-premises).
- Un hub por región; spokes por entorno o equipo.
- Crear el peering **por IaC en ambos sentidos** a la vez.
- Documentar qué spokes se pueden ver entre sí.
- Zonas DNS privadas **en el hub** y enlazadas a spokes.
- Monitorear el costo del tráfico entre regiones.

## 8. Qué NO hacer

- Esperar que el peering sea transitivo.
- Poner cargas de trabajo en el hub.
- Dejar peerings `Disconnected` sin limpiar.
- Dar permisos de peering a todos los desarrolladores.
- Cambiar el address space de una VNet sin resincronizar los peerings.

---

## 9. Límites, costos y versiones

- El tráfico por peering **se cobra** por GB (más si es entre regiones); dentro de la misma región es bajo.
- Hay un límite de peerings por VNet: consulta los límites vigentes.
- Tras agregar un address space a una VNet peereada, hay que **sincronizar** el peering (el portal tiene la opción *Sync*).
