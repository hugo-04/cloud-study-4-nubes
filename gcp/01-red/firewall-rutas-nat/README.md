# Google Cloud · Red · Firewall, rutas y Cloud NAT

Dentro de una VPC todo es alcanzable por ruta; lo que decide si un paquete pasa es el **firewall** (reglas de VPC y políticas de firewall jerárquicas o de red). Las **rutas** deciden por dónde sale el tráfico, y **Cloud NAT** da salida a Internet a recursos sin IP pública.

## 1. Qué es

**Analogía:** un edificio con calles internas (rutas), guardias en cada puerta (firewall) y una sola salida vigilada al exterior por donde salen los repartidores sin que nadie de afuera pueda entrar por ahí (NAT).

```
 Internet ◄── Cloud NAT (Cloud Router, IPs reservadas) ◄── VMs/pods sin IP externa
                                         ▲
 Políticas de firewall: organización → carpeta → red  (allow/deny/goto_next, por prioridad)
 Reglas de VPC:  entrada denegada por defecto · salida permitida por defecto
   allow tcp:8080 desde rangos del balanceador hacia SA "app-pedidos"
   allow tcp:22   desde 35.235.240.0/20 (IAP) hacia tag "bastion"
 Rutas: subredes (sistema) · 0.0.0.0/0 → default-internet-gateway · personalizadas/BGP (Cloud Router)
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Regla de firewall de VPC** | Dirección, prioridad (0–65535, menor gana), acción, protocolo/puertos, origen/destino |
| **Objetivos** | Todas las instancias, **etiquetas de red** o **cuentas de servicio** (recomendado) |
| **Reglas implícitas** | Entrada denegada y salida permitida (prioridad 65535) |
| **Políticas de firewall jerárquicas** | En organización/carpetas; se evalúan antes que las de VPC; `goto_next` delega |
| **Políticas de firewall de red** | Agrupan reglas por red (global o regional); soportan tags seguros y FQDN *(verifica)* |
| **Firewall Rules Logging** | Registra coincidencias por regla |
| **Rutas** | Destino + siguiente salto (gateway, instancia, IP, VPN, ILB); prioridad |
| **Cloud Router** | BGP para rutas dinámicas y plano de control de Cloud NAT |
| **Cloud NAT** | Salida a Internet sin IP pública; puertos por VM, IPs manuales o automáticas |

### Orden de evaluación
1. Políticas jerárquicas (organización → carpetas).
2. Política de firewall de red / reglas de VPC por prioridad.
3. Reglas implícitas.
Las conexiones son **con estado**: la respuesta de una conexión permitida vuelve sin regla adicional.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Permitir solo al balanceador hablar con las apps | Regla por **cuenta de servicio** desde los rangos del balanceador |
| Prohibir SSH desde Internet en toda la organización | Política jerárquica `deny` |
| SSH administrativo | IAP TCP forwarding (rango de IAP), no IP pública |
| Salida a una API externa sin IP pública | Cloud NAT con IPs reservadas (para listas blancas del proveedor) |
| Filtrar por URL/contenido | **No**: Cloud Armor o un proxy |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Con estado** | La respuesta vuelve sola |
| **Etiqueta de red vs cuenta de servicio** | Texto libre en la VM vs identidad (más segura) |
| **Prioridad** | Número menor se evalúa primero |
| **Puertos por VM en NAT** | Cuántas conexiones simultáneas puede abrir cada VM |
| **IAP** | Acceso administrativo por identidad sin exponer puertos |

## 5. Cómo se usa
1. Reglas por cuenta de servicio, deny de SSH público, IAP y Cloud NAT: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Audita reglas peligrosas desde [Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/firewall.sh`](ejemplos/cli/firewall.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Seguridad de red | `roles/compute.securityAdmin` (firewall) | — |
| Equipo de red | `roles/compute.networkAdmin` (rutas, NAT) | — |
| Auditoría | `roles/compute.networkViewer` | Logs de firewall y NAT |

- Reglas por **cuenta de servicio**, no por etiqueta (cualquiera con permiso de editar la VM cambia etiquetas).
- Nada de `0.0.0.0/0` de entrada salvo en el balanceador.
- Logs de firewall en reglas de denegación y en las críticas.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Políticas jerárquicas para lo prohibido en todo | Repetir reglas en cada proyecto |
| Objetivos por cuenta de servicio | Reglas para «todas las instancias» |
| IAP para SSH/RDP | Puerto 22 abierto a Internet |
| NAT con IPs reservadas y alertas de puertos agotados | NAT automático sin monitoreo |
| Borrar reglas `default-allow-*` | Dejar la red `default` |

## 8. Límites, costos y versiones
- **Costo:** reglas sin costo; Cloud NAT por hora de gateway y por GB procesado; logs en Logging *(verifica)*.
- **Límites** (verifica): reglas por proyecto, reglas por política, puertos por VM en NAT.
- **Terraform:** `google_compute_firewall`, `google_compute_firewall_policy`, `google_compute_router`, `google_compute_router_nat`, `google_compute_route`.
- **Java:** `FirewallsClient`, `RoutersClient`, `RoutesClient` (`google-cloud-compute`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
