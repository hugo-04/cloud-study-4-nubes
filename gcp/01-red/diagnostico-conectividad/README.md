# Google Cloud · Red · Diagnóstico de conectividad

«No conecta» es el síntoma más común y el que más tiempo hace perder. Google Cloud da herramientas para responder **por qué** sin adivinar: **Connectivity Tests** (simula el camino de un paquete), **VPC Flow Logs**, **logs de reglas de firewall**, **Firewall Insights** y el **Network Intelligence Center**. Este capítulo es el método.

## 1. Qué es

**Analogía:** rastrear un paquete de mensajería: ¿salió del remitente?, ¿qué centros de distribución pasó?, ¿dónde lo detuvieron y por qué? Connectivity Tests es la simulación del recorrido; los flow logs son el registro de lo que realmente pasó.

```
 Origen (VM/pod/IP) ─► DNS ─► ruta ─► firewall de salida ─► [peering/VPN/NAT/PSC] ─► firewall de entrada ─► puerto escuchando ─► TLS ─► IAM
 Herramientas:  Connectivity Tests (estático + dinámico) · Flow Logs · Firewall Logs/Insights · Performance Dashboard
```

## 2. Cómo funciona por dentro

### Herramientas
| Herramienta | Qué responde |
|---|---|
| **Connectivity Tests** | Analiza configuración (rutas, firewall, NAT, peering, balanceadores) y dice dónde se cae el paquete; puede hacer sondeo real *(verifica)* |
| **VPC Flow Logs** | Muestras de flujos (origen, destino, puertos, bytes, latencia en TCP) por subred |
| **Logs de firewall** | Qué regla permitió o denegó cada conexión |
| **Firewall Insights** | Reglas sombra, nunca usadas o demasiado amplias |
| **Performance Dashboard** | Pérdida y latencia entre zonas/regiones |
| **Rutas efectivas** | Qué ruta usa realmente una VM |

### El método (siempre en este orden)
1. **Nombre**: ¿resuelve a la IP esperada (privada vs pública)?
2. **Ruta**: ¿hay ruta al destino desde el origen?
3. **Firewall de salida** del origen y **de entrada** del destino (incluidas políticas jerárquicas).
4. **Intermedios**: NAT, peering (no transitivo), VPN/BGP, PSC/PSA.
5. **Destino**: ¿el proceso escucha en ese puerto e interfaz?
6. **TLS** e **identidad (IAM)**: un 403 no es un problema de red.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Timeout entre dos servicios | Connectivity Tests + logs de firewall |
| Conexión intermitente | Flow logs + métricas de NAT/VPN |
| ¿Esta regla se usa? | Firewall Insights |
| Errores 403/401 | **No** es red: revisa IAM |
| Errores 5xx de la aplicación | **No** es red: registros de la app |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Análisis estático** | Revisar la configuración sin mandar paquetes |
| **Regla sombra** | Una regla que nunca se aplica porque otra la tapa |
| **Muestreo de flow logs** | Porcentaje de flujos que se registran |
| **Timeout vs rechazo** | Silencio (firewall) vs RST (nadie escucha) |

## 5. Cómo se usa
1. Activa flow logs y logs de firewall, y crea una prueba de conectividad: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf) y [`ejemplos/cli/diagnostico.sh`](ejemplos/cli/diagnostico.sh).
2. Simula las reglas de firewall para un paquete concreto desde [Java](uso-en-java.md) (un «mini Connectivity Test» para pruebas automatizadas de configuración).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Diagnóstico | `roles/networkmanagement.admin` (crear pruebas), `roles/compute.networkViewer` | `roles/logging.viewer` para flow logs |

- Los flow logs contienen IPs: acceso restringido y retención acotada.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Seguir el orden de capas | Abrir `0.0.0.0/0` «para probar» |
| Connectivity Tests antes de tocar reglas | Cambiar reglas a ciegas |
| Distinguir timeout de rechazo | Tratar todo como «red caída» |
| Flow logs con muestreo en producción | 100 % en todo (costo) |
| Guardar las pruebas como código | Recrearlas en cada incidente |

## 8. Límites, costos y versiones
- **Costo:** Connectivity Tests con cargo por prueba fuera de una cuota *(verifica)*; flow logs y logs de firewall en Logging.
- **Terraform:** `google_network_management_connectivity_test`, `log_config` en subredes y reglas.
- **Java:** `FirewallsClient` para leer reglas y simular (no hay biblioteca de Connectivity Tests en el BOM usado aquí).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
