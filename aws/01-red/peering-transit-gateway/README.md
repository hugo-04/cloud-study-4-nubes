# AWS · Red · Peering de VPC y Transit Gateway

Cómo conectar varias VPC (y la red local) entre sí. Dos herramientas principales: **VPC Peering** (un cable directo entre dos redes) y **Transit Gateway** (una central de enrutamiento a la que se conectan todas).

## 1. Qué es

**Analogía:** dos oficinas vecinas. El **peering** es una **puerta directa** entre dos oficinas: rápida y barata, pero cada puerta une solo a dos, y no puedes pasar de la A a la C a través de la B. El **Transit Gateway** es el **lobby central del edificio**: cada oficina tiene un solo pasillo hasta el lobby y desde allí el vigilante decide quién puede ir adonde.

```
 Peering (1:1, no transitivo)         Transit Gateway (centro y radios)

   VPC-A ◄────► VPC-B                    VPC-A ─┐
     ▲                                   VPC-B ─┼──► [ TGW ] ──► VPN / Direct Connect
     └─────────/ VPC-C  (A↔C requiere   VPC-C ─┘      tablas de rutas por segmento
                 otro peering)
```

## 2. Cómo funciona por dentro

### VPC Peering
- Conexión **privada 1:1** entre dos VPC (misma o distinta cuenta, misma o distinta región).
- **No transitiva:** A↔B y B↔C **no** implican A↔C. Y **no hay «edge to edge»**: A no usa el NAT/VPN/Direct Connect de B.
- **Sin CIDR solapados.**
- Pides la conexión, el otro lado la **acepta**, y luego **añades rutas en ambas tablas de rutas** (si falta una, no funciona).
- Permite referenciar **grupos de seguridad del par** en reglas (misma región).
- Opción de resolución DNS entre VPC (nombres privados).
- Sin cargo por la conexión; sí por transferencia entre AZ o regiones.
- Con muchas VPC explota: **n·(n−1)/2** conexiones.

### Transit Gateway (TGW)
- Enrutador regional administrado, alta disponibilidad, ancho de banda alto.
- **Adjuntos (attachments):** VPC, VPN, Direct Connect Gateway, peering con otro TGW, Connect (SD-WAN).
- **Tablas de rutas del TGW:** cada adjunto está **asociado** a una tabla (qué tabla usa para salir) y **propaga** sus rutas a una o más (qué tablas lo conocen). Así se segmenta: `prod` ve `compartida`, `dev` ve `compartida`, pero `prod` y `dev` no se ven.
- En cada VPC debes poner **rutas en sus tablas** hacia el TGW (p. ej. `10.0.0.0/8 → tgw-xxxx`).
- Un adjunto de VPC elige **una subred por AZ**; el tráfico entre AZ usa esa subred.
- **Modo aparato (appliance mode):** mantiene la misma AZ de ida y vuelta, necesario con firewalls en línea.
- Se comparte entre cuentas con **AWS RAM**.
- Entre regiones: **peering de TGW** con rutas estáticas.
- Cobra **por adjunto-hora y por GB procesado**.

### Alternativas
| Necesidad | Herramienta |
|---|---|
| Exponer **un servicio** sin unir redes | PrivateLink |
| Red global multirregión administrada | AWS Cloud WAN (verifica) |
| Conectar aplicaciones por nombre/servicio con políticas | VPC Lattice (verifica) |
| Red local ↔ AWS | VPN de sitio a sitio o Direct Connect, normalmente sobre TGW |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| 2–3 VPC con tráfico simple | **Peering** (barato y directo) |
| 4 o más VPC, red local, o segmentar prod/dev | **Transit Gateway** |
| Servicios compartidos (DNS, herramientas, firewall central) | TGW con VPC de servicios compartidos |
| CIDR solapados | Ninguno funciona: **PrivateLink** (o rediseñar) |
| Una API para ocho cuentas | PrivateLink |

**Cuándo NO usar TGW:** con dos VPC y mucho tráfico, el cobro por GB procesado del TGW pesa más que un peering gratuito.

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Transitivo** | Poder llegar de A a C pasando por B |
| **Asociación** | La tabla del TGW que usa un adjunto para enrutar su tráfico |
| **Propagación** | Publicar las rutas de un adjunto en una tabla |
| **Ruta estática** | La que escribes a mano (`blackhole` descarta tráfico) |
| **RAM** | Servicio para compartir recursos entre cuentas |
| **Appliance mode** | Simetría de AZ para inspección |
| **Segmentación** | Separar entornos con tablas de rutas distintas |
| **Hub-and-spoke** | Centro y radios |

## 5. Cómo se usa
1. Define el plan de CIDR **sin solapes** (hoja central).
2. Peering: solicitar → aceptar → rutas en **ambos lados** → (opcional) SG por referencia.
3. TGW: crear, adjuntar VPC (subred por AZ), crear tablas por segmento, asociar y propagar, **rutas en las VPC**.
4. Compartir el TGW con RAM a las cuentas de carga.
5. Terraform: [`ejemplos/terraform/`](ejemplos/terraform/); CLI: [`ejemplos/cli/tgw.sh`](ejemplos/cli/tgw.sh).
6. Verifica con [Reachability Analyzer](../diagnostico-conectividad/README.md).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Equipo de red (cuenta de red) | `ec2:*TransitGateway*`, RAM | — |
| Cuentas de carga | Crear el **adjunto** de su VPC (aceptación automática o manual) | — |
| Seguridad | Describe + Config | — |

- Tablas separadas por segmento: **prod no alcanza dev** por diseño, no por buena voluntad.
- Los SG y NACL siguen aplicando: unir redes **no abre** puertos.
- Aceptación manual de adjuntos en entornos sensibles.
- **Flow Logs del TGW** para auditar.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Plan de CIDR central y sin solapes | CIDR por equipo sin coordinar |
| TGW en una cuenta de red dedicada | TGW en una cuenta de carga |
| Tablas de rutas del TGW por segmento | Una tabla única «todos con todos» |
| Rutas específicas (`10.20.0.0/16`) | `0.0.0.0/0` hacia el TGW sin pensarlo |
| Peering para 2–3 VPC | Malla de 15 peerings |
| Una subred pequeña dedicada por AZ para el adjunto | Usar subredes de aplicación (consumen IP) |

## 8. Límites, costos y versiones
- **Costo:** Peering: sin cargo por la conexión, sí por transferencia entre AZ/regiones. **TGW:** por adjunto-hora y por GB procesado. *Verifica precios.*
- **Límites típicos** (verifica): peerings por VPC, adjuntos por TGW, rutas por tabla.
- **Terraform:** `aws_vpc_peering_connection`, `aws_ec2_transit_gateway*`, `aws_ram_*`. Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
