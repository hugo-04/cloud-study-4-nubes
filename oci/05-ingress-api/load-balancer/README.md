# Oracle OCI · Ingress y API · Load Balancer (capa 7)

El balanceador flexible de OCI recibe tráfico HTTP/HTTPS (o TCP), termina TLS si quieres, decide a qué backend mandar cada petición según reglas y deja de enviar a los que fallan el chequeo de salud.

## 1. Qué es

**Analogía:** la recepcionista de una clínica. Mira cada paciente que entra (la petición), revisa a qué especialidad va (ruta, host), lo manda al consultorio que está libre y sano, y si un médico se fue a almorzar (backend caído) deja de enviarle gente.

```
 Internet ──► IP pública del LB (subred pública, 2 nodos en alta disponibilidad)
                 │ listener :443 (certificado) ── reglas: host / ruta / cabeceras
                 ├─► backend set "catalogo"  ──► 10.0.2.11:8080, 10.0.2.12:8080  (chequeo /actuator/health)
                 └─► backend set "pedidos"   ──► 10.0.2.21:8080 …
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Load balancer** | Recurso regional; público o privado; forma `flexible` con ancho de banda mínimo y máximo (Mbps) |
| **Listener** | Puerto + protocolo (HTTP, HTTP2, TCP) + certificado opcional |
| **Backend set** | Grupo de backends + política (`ROUND_ROBIN`, `LEAST_CONNECTIONS`, `IP_HASH`) + chequeo de salud |
| **Backend** | IP:puerto de una VM, pod (vía OKE) o instancia; con peso, `drain`, `backup`, `offline` |
| **Health checker** | Protocolo, puerto, URL, código esperado, intervalo, reintentos |
| **Reglas** | *Hostnames*, *routing policies* (condiciones por ruta/cabecera), *rule sets* (añadir cabeceras, redirigir HTTP→HTTPS) |
| **Certificados** | Subidos al LB o desde el servicio Certificates |
| **Sesión persistente** | Cookie del LB o de la aplicación (evítala si puedes) |

### Recorrido de una petición
1. DNS resuelve al IP del LB; el nodo activo acepta la conexión.
2. El listener termina TLS (o lo pasa, en TCP) y evalúa reglas.
3. Elige un backend **sano** del set según la política; añade `X-Forwarded-For` y `X-Forwarded-Proto`.
4. Si el backend no responde a tiempo, devuelve `502`/`504` al cliente.

### Alta disponibilidad
El LB público regional se reparte entre dominios de disponibilidad (o dominios de fallo en regiones de un solo AD); tú no administras los nodos.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Web/API HTTP con varias réplicas | **Load Balancer** |
| Necesitas IP de origen del cliente intacta, UDP o rendimiento extremo | [Network Load Balancer](../network-load-balancer/README.md) |
| Autenticación, cuotas, transformación por API | [API Gateway](../api-gateway/README.md) (puede ir detrás) |
| Protección OWASP, bots, límites por IP | [WAF](../waf/README.md) sobre el LB |
| Exponer servicios de OKE | [Ingress en OKE](../ingress-oke/README.md) (crea el LB por ti) |
| Un único backend sin réplicas | Probablemente no lo necesitas |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Terminación TLS** | El LB descifra y habla HTTP (o re-cifra) con el backend |
| **Drenado (`drain`)** | El backend no recibe conexiones nuevas, termina las actuales |
| **Chequeo de salud** | La prueba periódica que decide si un backend recibe tráfico |
| **Forma flexible** | Ancho de banda mínimo garantizado y máximo de ráfaga |
| **Idle timeout** | Tiempo máximo sin datos en una conexión (ojo con *long polling* y WebSocket) |

## 5. Cómo se usa
1. Crea LB, backend set, backends y listener HTTPS: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Chequeo de salud apuntando a un endpoint de *readiness* (no a `/`).
3. En los despliegues, **drena** antes de retirar una réplica: [uso en Java](uso-en-java.md).
4. Diagnóstico: [`ejemplos/cli/load-balancer.sh`](ejemplos/cli/load-balancer.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `manage load-balancers` en el compartimento de red | — |
| Pipeline de despliegue | `use load-balancers` (actualizar backends) | — |
| Clientes | — | Tráfico al listener, filtrado por NSG/WAF |

- LB en subred pública; **backends en subred privada**; NSG del backend solo acepta del NSG del LB.
- TLS 1.2+ con suite de cifrado propia; redirección HTTP→HTTPS con *rule set*.
- Cabeceras `X-Forwarded-*`: confía en ellas **solo** si vienen del LB.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Chequeo a `/actuator/health/readiness` o equivalente | Chequeo a `/` que hace consultas a la base |
| Drenar antes de detener una réplica | Matar el backend con conexiones vivas |
| Al menos 2 backends por set | Un backend y suponer alta disponibilidad |
| `idle timeout` ajustado a la app | Dejar el valor por defecto con WebSocket |
| Certificados con renovación automática | Certificado subido a mano que vence |
| Registros de acceso en Logging | Operar a ciegas |

## 8. Límites, costos y versiones
- **Costo:** por hora del LB + por Mbps de la forma flexible; hay un LB gratuito de 10 Mbps en la capa siempre gratis *(verifica)*.
- **Límites** (verifica): listeners, backend sets y backends por LB; ancho de banda máximo de la forma.
- **Terraform:** `oci_load_balancer_load_balancer`, `oci_load_balancer_backend_set`, `oci_load_balancer_backend`, `oci_load_balancer_listener`, `oci_load_balancer_rule_set`.
- **SDK:** `LoadBalancerClient` (`oci-java-sdk-loadbalancer`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
