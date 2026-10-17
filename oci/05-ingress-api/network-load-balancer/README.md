# Oracle OCI · Ingress y API · Network Load Balancer (capa 4)

Balanceador de capa 4 (TCP, UDP, ICMP) que reparte paquetes sin abrirlos: latencia muy baja, rendimiento alto y, si quieres, la IP de origen del cliente llega intacta al backend. No termina TLS ni lee rutas HTTP.

## 1. Qué es

**Analogía:** el guardia del estacionamiento. No pregunta a qué vienes ni revisa tu bolso; solo mira la placa y te indica un carril libre. Es rapidísimo porque no abre nada.

```
 Clientes (TCP/UDP) ──► NLB (IP pública o privada, sin estado de app)
                          │ listener TCP :443 / UDP :5060 / ANY
                          └─► backend set (hash de 5-tupla) ──► 10.0.2.31, 10.0.2.32  (chequeo TCP/HTTP)
                                    la IP origen del cliente se preserva (opcional)
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Network load balancer** | Recurso regional, público o privado, sin forma ni ancho de banda que elegir |
| **Listener** | Puerto + protocolo `TCP`, `UDP`, `TCP_AND_UDP` o `ANY` (todos los puertos) |
| **Backend set** | Política de hash (`FIVE_TUPLE`, `THREE_TUPLE`, `TWO_TUPLE`) + chequeo de salud + `is_preserve_source` |
| **Backend** | IP o OCID de instancia + puerto; con peso, `is_drain`, `is_offline`, `is_backup` |
| **Health checker** | TCP, HTTP, HTTPS o UDP; intervalo, reintentos, código esperado |
| **Preservar origen/destino** | Modo *bump-in-the-wire* para *appliances* de red (firewalls) |
| **Hash simétrico** | Ida y vuelta por el mismo backend (útil con *appliances*) |

### Recorrido de un paquete
1. Llega al IP del NLB; se calcula el hash de la tupla elegida.
2. El hash elige un backend **sano**; mientras la conexión viva, sigue yendo al mismo.
3. Con `is_preserve_source = true`, el backend ve la IP real del cliente: **sus NSG deben permitir las IP de los clientes**, no solo la del NLB.
4. La respuesta vuelve por el NLB (el backend necesita ruta de retorno coherente).

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Kafka, MQTT, bases de datos, gRPC sin terminar TLS | **NLB** |
| UDP (VoIP, juegos, DNS, syslog) | **NLB** |
| Necesitas la IP real del cliente sin cabeceras | **NLB** con preservación de origen |
| Cadena de *firewalls* virtuales | **NLB** con preservar origen/destino y hash simétrico |
| Rutas HTTP, TLS en el balanceador, redirecciones | [Load Balancer](../load-balancer/README.md) |
| WAF delante | [Load Balancer](../load-balancer/README.md) (el WAF no se adjunta al NLB) |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Capa 4** | Solo ve IP, puerto y protocolo |
| **Hash de 5-tupla** | Origen IP+puerto, destino IP+puerto y protocolo → backend |
| **Preservación de origen** | El backend ve la IP del cliente |
| **TLS de extremo a extremo** | El certificado vive en el backend, no en el balanceador |
| **Sin forma** | Escala solo; no reservas Mbps |

## 5. Cómo se usa
1. Crea NLB privado para un clúster TCP interno: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. NSG del backend: permite el tráfico de los clientes (si preservas origen) y el chequeo desde la subred del NLB.
3. Vigila la salud desde [Java](uso-en-java.md) o con [`ejemplos/cli/nlb.sh`](ejemplos/cli/nlb.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `manage network-load-balancers` | — |
| Monitoreo | `read network-load-balancers` | — |
| Clientes | — | Paquetes al listener, filtrados por NSG |

- Sin WAF ni TLS en el NLB: **el backend** valida certificados, autentica y limita.
- Prefiere NLB **privado** para tráfico interno; público solo cuando el protocolo lo exige.
- Con preservación de origen, los NSG del backend se vuelven tu frontera: revísalos con cuidado.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Chequeo HTTP a *readiness* aunque el tráfico sea TCP | Chequeo TCP que solo prueba que el puerto abre |
| NSG del backend coherente con la preservación de origen | Permitir `0.0.0.0/0` «porque el NLB filtra» |
| TLS de extremo a extremo en el backend | Tráfico sensible en claro porque «es interno» |
| Drenar antes de retirar | Retirar el backend en caliente |
| Hash simétrico con *appliances* | Rutas asimétricas que rompen conexiones |

## 8. Límites, costos y versiones
- **Costo:** el NLB no tiene cargo por hora en muchas regiones; pagas el tráfico saliente estándar *(verifica)*.
- **Límites** (verifica): listeners, backend sets y backends por NLB; NLB por región.
- **Terraform:** `oci_network_load_balancer_network_load_balancer`, `_backend_set`, `_backend`, `_listener`.
- **SDK:** `NetworkLoadBalancerClient` (`oci-java-sdk-networkloadbalancer`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
