# Google Cloud · Red · VPC y subredes

Una **VPC** en Google Cloud es una red privada **global**: una sola red atraviesa todas las regiones y las **subredes** son **regionales**. Las VMs, nodos de GKE, conectores y servicios administrados toman IPs de esas subredes y se hablan por la red interna de Google sin salir a Internet.

## 1. Qué es

**Analogía:** una empresa con sucursales en varias ciudades unidas por su propia autopista privada. La autopista (VPC) es una sola; cada ciudad (región) tiene sus calles numeradas (subredes). Un auto de Lima llega a São Paulo por la autopista privada, sin pasar por la vía pública.

```
 VPC "modalima-vpc" (global, modo personalizado, MTU 1460)
   ├─ southamerica-west1   subred "apps"   10.10.0.0/20   (+ secundarios pods 10.20.0.0/16, servicios 10.30.0.0/20)
   ├─ southamerica-west1   subred "datos"  10.10.16.0/22  Private Google Access ✓, flow logs ✓
   └─ southamerica-east1   subred "apps"   10.11.0.0/20
 Rutas del sistema: cada subred se ve con todas · ruta por defecto 0.0.0.0/0 → Internet (si hay IP externa o NAT)
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **VPC** | Recurso global; modo **automático** (una subred por región, rangos fijos) o **personalizado** (tú defines) |
| **Subred** | Rango primario IPv4 en una región; opcionalmente rangos **secundarios** (pods y servicios de GKE) e IPv6 |
| **Private Google Access** | Permite a VMs sin IP externa llegar a las APIs de Google |
| **Flow logs** | Muestreo de flujos por subred para diagnóstico y seguridad |
| **Rutas** | Del sistema (subredes, por defecto) y personalizadas/dinámicas (Cloud Router) |
| **Modo de enrutamiento dinámico** | `REGIONAL` o `GLOBAL` para rutas aprendidas por BGP |
| **Shared VPC** | Proyecto **host** con la red; proyectos de **servicio** crean recursos en sus subredes |
| **IPs reservadas** | Internas o externas estáticas para que no cambien |

### Lo que conviene saber
- Las subredes pueden **ampliarse** (cambiar a un prefijo más corto) sin recrearlas, pero no reducirse.
- Dentro de una VPC, todo se ve por ruta; lo que bloquea o permite es el **firewall** (ver [firewall, rutas y NAT](../firewall-rutas-nat/README.md)).
- Cuatro direcciones de cada rango primario están reservadas *(verifica)*.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Base de red de una empresa con varios proyectos | **Shared VPC** en un proyecto host |
| GKE con IPs de pods nativas de VPC | Subred con rangos secundarios |
| Equipo pequeño con un solo proyecto | VPC personalizada en ese proyecto |
| Modo automático en producción | **No**: rangos fijos que chocan al conectar redes |
| Una VPC por microservicio | **No**: complejidad sin beneficio |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **VPC global** | Una red para todas las regiones |
| **Subred regional** | Rango de IPs en una región |
| **Rango secundario** | IPs extra para pods/servicios de GKE |
| **Proyecto host / servicio** | Dueño de la red / quien la usa |
| **Private Google Access** | APIs de Google sin IP pública |

## 5. Cómo se usa
1. VPC personalizada, subredes con secundarios, PGA y flow logs: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Audita solapes, PGA y flow logs desde [Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/vpc.sh`](ejemplos/cli/vpc.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Equipo de red (host) | `roles/compute.networkAdmin` | — |
| Proyectos de servicio | `roles/compute.networkUser` **por subred** | Tráfico según firewall |
| Auditoría | `roles/compute.networkViewer` | Flow logs en Logging |

- Sin IPs externas en VMs (política de organización `compute.vmExternalIpAccess`).
- `networkUser` solo sobre las subredes que cada equipo necesita.
- Flow logs en subredes de producción (con muestreo para controlar costo).

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Modo personalizado y plan de direcciones | Modo automático |
| Rangos secundarios dimensionados para GKE | Quedarse sin IPs de pods |
| PGA en subredes privadas | Dar IP pública para llegar a las APIs |
| Shared VPC para centralizar | Redes duplicadas por proyecto |
| Borrar la red `default` | Dejarla con reglas abiertas |

## 8. Límites, costos y versiones
- **Costo:** la VPC no cuesta; el tráfico entre zonas/regiones y la salida a Internet sí; flow logs se cobran en Logging *(verifica)*.
- **Límites** (verifica): subredes por VPC, rangos secundarios por subred, VPC por proyecto.
- **Terraform:** `google_compute_network`, `google_compute_subnetwork`, `google_compute_shared_vpc_host_project`.
- **Java:** `NetworksClient`, `SubnetworksClient` (`google-cloud-compute`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
