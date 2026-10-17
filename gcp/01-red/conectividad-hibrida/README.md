# Google Cloud · Red · Conectividad entre redes e híbrida

Cómo unir redes: **VPC Network Peering** (dos VPC se ven por IP privada), **Shared VPC** (una red para muchos proyectos), **Cloud VPN** (túneles IPsec por Internet con BGP) y **Cloud Interconnect** (enlace dedicado o de socio al centro de datos). Todas dependen de lo mismo: **rangos que no se solapen** y rutas bien anunciadas.

## 1. Qué es

**Analogía:** conectar oficinas. Peering es abrir una puerta entre dos oficinas vecinas; Shared VPC es que todos trabajen en el mismo piso; VPN es un túnel seguro por la calle pública; Interconnect es una línea privada propia entre el edificio y la fábrica.

```
 VPC tienda ◄── peering ──► VPC analítica        (no transitivo: A↔B y B↔C no da A↔C)
 VPC host (Shared VPC) ── subredes usadas por proyectos de servicio
 VPC host ── Cloud Router (BGP) ── HA VPN (2 túneles) ── firewall/router de la oficina 192.168.0.0/16
                                └─ Interconnect (VLAN attachments) ── centro de datos
```

## 2. Cómo funciona por dentro

### Opciones
| Opción | Qué es | Detalle clave |
|---|---|---|
| **VPC Peering** | Intercambio de rutas de subred entre dos VPC | **No transitivo**; exportar/importar rutas personalizadas es opcional |
| **Shared VPC** | Red del proyecto host usada por proyectos de servicio | La alternativa preferida dentro de una organización |
| **HA VPN** | Gateway con 2 interfaces y 2+ túneles IPsec | SLA alto con dos túneles activos *(verifica)*; BGP con Cloud Router |
| **Classic VPN** | Un túnel, rutas estáticas | Legado; evita |
| **Dedicated Interconnect** | Enlace físico de 10/100 Gbps | En una colocación compartida con Google |
| **Partner Interconnect** | Enlace vía proveedor | Capacidades más pequeñas |
| **Network Connectivity Center** | Hub para conectar muchas redes/sitios | Topologías más grandes *(verifica)* |

### Rutas
- Cloud Router aprende y anuncia por **BGP**; el **modo de enrutamiento** de la VPC (`REGIONAL`/`GLOBAL`) decide si las rutas aprendidas se usan en todas las regiones.
- En peering, las rutas de subred se intercambian siempre; las personalizadas solo si exportas e importas.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Varios proyectos de la misma organización | **Shared VPC** |
| Dos organizaciones o equipos con redes separadas | **Peering** |
| Oficina o centro de datos con tráfico moderado | **HA VPN** |
| Tráfico alto y latencia estable al centro de datos | **Interconnect** |
| Conectar 10 VPC entre sí con peering | **No**: Shared VPC o NCC |
| Exponer un servicio a otra organización sin unir redes | **Private Service Connect** (ver [acceso privado](../acceso-privado/README.md)) |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **No transitivo** | El vecino de mi vecino no es mi vecino |
| **BGP** | Protocolo con el que los routers se cuentan qué redes tienen |
| **ASN** | Número que identifica a cada router BGP |
| **Túnel IPsec** | Conexión cifrada sobre Internet |
| **VLAN attachment** | La «conexión lógica» de un Interconnect |

## 5. Cómo se usa
1. Peering bidireccional y HA VPN con BGP: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Verifica estado de peerings, rutas y solapes desde [Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/conectividad.sh`](ejemplos/cli/conectividad.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Equipo de red | `roles/compute.networkAdmin` en ambos lados | — |
| Auditoría | `roles/compute.networkViewer` | Flow logs |

- El firewall sigue aplicando en cada VPC: un peering no abre puertos.
- Secretos compartidos de VPN en Secret Manager, no en el repo.
- Filtra en BGP lo que anuncias (no anuncies 0.0.0.0/0 por error).

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Plan de direcciones único para toda la empresa | Rangos repetidos |
| HA VPN con dos túneles | VPN clásica de un túnel |
| Modo de enrutamiento `GLOBAL` si hay varias regiones | Descubrir que una región no ve las rutas |
| Shared VPC dentro de la organización | Malla de peerings |
| Alertas de túnel caído y de sesión BGP | Enterarse por los usuarios |

## 8. Límites, costos y versiones
- **Costo:** peering sin cargo propio (tráfico sí); VPN por túnel-hora + tráfico; Interconnect por puerto/VLAN + tráfico *(verifica)*.
- **Límites** (verifica): peerings por VPC, rutas importadas, túneles por gateway.
- **Terraform:** `google_compute_network_peering`, `google_compute_ha_vpn_gateway`, `google_compute_external_vpn_gateway`, `google_compute_vpn_tunnel`, `google_compute_router_interface`, `google_compute_router_peer`.
- **Java:** `NetworksClient` (peerings), `VpnTunnelsClient`, `RoutersClient` (estado BGP).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
