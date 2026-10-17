# Google Cloud · 01 Red

La red es lo primero que se diseña y lo último que se quiere cambiar. En Google Cloud la VPC es **global**, las subredes **regionales** y el **firewall** decide qué pasa.

| Unidad | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [VPC y subredes](vpc-subredes/README.md) | ¿Cómo reparto direcciones entre regiones y equipos? | Autopista privada entre sucursales | Base de red, Shared VPC, GKE |
| [Firewall, rutas y Cloud NAT](firewall-rutas-nat/README.md) | ¿Qué tráfico pasa y cómo salgo a Internet? | Guardias en las puertas y salida vigilada | Reglas por cuenta de servicio, NAT |
| [Conectividad entre redes e híbrida](conectividad-hibrida/README.md) | ¿Cómo uno VPC entre sí y con mi oficina? | Puertas, pisos compartidos, túneles | Peering, Shared VPC, HA VPN, Interconnect |
| [Acceso privado](acceso-privado/README.md) | ¿Cómo llego a las APIs y servicios sin Internet? | Ascensor de servicio del hotel | PGA, PSC, PSA, DNS privado |
| [Diagnóstico de conectividad](diagnostico-conectividad/README.md) | ¿Por qué no conecta? | Rastrear un paquete | Connectivity Tests, flow logs |

## Árbol de decisión: «quiero…»

```
¿Red para varios proyectos de la organización?        → Shared VPC (proyecto host, networkUser por subred)
¿GKE con IPs de pods en la VPC?                        → Subred con rangos secundarios
¿Permitir tráfico solo desde el balanceador?           → Firewall por cuenta de servicio desde sus rangos
¿Prohibir algo en toda la organización?                → Política de firewall jerárquica
¿Salir a Internet sin IP pública?                      → Cloud NAT (IPs reservadas si hay listas blancas)
¿Llegar a APIs de Google sin IP pública?               → PGA (simple) o PSC + DNS privado (control)
¿Cloud SQL/Memorystore con IP privada?                 → PSA
¿Unir con otra VPC u organización?                     → Peering (no transitivo) o PSC para un servicio
¿Unir con la oficina o el centro de datos?             → HA VPN (BGP) o Interconnect
¿No conecta?                                           → Método por capas + Connectivity Tests
```

## Comparativa

| Necesidad | Opción | Alcance | Error típico |
|---|---|---|---|
| Direcciones | VPC + subredes | Global / regional | Modo automático |
| Filtrar | Firewall de VPC / políticas | Red / jerarquía | Reglas por etiqueta |
| Salida | Cloud NAT | Regional | Puertos agotados |
| Unir redes | Peering / Shared VPC | Entre VPC | Esperar transitividad |
| Híbrido | HA VPN / Interconnect | Regional | Un solo túnel |
| APIs privadas | PGA / PSC | Subred / red | PSC sin DNS |

## La receta ModaLima
| Necesidad | Pieza | Por qué |
|---|---|---|
| Red común | Shared VPC `modalima-vpc` en `red-compartida` | Centraliza administración |
| Plataforma GKE | Subred `apps` con secundarios de pods/servicios | IPs nativas de VPC |
| Seguridad | Política jerárquica deny 22/3389 + reglas por SA | Prevención en toda la organización |
| Pagos externos | Cloud NAT con IPs reservadas | Lista blanca del proveedor |
| APIs y Cloud SQL | PGA + PSA | Sin IP públicas |
| Oficina | HA VPN con BGP, modo `GLOBAL` | Redundancia |

## Orden recomendado de adopción
1. Plan de direcciones de toda la empresa.
2. Shared VPC y borrado de la red `default`.
3. Políticas jerárquicas y reglas por cuenta de servicio.
4. PGA/PSA y NAT.
5. Conectividad híbrida.
6. Flow logs, logs de firewall y pruebas de conectividad como código.

## Reglas transversales
- Nada de IP públicas en VMs (política de organización).
- Reglas por identidad, no por etiqueta.
- Rangos sin solapes, incluidos secundarios y PSA.
- El camino privado no da permisos: IAM sigue mandando.
- Diagnostica con método, no abriendo reglas.

## Java en red: qué construye cada `uso-en-java.md`
| Unidad | Qué construyes | Patrón común |
|---|---|---|
| VPC | Auditor de solapes, PGA y flow logs | Lógica pura + adaptador de la biblioteca |
| Firewall | Auditor de reglas peligrosas | Lectura paginada con `iterateAll` |
| Conectividad | Verificador de peerings y solapes | Lo ilegible es hallazgo |
| Acceso privado | Verificador de PGA y DNS privado | Dos APIs combinadas |
| Diagnóstico | Simulador de firewall | Prueba de configuración en el pipeline |

## Cómo se relaciona con otros capítulos
- [IAM](../02-iam/README.md): cuentas de servicio como objetivo de reglas.
- [Compute](../04-compute/README.md): GKE, Cloud Run (conector VPC / salida directa).
- [Ingress](../05-ingress-api/README.md): rangos de los balanceadores.
- [Datos](../08-datos/README.md): PSA para Cloud SQL y Memorystore.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos, troubleshooting, repaso y prompt de NotebookLM.
