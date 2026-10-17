# AWS · Red · Diagnóstico de conectividad

Cuando «no conecta», no se adivina: se **mide**. Este servicio reúne las herramientas para encontrar **en qué punto exacto** se pierde el tráfico: **Reachability Analyzer**, **VPC Flow Logs**, **Network Access Analyzer**, **Session Manager / ECS Exec** para probar desde dentro y las métricas de los componentes de red.

## 1. Qué es

**Analogía:** cuando un paquete se pierde, hay que preguntar a cada puerta del camino. **Reachability Analyzer** es el plano que te dice *«en teoría, por este camino debería pasar o se frena aquí»* (revisa la configuración, no envía tráfico). **Flow Logs** son las cámaras de las puertas: dicen *«qué pasó de verdad»* (aceptado o rechazado). Las pruebas desde dentro (`nc`, `dig`) son *caminar tú mismo el pasillo*.

```
 ¿Falla A → B:5432?
   1. ¿Resuelve el nombre y a qué IP?         → dig / nslookup (desde A)
   2. ¿La configuración permite el camino?     → Reachability Analyzer (ruta, NACL, SG, peering/TGW, endpoint)
   3. ¿Qué vio la red cuando A intentó?        → Flow Logs: ACCEPT / REJECT en origen y destino
   4. ¿Llega el SYN y nadie responde?          → ¿escucha el servicio? (ss -ltnp)  → "refused" vs "timeout"
   5. ¿Falla solo a veces?                     → NAT (ErrorPortAllocation), idle timeout, DNS, pool
```

## 2. Cómo funciona por dentro

### Reachability Analyzer
- Creas una **ruta de análisis** (*Network Insights path*): origen y destino (ENI, instancia, IGW, TGW, VPC endpoint, peering…), protocolo y puerto de destino.
- Lanzas un **análisis**: AWS recorre el modelo de la configuración de red (**no manda paquetes**) y responde **alcanzable / no alcanzable**, con el **componente que bloquea** y la **explicación** (código).
- Cubre: tablas de rutas, SG, NACL, peering, TGW, endpoints, balanceadores, NAT…
- Limitaciones: no ve problemas de aplicación, DNS ni conexiones intermitentes; coste **por análisis**. *Verifica precio y cobertura.*

### VPC Flow Logs
- Registran **metadatos** de tráfico IP por ENI, subred o VPC: origen, destino, puertos, protocolo, paquetes, bytes, **ACCEPT/REJECT**. No guardan el contenido.
- Destinos: **CloudWatch Logs** (consultas con Logs Insights), **S3** (consultas con Athena, más barato a gran escala) o **Data Firehose**.
- Hay un **formato personalizado** con campos extra (`pkt-srcaddr`, `flow-direction`, `tcp-flags`, `az-id`…) que mejora el diagnóstico.
- Tienen **retraso** (minutos) y **no capturan** algunos tráficos (DNS del resolutor de la VPC `+2`, metadatos de instancia, DHCP).
- Cómo leer un `REJECT`: lo rechaza un **SG** o una **NACL**. Si el origen ve `ACCEPT` y el destino nunca lo registra, se pierde en el camino (ruta, NACL del destino).

### Network Access Analyzer
Responde a preguntas de **seguridad** («¿hay algún camino desde internet a mis bases?») evaluando el alcance posible, no una conexión puntual.

### Pruebas desde dentro
- **Session Manager (SSM)** o **ECS Exec** para entrar a una tarea o instancia **sin abrir el 22**.
- `dig`/`nslookup` (DNS), `nc -vz host puerto` (TCP), `curl -v` (TLS/HTTP), `traceroute`/`mtr`.
- Una herramienta en Java para el mismo propósito: [`ConnCheck.java`](ejemplos/java/ConnCheck.java).

### Métricas útiles por componente
| Componente | Métrica | Qué indica |
|---|---|---|
| NAT Gateway | `ErrorPortAllocation`, `PacketsDropCount`, `ActiveConnectionCount` | Puertos agotados, descartes |
| Balanceador | `TargetConnectionErrorCount`, `HealthyHostCount`, `HTTPCode_ELB_5XX_Count` | Fallos hacia los destinos |
| TGW | `PacketDropCountNoRoute`, `BytesIn/Out` | Falta de ruta |
| Endpoint | `PacketsDropped`, `BytesProcessed` | Descartes en PrivateLink |

## 3. Para qué sirve y cuándo NO

| Quiero… | Herramienta |
|---|---|
| Saber si la configuración permite A→B | Reachability Analyzer |
| Saber qué pasó realmente | Flow Logs |
| Saber si hay exposición no deseada | Network Access Analyzer |
| Probar DNS, puerto o TLS desde la app | `ConnCheck`/`nc`/`dig` por SSM o ECS Exec |
| Ver contenido de los paquetes | Traffic Mirroring (con cuidado y por tiempo limitado) |

**Cuándo NO:** Reachability no explica un fallo de **aplicación** (el puerto está abierto pero el servicio responde 500) ni uno **intermitente** de capacidad.

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Network Insights path/analysis** | Definición del camino / resultado del análisis |
| **Explicación** | Por qué no es alcanzable (componente + código) |
| **ACCEPT / REJECT** | Decisión de SG/NACL registrada en Flow Logs |
| **Timeout vs refused** | Se descarta en silencio vs llega y nadie escucha |
| **Registro de flujo personalizado** | Elegir los campos que se guardan |
| **ECS Exec / SSM** | Entrar a probar sin abrir puertos |
| **Retorno** | La respuesta debe poder volver (NACL, rutas asimétricas) |

## 5. Cómo se usa (receta de 6 pasos)
1. **Nombre → IP:** `dig`/`ConnCheck` desde el origen. ¿IP privada esperada?
2. **Reachability Analyzer** origen→destino:puerto. ¿Alcanzable? Si no, lee la explicación y arregla ese componente.
3. **Flow Logs** del origen y del destino en el instante de la prueba (consultas en [`ejemplos/logs-insights`](ejemplos/logs-insights/consultas.md)).
4. **Refused o timeout:** `refused` = llega y no escucha; `timeout` = se descarta.
5. **Intermitente:** métricas del NAT, balanceador, pool y DNS.
6. **Cierra:** documenta la causa y deja un **análisis y una alarma** guardados como código ([`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf)).

CLI: [`ejemplos/cli/diagnostico.sh`](ejemplos/cli/diagnostico.sh).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Soporte/operaciones | `ec2:CreateNetworkInsightsPath`, `Start/DescribeNetworkInsightsAnalyses` | Entrar por **SSM/ECS Exec** (permiso auditado) |
| Seguridad | Leer Flow Logs, Network Access Analyzer | — |
| Aplicaciones | — | Ninguno de esto |

- Los Flow Logs contienen **direcciones IP**: trátalos como datos sensibles; destino cifrado (KMS) y retención definida.
- Entra a las máquinas con **SSM/ECS Exec** (queda en CloudTrail), no abriendo el puerto 22.
- Traffic Mirroring captura contenido: solo con aprobación y por tiempo limitado.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Flow Logs activos desde el principio | Activarlos «cuando haya un incidente» |
| Formato personalizado con `pkt-srcaddr`, `flow-direction`, `az-id` | Quedarte con el formato por defecto sin campos de diagnóstico |
| Medir primero (nombre → análisis → flujos) | Abrir `0.0.0.0/0` «para probar» |
| Dejar análisis guardados para las rutas críticas | Rehacerlos a mano en cada incidente |
| Alarmas por `REJECT` anómalos y por NAT | Esperar a que lo reporte el cliente |
| Entrar por SSM/ECS Exec | Dejar abierto el 22 |

## 8. Límites, costos y versiones
- **Costo:** Reachability **por análisis**; Flow Logs: ingesta de CloudWatch o almacenamiento en S3 (el más barato) más consultas de Athena. *Verifica precios.*
- **Límites:** retraso de minutos; no registra todo el tráfico; sin contenido.
- **Terraform:** `aws_ec2_network_insights_path`, `aws_flow_log`, `aws_cloudwatch_log_metric_filter`. Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
