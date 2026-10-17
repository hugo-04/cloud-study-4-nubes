# Google Cloud · Compute · Cloud Run

Corre **contenedores** sin administrar servidores: le das una imagen, Cloud Run la escala de 0 a N instancias según las peticiones, te da una URL HTTPS y cobra por el tiempo que atiendes. Tiene **servicios** (HTTP/gRPC/WebSocket), **jobs** (tareas que terminan) y **worker pools** *(verifica)*.

## 1. Qué es

**Analogía:** un servicio de taxis por aplicación. No compras autos ni contratas choferes: pides un viaje (petición), llega un auto (instancia), y si hay mucha demanda aparecen más; de madrugada no hay ninguno esperando (escala a cero), salvo que pagues por tener uno listo (instancias mínimas).

```
 Cliente ─► https://pedidos-xyz.a.run.app (o balanceador + dominio propio)
            Servicio "pedidos" (región southamerica-west1)
              ├─ revisión 00014 (90 % del tráfico) ── instancias 1..50, concurrencia 80, 1 vCPU / 1 GiB
              └─ revisión 00015 (10 %, canario)
            Identidad: SA pedidos@ · Salida a la VPC: Direct VPC egress · Ingress: interno + balanceador
 Job "reporte-ventas" ── tareas en paralelo ── termina y libera todo
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Servicio** | URL estable; enruta tráfico a revisiones |
| **Revisión** | Versión inmutable (imagen + configuración); cada despliegue crea una |
| **Instancia** | Contenedor que atiende; escala por peticiones/CPU |
| **Concurrencia** | Peticiones simultáneas por instancia (por defecto 80 *(verifica)*) |
| **Mínimo / máximo de instancias** | Evita arranques en frío / limita costo y conexiones a la base |
| **Facturación de CPU** | Solo durante peticiones (por defecto) o siempre asignada |
| **Ingress** | `all`, `internal`, `internal-and-cloud-load-balancing` |
| **Autenticación** | Pública (`allUsers` invoker) o privada con ID token |
| **Salida a la VPC** | Direct VPC egress o conector de acceso a VPC |
| **Jobs** | Tareas con reintentos y paralelismo; se ejecutan por programador o manualmente |
| **Secretos** | Montados como variable o volumen desde Secret Manager |

### Ciclo de una petición
1. Llega la petición; si hay instancia libre (por concurrencia), la atiende.
2. Si no, arranca una (*arranque en frío*): descargar imagen, iniciar JVM, `readiness`.
3. Al terminar, la instancia queda ociosa y Cloud Run puede apagarla.
4. Con «CPU solo durante peticiones», el trabajo en segundo plano fuera de una petición se congela.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| API REST/gRPC sin estado | **Cloud Run** |
| Consumidor de Pub/Sub *push* | Cloud Run (endpoint HTTP) |
| Lote de 30 minutos | **Cloud Run jobs** |
| Muchos microservicios con malla y políticas complejas | [GKE](../gke/README.md) |
| Estado local, disco persistente | **No** |
| Necesita el SO o GPU especial | [Compute Engine](../compute-engine/README.md) *(GPU en Cloud Run: verifica)* |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Escala a cero** | Sin tráfico, sin instancias ni costo de cómputo |
| **Arranque en frío** | Primera petición lenta de una instancia nueva |
| **Revisión** | Foto inmutable de un despliegue |
| **División de tráfico** | Repartir entre revisiones (canario) |
| **ID token** | Credencial para llamar a un servicio privado |

## 5. Cómo se usa
1. Servicio privado con cuenta propia, secretos montados, VPC egress, mínimo de instancias y canario: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Llamada servicio-a-servicio con ID token, *deadline* y reintentos solo seguros desde [Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/run.sh`](ejemplos/cli/run.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Pipeline | `roles/run.developer` + `iam.serviceAccountUser` sobre la SA del servicio | — |
| Llamadores | — | `roles/run.invoker` sobre ese servicio |
| El servicio | SA propia con roles mínimos | — |

- Privado por defecto; público solo detrás de un balanceador con Cloud Armor si es web.
- Ingress `internal-and-cloud-load-balancing` para servicios internos.
- Imágenes de Artifact Registry con análisis de vulnerabilidades.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Máximo de instancias acorde a la base | Escalar a 1.000 y agotar conexiones |
| Mínimo de instancias en lo sensible a latencia | Ignorar el arranque en frío de la JVM |
| Canario con división de tráfico | Pasar 100 % de golpe |
| Secretos montados desde Secret Manager | Contraseñas en variables planas |
| Trabajo en segundo plano en jobs o con CPU siempre asignada | Hilos de fondo con CPU solo en peticiones |

## 8. Límites, costos y versiones
- **Costo:** vCPU-segundo, GiB-segundo y peticiones; nivel gratuito mensual; instancias mínimas cobran en reposo *(verifica)*.
- **Límites** (verifica): tiempo máximo de petición (hasta 60 min), memoria y CPU por instancia, concurrencia máxima.
- **Terraform:** `google_cloud_run_v2_service`, `google_cloud_run_v2_job`, `google_cloud_run_v2_service_iam_member`.
- **Java:** `ServicesClient` (`google-cloud-run`) para gestión; `IdTokenCredentials` (`google-auth-library`) para llamar.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
