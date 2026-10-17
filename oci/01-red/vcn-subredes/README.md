# Oracle OCI · Red · VCN y subredes

La **VCN** (*Virtual Cloud Network*) es tu red privada dentro de una región de OCI. Dentro de ella creas **subredes**, y conectas esa red con Internet, con servicios de Oracle o con otras redes mediante **gateways** y **tablas de rutas**. Casi todo lo que despliegas (VM, nodos de OKE, bases de datos, balanceadores) vive en una subred.

## 1. Qué es

**Analogía:** un **barrio cerrado** que alquilas dentro de la ciudad. El barrio tiene un rango de direcciones (el CIDR), calles internas (subredes), una puerta principal con portero (Internet Gateway), una salida de servicio de un solo sentido (NAT Gateway) y un pasillo directo a los servicios municipales de Oracle (Service Gateway).

```
                 Internet
                    │
           ┌────────┴────────┐
           │ Internet Gateway │
           └────────┬────────┘
 VCN 10.30.0.0/16   │
 ┌──────────────────┼───────────────────────────────────────┐
 │  Subred pública  10.30.0.0/24  (balanceador)             │
 │  Subred privada  10.30.10.0/24 (app / nodos OKE) ──► NAT Gateway ──► Internet (solo salida)
 │  Subred privada  10.30.20.0/24 (base de datos)   ──► Service Gateway ──► Object Storage, etc.
 └──────────────────────────────────────────────────────────┘
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es | Detalles clave |
|---|---|---|
| **VCN** | Red virtual regional con uno o más bloques CIDR IPv4 (y opcional IPv6) | Rango típico `/16`; se pueden **añadir** bloques después; no los cambies si ya hay peering |
| **Subred** | Porción del CIDR de la VCN | **Regional** (recomendada: abarca todos los AD) o por AD; **pública** o **privada** |
| **Internet Gateway (IGW)** | Entrada y salida a Internet para subredes públicas | Necesita ruta y IP pública en el recurso |
| **NAT Gateway** | Salida a Internet sin exponer entrada | Para subredes privadas |
| **Service Gateway (SGW)** | Ruta privada hacia servicios de Oracle (Object Storage, etc.) sin pasar por Internet | Se usa con un CIDR de servicio |
| **Tabla de rutas** | Reglas «destino → siguiente salto» (gateway, DRG, IP privada) | Una por subred (puede compartirse) |
| **Lista de seguridad** | Reglas de entrada/salida aplicadas a **toda la subred** | [Siguiente unidad](../seguridad-rutas-gateways/README.md) |
| **NSG** | Reglas aplicadas a **VNIC concretas** | [Siguiente unidad](../seguridad-rutas-gateways/README.md) |
| **Opciones DHCP** | DNS que reciben las instancias (resolutor de la VCN por defecto) | Define el dominio de búsqueda |
| **VNIC** | Tarjeta de red virtual de una instancia; vive en una subred | Cada VNIC tiene una IP privada (y opcional pública) |

### Subred pública y privada
| | Pública | Privada |
|---|---|---|
| IP pública en los recursos | Permitida | **Prohibida** (se fuerza al crear la subred) |
| Ruta a Internet | Vía IGW | Vía NAT Gateway (solo salida) |
| Típico | Balanceador de carga, bastión | App, nodos OKE, base de datos |

### Direcciones reservadas
En cada subred OCI reserva **3 direcciones**: la primera (red), la segunda (gateway virtual del router) y la última (difusión). Un `/24` ofrece **253** utilizables; un `/28`, **13**. Planifica con ese margen.

### Dimensionar
| Subred | Tamaño común | Motivo |
|---|---|---|
| Balanceador | `/27`–`/24` | Pocas IP, pero crecen al escalar |
| Nodos / pods de OKE | `/24` o más | Con la red de pods nativa de VCN, **cada pod consume una IP de la subred** *(verifica)* |
| Base de datos | `/28`–`/26` | Pocas instancias |
| Reserva | Deja bloques libres | Para crecer sin renumerar |

### Quién ve a quién
Dentro de la VCN, **todas las subredes se alcanzan por defecto** (ruta local implícita); lo que limita es la lista de seguridad/NSG. Entre VCN distintas no hay ruta hasta que haya peering o DRG ([unidad de peering](../drg-peering/README.md)).

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Aislar entornos | Una VCN por entorno (o por dominio de riesgo), en compartimentos distintos |
| Exponer solo un balanceador | Subred pública solo para él |
| Todo en una subred pública | **No**: expone la app y la base |
| CIDR que solapa con on-premises u otra VCN | **No**: imposibilita el peering |
| Subredes por AD sin necesidad | **No**: usa regionales |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **CIDR** | Rango de IP en notación `10.30.0.0/16` |
| **Subred regional** | Subred que abarca todos los AD de la región |
| **Gateway** | Puerta de la VCN hacia otro lugar |
| **Tabla de rutas** | «Para ir a X, usa la puerta Y» |
| **VNIC** | Tarjeta de red virtual |
| **IP reservada** | Las 3 direcciones que OCI no entrega |
| **Solapamiento** | Dos redes con rangos que se pisan; impide conectarlas |

## 5. Cómo se usa
1. Define el plan de CIDR de **todo el tenancy** (hoja de cálculo o el planificador en [Java](uso-en-java.md)).
2. Crea la VCN, los gateways, las tablas de rutas y las subredes con **Terraform**: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
3. Comprueba con la CLI: [`ejemplos/cli/vcn.sh`](ejemplos/cli/vcn.sh).
4. Añade seguridad ([siguiente unidad](../seguridad-rutas-gateways/README.md)) y endpoints privados ([PrivateLink-equivalente](../endpoints-privados-dns/README.md)).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Equipo de red | `manage virtual-network-family` en el compartimento de red | — |
| Equipo de aplicación | `use virtual-network-family` (adjuntar VNIC a subredes existentes) o `read` | Tráfico según listas de seguridad/NSG |
| Auditoría | `inspect virtual-network-family`, registro de auditoría | Registros de flujo de la VCN |

- Mantén **VCN y subredes en un compartimento de red**, y las aplicaciones en otros: separa quien define la red de quien la usa.
- **Activa los registros de flujo** (*VCN flow logs*) de las subredes críticas.
- Subredes **privadas** por defecto; la pública solo para el balanceador.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Un plan de CIDR único para toda la empresa | Usar `10.0.0.0/16` en todas partes |
| Subredes regionales y privadas | Subredes por AD sin motivo |
| NAT Gateway para salidas | IP públicas en las VM de aplicación |
| Service Gateway para Object Storage | Salir a Internet para hablar con servicios de Oracle |
| Dejar espacio libre en el CIDR | Llenar la VCN al 100 % |
| Todo con Terraform | Editar tablas de rutas a mano |

## 8. Límites, costos y versiones
- **Costo:** la VCN, subredes, IGW, rutas y listas de seguridad son **gratuitas**; la NAT Gateway es gratuita pero la salida de datos tiene tarifa; los balanceadores y la DRG tienen sus propias tarifas. *(verifica)*
- **Límites** (verifica): VCN por región, bloques CIDR por VCN, reglas por lista de seguridad (200) y por NSG, NSG por VNIC (5).
- **Terraform:** `oci_core_vcn`, `oci_core_subnet`, `oci_core_internet_gateway`, `oci_core_nat_gateway`, `oci_core_service_gateway`, `oci_core_route_table`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
