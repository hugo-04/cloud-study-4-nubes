# Oracle OCI · Red · Listas de seguridad, NSG, rutas y gateways

En OCI, **qué puede hablar con qué** se decide en dos niveles: las **reglas de seguridad** (listas de seguridad y grupos de seguridad de red, NSG) permiten o no el tráfico, y las **tablas de rutas** deciden por qué puerta sale. Este documento explica cómo funcionan juntas y cómo se diseñan.

## 1. Qué es

**Analogía:** en el barrio cerrado ([VCN](../vcn-subredes/README.md)), la **lista de seguridad** es el reglamento de la **entrada de cada calle** (aplica a todas las casas de esa calle); el **NSG** es la **llave individual de cada casa o grupo de casas**; la **tabla de rutas** son los letreros que dicen «para ir a Internet, por la puerta norte».

```
  Internet ─► IGW ─► [ Subred lb ]  lista de seguridad: permite 443 desde 0.0.0.0/0
                        │  NSG-lb → NSG-app (puerto 8080)
                        ▼
                    [ Subred app ]  NSG-app: entrada 8080 solo desde NSG-lb
                        │  NSG-app → NSG-datos (puerto 5432)
                        ▼
                    [ Subred datos ] NSG-datos: entrada 5432 solo desde NSG-app
```

## 2. Cómo funciona por dentro

### Lista de seguridad vs NSG
| | Lista de seguridad | NSG |
|---|---|---|
| Se aplica a | **Subred** completa | **VNIC** concretas (cualquier subred de la VCN) |
| Origen/destino | CIDR o CIDR de servicio | CIDR, CIDR de servicio **u otro NSG** |
| Granularidad | Gruesa | Fina (por rol: lb, app, datos) |
| Límite orientativo | 5 listas por subred, 200 reglas por lista | 5 NSG por VNIC (verifica) |
| Recomendación | Mínimo común (ICMP, etc.) | **Reglas de la aplicación** |

Si una VNIC está cubierta por ambas, el tráfico se permite si **cualquiera** lo permite (unión de reglas). Todo lo no permitido se deniega: **no existen reglas de denegación**.

### Con y sin estado
| | Con estado (*stateful*, por defecto) | Sin estado (*stateless*) |
|---|---|---|
| Seguimiento de conexión | Sí: la respuesta se permite sola | No: necesitas la regla de **ida y de vuelta** |
| Rendimiento | Normal | Mejor en tráfico enorme y simétrico |
| Úsalo | Casi siempre | Casos especiales con muchísimas conexiones |

### Reglas: qué lleva cada una
Dirección (entrada/salida), **protocolo** (TCP 6, UDP 17, ICMP 1, todos), **origen o destino**, **rango de puertos** y si es con o sin estado. Una buena regla incluye una **descripción**.

### Rutas y gateways
| Destino | Siguiente salto | Para qué |
|---|---|---|
| `0.0.0.0/0` | Internet Gateway | Subred pública |
| `0.0.0.0/0` | NAT Gateway | Salida desde subred privada |
| CIDR de servicios de Oracle | Service Gateway | Object Storage, etc. por la red de Oracle |
| CIDR on-premises / otra VCN | DRG | Híbrido y peering ([unidad](../drg-peering/README.md)) |
| IP privada | VNIC de una instancia | Aparato de red o firewall virtual |

Gana la **ruta más específica** (prefijo más largo). Una tabla de rutas se asocia a una o varias subredes; la ruta local de la VCN siempre existe.

### OCI Network Firewall
Para inspección profunda (IPS, filtrado por URL) existe **OCI Network Firewall** (basado en Palo Alto), que se coloca en la ruta del tráfico. No sustituye a las reglas de seguridad: las complementa. *(verifica disponibilidad)*

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Aplicación en tres capas | NSG por rol, referenciando NSG entre sí |
| Regla de ICMP/diagnóstico común a la subred | Lista de seguridad |
| `0.0.0.0/0` al puerto 22 o a la base de datos | **No** |
| Reglas por IP de cada pod/VM | **No**: usa NSG como origen |
| Todo en la lista de seguridad por defecto | **No**: se vuelve inmanejable |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Stateful** | Si dejo entrar, la respuesta sale sola |
| **Stateless** | Debo permitir ida y vuelta por separado |
| **NSG como origen** | «Permite desde cualquiera que tenga este NSG» |
| **Unión de reglas** | Se permite si cualquiera de las reglas aplicables lo permite |
| **CIDR de servicio** | Rango que representa a un servicio de Oracle |
| **Ruta más específica** | Gana el prefijo más largo |

## 5. Cómo se usa
1. Una **lista de seguridad mínima** por subred (ICMP necesario para MTU y nada más).
2. Un **NSG por rol** y reglas que se referencian entre NSG: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
3. Asigna los NSG a las VNIC (balanceador, nodos, base de datos).
4. Audita con [`ejemplos/cli/auditar.sh`](ejemplos/cli/auditar.sh) o con el auditor de [Java](uso-en-java.md).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Equipo de red | `manage network-security-groups`, `manage security-lists` | — |
| Equipo de aplicación | `use network-security-groups` (asignar a VNIC) | Tráfico permitido por las reglas |
| Auditoría | `inspect network-security-groups`, `inspect security-lists` | Registros de flujo |

- **Mínimo privilegio de red**: puertos concretos, orígenes concretos.
- Los **cambios de reglas** quedan en Audit; vincula una alerta a cambios en producción.
- **Registros de flujo** en las subredes críticas.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| NSG por rol con referencias entre NSG | Reglas con CIDR amplios entre capas |
| Descripción en cada regla | Reglas sin explicación |
| Permitir solo el puerto necesario | `all protocols` desde cualquier lugar |
| Acceso administrativo por Bastion/sesión | SSH abierto a Internet |
| Auditar reglas con una herramienta | Revisar a ojo en la consola |
| Cambios por Terraform y revisión | Editar en producción a mano |

## 8. Límites, costos y versiones
- **Costo:** listas de seguridad, NSG y rutas son gratuitas. Network Firewall tiene costo. *(verifica)*
- **Límites** (verifica): reglas por lista y por NSG, NSG por VNIC, listas por subred.
- **Terraform:** `oci_core_security_list`, `oci_core_network_security_group`, `oci_core_network_security_group_security_rule`, `oci_core_route_table`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
