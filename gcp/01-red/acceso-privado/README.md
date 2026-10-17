# Google Cloud · Red · Acceso privado a servicios (PGA, PSC, PSA y Cloud DNS)

Cómo llegar a las APIs de Google y a servicios administrados **sin salir a Internet**: **Private Google Access** (PGA) para las APIs desde subredes sin IP externa, **Private Service Connect** (PSC) para un endpoint privado propio hacia APIs o servicios publicados, **Private Service Access** (PSA) para servicios administrados con IP privada (Cloud SQL, Memorystore) y **Cloud DNS** privado para que los nombres resuelvan a esas IPs.

## 1. Qué es

**Analogía:** el ascensor de servicio de un hotel. Los huéspedes (tus VMs y pods) llegan a la lavandería, la cocina y el depósito (servicios de Google) sin salir a la calle; un directorio interno (DNS privado) dice a qué piso ir.

```
 Subred privada (sin IP externa)
   ├─ PGA ✓ ──────────────► storage.googleapis.com (IPs de Google, ruta por defecto interna)
   ├─ PSC endpoint 10.10.99.10 ─► "all-apis" o "vpc-sc"  (DNS privado: *.googleapis.com → 10.10.99.10)
   ├─ PSA (peering de servicenetworking, rango 10.50.0.0/16) ─► Cloud SQL / Memorystore con IP privada
   └─ PSC consumidor ─► servicio publicado por otro equipo u organización (attachment)
 Cloud DNS: zonas privadas ligadas a la VPC · políticas de reenvío · peering de DNS
```

## 2. Cómo funciona por dentro

### Opciones
| Opción | Qué resuelve | Detalle |
|---|---|---|
| **PGA** | APIs de Google desde subredes sin IP externa | Se activa por subred; usa los dominios públicos o `private.googleapis.com` / `restricted.googleapis.com` |
| **VIPs privadas/restringidas** | `199.36.153.8/30` (privado) y `199.36.153.4/30` (restringido, para VPC Service Controls) | Requieren ruta y DNS *(verifica rangos)* |
| **PSC para APIs de Google** | Endpoint con IP **de tu subred** hacia un paquete de APIs | Control total de IP y DNS |
| **PSC para servicios publicados** | Consumir un servicio de otro proyecto/organización como IP local | Sin peering ni solapes |
| **PSA** | Servicios administrados con IP privada mediante peering con la red de Google | Reserva un rango asignado (`/16` o `/20`) |
| **Cloud DNS privado** | Zonas visibles solo desde VPC elegidas | Reenvío a DNS local y peering de DNS |

### Elegir
- Solo APIs de Google, simple → PGA.
- Necesitas IP fija, VPC Service Controls o resolver desde la oficina → PSC + DNS privado.
- Cloud SQL/Memorystore con IP privada → PSA (o PSC si el servicio lo ofrece).

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| GKE privado que baja imágenes y lee Secret Manager | PGA en la subred |
| Perímetro de VPC Service Controls | `restricted.googleapis.com` o PSC `vpc-sc` |
| Cloud SQL sin IP pública | PSA (o PSC) |
| Exponer tu API interna a otra organización | PSC productor (attachment) |
| Acceso a Internet general (APIs de terceros) | **No**: Cloud NAT |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **IP externa** | Dirección pública de una VM (evítala) |
| **VIP** | Dirección virtual de un servicio |
| **Endpoint PSC** | Una IP de tu subred que lleva a un servicio |
| **Rango asignado (PSA)** | Bloque reservado para los servicios administrados |
| **Zona privada** | DNS que solo ve tu red |

## 5. Cómo se usa
1. PSC para APIs, DNS privado y PSA para Cloud SQL: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Verifica PGA y DNS privado desde [Java](uso-en-java.md).
3. Pruebas: [`ejemplos/cli/acceso-privado.sh`](ejemplos/cli/acceso-privado.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Equipo de red | `roles/compute.networkAdmin`, `roles/dns.admin`, `roles/servicenetworking.networksAdmin` | — |
| Apps | — | Sus roles de IAM sobre cada API (el acceso privado no da permisos) |

- El acceso privado **no** reemplaza IAM: solo cambia el camino.
- VPC Service Controls para evitar exfiltración hacia proyectos ajenos.
- Política de organización que restringe IP públicas en Cloud SQL.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| PGA en todas las subredes privadas | IP pública solo para llamar APIs |
| DNS privado coherente con la opción elegida | Endpoints PSC sin DNS (todos siguen usando la IP pública) |
| Reservar el rango PSA en el plan de direcciones | Rangos PSA que chocan al crecer |
| Probar resolución y ruta desde la VM | Suponer que «debería ir por privado» |

## 8. Límites, costos y versiones
- **Costo:** PGA sin cargo; PSC por endpoint-hora y GB; Cloud DNS por zona y consultas *(verifica)*.
- **Límites** (verifica): endpoints PSC por red, tamaño del rango PSA.
- **Terraform:** `google_compute_global_address`, `google_compute_global_forwarding_rule` (PSC APIs), `google_service_networking_connection`, `google_dns_managed_zone`, `google_dns_record_set`.
- **Java:** `SubnetworksClient` y `com.google.cloud.dns.Dns` para verificar.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
