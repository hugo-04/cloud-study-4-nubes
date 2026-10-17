# Oracle OCI · Red · DRG, peering e híbrido

Cuando tienes **más de una red** (producción y desarrollo, una VCN central y varias de aplicación, o tu oficina y OCI), necesitas conectarlas. En OCI el centro de conexión es la **DRG** (*Dynamic Routing Gateway*): un router virtual al que se **adjuntan** VCN, VPN y circuitos dedicados, con tablas de rutas propias.

## 1. Qué es

**Analogía:** una **estación central de trenes**. Cada barrio ([VCN](../vcn-subredes/README.md)) tiene su andén (*attachment*); la estación (DRG) tiene su tablero de destinos (tabla de rutas de la DRG) que decide a qué andén va cada tren. También llegan trenes de otras ciudades (VPN, FastConnect, otra región).

```
        Oficina ──(VPN IPSec / FastConnect)──┐
                                             ▼
   VCN-spoke-prod ──attach──►  ┌────── DRG ──────┐ ◄──attach── VCN-hub (red central, firewall, DNS)
   VCN-spoke-dev  ──attach──►  └────────┬────────┘
                                        │ RPC (peering remoto)
                                        ▼
                                 DRG de otra región
```

## 2. Cómo funciona por dentro

### Formas de conectar
| Opción | Qué conecta | Cuándo |
|---|---|---|
| **DRG con adjuntos de VCN** | Varias VCN de la misma o distinta región/tenancy | **La opción actual** para hub-and-spoke |
| **LPG** (*Local Peering Gateway*) | Dos VCN de la misma región, directo | Casos simples y antiguos; la DRG lo sustituye en diseños nuevos |
| **RPC** (*Remote Peering Connection*) | Dos DRG de regiones distintas | Peering entre regiones |
| **Site-to-Site VPN (IPSec)** | OCI ↔ red on-premises por Internet cifrado | Híbrido rápido y barato |
| **FastConnect** | OCI ↔ on-premises por enlace dedicado | Ancho de banda estable y baja latencia |

### Piezas de la DRG
| Pieza | Qué es |
|---|---|
| **DRG** | Router virtual regional |
| **Adjunto (attachment)** | Conexión de la DRG con una VCN, un IPSec, un circuito virtual o una RPC |
| **Tabla de rutas de la DRG** | A dónde va el tráfico que **entra** por cada adjunto |
| **Distribución de rutas** | Qué rutas se **importan/exportan** automáticamente entre adjuntos |
| **Tabla de rutas de la VCN** | Debe enviar el tráfico remoto **a la DRG** |

Un paquete solo cruza si **tres cosas** coinciden: la subred origen tiene ruta **a la DRG**, la DRG tiene ruta **al adjunto destino**, y las reglas de seguridad de destino lo permiten. Y los CIDR **no deben solaparse**.

### Hub-and-spoke
La VCN **hub** concentra servicios compartidos (firewall, DNS, bastión). Las **spoke** se adjuntan a la DRG; una tabla de rutas de la DRG para spokes envía `0.0.0.0/0` al adjunto del hub (donde un firewall inspecciona). Así dev y prod **no se hablan** entre sí salvo por el hub.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Varias VCN + on-premises | DRG con hub-and-spoke |
| Dos VCN en la misma región, sin más | DRG igualmente (LPG solo por herencia) |
| Dev y prod hablando libremente | **No**: aíslalos con tablas de rutas de la DRG |
| CIDR solapados | **No**: renumerar o usar NAT intermedio |
| Datos masivos por la VPN | Considera FastConnect |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **DRG** | Router central regional |
| **Adjunto** | Un andén de la estación |
| **Distribución de rutas** | Regla que decide qué rutas se aprenden solas |
| **RPC** | Peering entre DRG de distintas regiones |
| **Hub / spoke** | Red central / redes de aplicación |
| **Tránsito** | Tráfico que atraviesa la DRG hacia otro adjunto |

## 5. Cómo se usa
1. Verifica que **no hay solapes** de CIDR (el verificador de [Java](uso-en-java.md)).
2. Crea la DRG y los adjuntos con Terraform: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
3. En cada VCN, añade la ruta al CIDR remoto con destino la DRG.
4. Ajusta las reglas de seguridad de los destinos.
5. Inspecciona: [`ejemplos/cli/drg.sh`](ejemplos/cli/drg.sh).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Equipo de red central | `manage drgs`, `manage drg-attachments` | — |
| Equipo de aplicación | Ninguno sobre la DRG | Tráfico según reglas y rutas |
| Entre tenancies | Políticas `endorse`/`admit` explícitas para adjuntar | — |

- La DRG **no filtra** por sí misma: la seguridad sigue en listas de seguridad/NSG y, si hace falta, en un firewall en el hub.
- Para peering entre tenancies se requieren políticas de ambos lados.
- Cifrado: IPSec cifra; FastConnect no cifra por defecto (puedes superponer IPSec). *(verifica)*

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Plan único de CIDR | Redes `10.0.0.0/16` repetidas |
| Hub-and-spoke con tablas de rutas por rol | Todo con todo |
| Inspección en el hub | Confiar solo en reglas de cada spoke |
| Dos túneles IPSec para redundancia | Un solo túnel |
| Terraform para adjuntos y rutas | Rutas a mano |

## 8. Límites, costos y versiones
- **Costo:** la DRG no se cobra por sí misma; sí el tráfico de salida entre regiones y hacia Internet, FastConnect (por puerto) y VPN (gratuita en el servicio, no en el tráfico). *(verifica)*
- **Límites** (verifica): adjuntos por DRG, rutas por tabla, DRG por región.
- **Terraform:** `oci_core_drg`, `oci_core_drg_attachment`, `oci_core_drg_route_table`, `oci_core_drg_route_distribution`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
