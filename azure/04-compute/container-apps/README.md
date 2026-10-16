# Azure · Compute · Container Apps

## 1. Qué es

**Azure Container Apps (ACA) ejecuta tus contenedores sin que administres Kubernetes.** Le das una imagen, le dices el puerto y cuánto escalar; la plataforma pone los nodos, el balanceador, el HTTPS, el escalado (incluso **a cero**) y las revisiones. Por debajo usa Kubernetes, KEDA, Envoy y Dapr, pero no los ves ni los operas.

Analogía: un **servicio de mensajería que lleva tu propio camión**. Traes tu carga empaquetada (el contenedor); ellos manejan, ponen la gasolina y envían más camiones cuando hace falta. No eres dueño de la flota (AKS), tampoco alquilas un asiento fijo (App Service).

| Tú aportas | La plataforma aporta |
|---|---|
| Imagen de contenedor, variables, reglas de escala, identidad | Nodos, parches, balanceo, certificados, escalado por eventos, revisiones, logs |

---

## 2. Cómo funciona por dentro

```
 Internet ──► Ingress (Envoy, HTTPS, dominio propio)
                 │
   ┌─────────────┴────────── ENTORNO (Container Apps environment) ─────────────┐
   │   red compartida · logs compartidos · DNS interno · (VNet opcional)        │
   │                                                                            │
   │   Container App "api"            Container App "worker"      Job "reporte" │
   │   ├ Revisión api--v1 (90 %)      ├ Revisión worker--v3       (cron/evento) │
   │   │   réplica 1 ─ contenedor     │   réplica 0..20 (KEDA)                  │
   │   │   réplica 2   + sidecar Dapr │                                         │
   │   └ Revisión api--v2 (10 %)      └ ...                                     │
   └────────────────────────────────────────────────────────────────────────────┘
```

### 2.1 Las piezas

| Pieza | Qué es | Detalle importante |
|---|---|---|
| **Environment** (entorno) | Frontera de red y de logs donde viven varias apps | Una VNet por entorno; las apps se ven entre sí por nombre; un workspace de Log Analytics |
| **Container App** | Tu servicio (uno o varios contenedores en la misma "plantilla") | Tiene ingress, escalado, identidad, secretos |
| **Revisión (revision)** | Foto **inmutable** de la plantilla de la app | Cada cambio en la plantilla crea una nueva; permite *blue/green* y reversión |
| **Réplica** | Una copia en ejecución (un pod) | 0 a N según las reglas de escala |
| **Job** | Tarea que termina: manual, programada o por evento | Para batch y reportes |
| **Perfil de carga (workload profile)** | Tipo de cómputo: *Consumption* (serverless) o *Dedicated* (D4, D8, E4, GPU…) | Se pueden mezclar en un entorno |
| **Dapr** | Sidecar opcional para invocar servicios, pub/sub, estado, secretos | Quita código de infraestructura de tu microservicio |

### 2.2 Revisiones: despliegue sin caída y reversión

| Modo | Comportamiento |
|---|---|
| **Single** (por defecto) | Solo hay una revisión activa; al desplegar, la nueva reemplaza a la anterior cuando está lista |
| **Multiple** | Varias revisiones activas a la vez; **tú repartes el tráfico** (90/10, azul/verde) y desactivas las viejas |

```
api--v1 (100 %) ──► despliegas v2 ──► api--v1 (90 %) + api--v2 (10 %) ──► v2 (100 %) ──► desactivas v1
                                                                         └─ ¿falla? vuelves a v1 en segundos
```
**Etiquetas (labels)** dan una URL estable a una revisión (`api---green.<dominio>`) para probarla antes de enviarle tráfico.

### 2.3 Escalado (sin que tú administres nodos)
Cada app define `minReplicas` y `maxReplicas` y una o más **reglas**:

| Regla | Escala según | Ejemplo |
|---|---|---|
| **HTTP** | Peticiones concurrentes por réplica | 50 concurrentes → otra réplica |
| **TCP** | Conexiones concurrentes | Servicios no HTTP |
| **Personalizada (KEDA)** | Cola de Service Bus, retraso de Kafka/Event Hubs, cron, etc. | 1 réplica por cada 20 mensajes |
| **CPU / memoria** | Uso de recursos | Cargas intensivas |

- **Escala a cero:** con `minReplicas = 0` no hay réplicas ni costo de cómputo (solo el primer request espera el *arranque en frío*).
- **Siempre una réplica:** `minReplicas = 1` para servicios con usuarios que no toleran espera.
- Se evalúa la regla que pida **más** réplicas.

### 2.4 Ingress (entrada)
| Opción | Qué hace |
|---|---|
| `external` / `internal` | Visible desde Internet o solo dentro de la VNet/entorno |
| `targetPort` | Puerto de tu contenedor |
| `transport` | `http`, `http2`, `tcp` |
| Dominio propio y certificado | Propio o administrado |
| Restricciones por IP, CORS, afinidad de sesión, certificado de cliente (mTLS) | Se configuran en el ingress |

Entre apps del mismo entorno, se llaman por nombre: `http://api-pedidos` (dentro del entorno) o por su FQDN interno.

### 2.5 Red
| Modelo | Descripción |
|---|---|
| **Entorno por defecto** | Subred gestionada por la plataforma; ingress público |
| **Entorno en tu VNet** | Eliges una subred **delegada** a `Microsoft.App/environments`; puedes hacerlo **interno** (solo IP privada) y poner Application Gateway/Front Door/APIM delante |
| **Salida (egress)** | Por defecto IP pública compartida; con VNet y *workload profiles* puedes usar NAT Gateway o UDR a un firewall |

El tamaño mínimo de la subred depende del tipo de entorno (workload profiles necesita menos que Consumption-only): *verifica el valor vigente*. Para recursos privados (bases de datos, Key Vault), mismas reglas de DNS privado de siempre ([Private Endpoint y DNS](../../01-red/private-endpoint-dns/README.md)).

### 2.6 Identidad y secretos
- **Managed Identity** (system o user-assigned) para hablar con Azure sin secretos ([Managed Identity](../../02-iam/managed-identity/README.md)). También sirve para **descargar imágenes de ACR** y para que las **reglas de KEDA** consulten Service Bus sin cadenas.
- **Secretos de la app:** valores guardados en la app o, mejor, **referencias a Key Vault** (`keyVaultUrl` + identidad); se exponen al contenedor como variable de entorno (`secretref`) o volumen.
- La variable `AZURE_CLIENT_ID` identifica la identidad a usar cuando hay varias.

### 2.7 Sondas, recursos y apagado
- **Probes:** *startup*, *readiness* y *liveness* (HTTP o TCP) en la plantilla del contenedor.
- **Recursos por contenedor:** combinaciones fijas de CPU/memoria en Consumption (por ejemplo 0.5 vCPU/1 GiB, 1/2, 2/4, 4/8). *Verifica las combinaciones y topes vigentes.*
- **Apagado:** la plataforma envía `SIGTERM` y espera `terminationGracePeriodSeconds` (por defecto 30 s, ajustable hasta 600 s) antes de `SIGKILL`.

### 2.8 Jobs
| Disparador | Para qué |
|---|---|
| **Manual** | Migraciones, tareas bajo demanda |
| **Programado (cron)** | Reportes nocturnos, limpiezas |
| **Por eventos** | Procesar un mensaje de una cola y terminar |

Parámetros: `replicaTimeout`, `replicaRetryLimit`, `parallelism`, `replicaCompletionCount`. El proceso debe **terminar con código 0** si salió bien.

### 2.9 Dapr (opcional)
Un sidecar en `localhost:3500` ofrece APIs estándar: **invocar servicios** (con reintentos y mTLS), **pub/sub** (sobre Service Bus, Event Hubs, Kafka…), **estado**, **bindings** y **secretos**. Tu código habla HTTP/gRPC con el sidecar y el *componente* (YAML) define el backend real. Ventaja: cambias Service Bus por Kafka sin tocar el código. Costo: un componente más que entender y operar.

### 2.10 Observabilidad
- Logs de consola y de sistema en Log Analytics (`ContainerAppConsoleLogs_CL`, `ContainerAppSystemLogs_CL`).
- `az containerapp logs show` y `az containerapp exec` para depurar.
- Métricas de réplicas, peticiones, CPU, memoria y *restarts*.
- OpenTelemetry/Application Insights desde tu aplicación.

### 2.11 Funcionalidades para Java
La plataforma ofrece **componentes de Java administrados** (por ejemplo Eureka Server, Config Server, Spring Boot Admin) y métricas/diagnóstico de JVM en el portal. *Verifica cuáles están disponibles y su estado (GA/preview).*

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- Microservicios en contenedores que no necesitan la API de Kubernetes.
- APIs con tráfico irregular que deben **escalar a cero** de noche.
- Workers que escalan por **cola** (Service Bus, Kafka, Event Hubs).
- Jobs programados o por evento.
- Equipos pequeños que quieren contenedores sin operar clústeres.

| NO lo uses si | Alternativa |
|---|---|
| Necesitas CRDs, operadores, mallas completas, `kubectl`, DaemonSets | [AKS](../aks/README.md) |
| Una sola web simple sin contenedor | [App Service](../app-service/README.md) |
| Eventos muy cortos con *bindings* declarativos | [Function Apps](../function-apps/README.md) |
| Necesitas control de nodos (kernel, drivers a medida) | AKS o máquinas virtuales |
| Estado local persistente complejo | AKS con StatefulSets |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Environment** | Frontera donde viven varias apps | `cae-modalima` |
| **Revision** | Versión inmutable de la app | `api-pedidos--v2` |
| **Replica** | Una copia en ejecución | 0 a 20 |
| **Scale rule** | Regla que decide cuántas réplicas | HTTP 50 concurrentes |
| **Scale to zero** | Sin réplicas cuando no hay carga | Workers nocturnos |
| **Ingress** | Puerta de entrada | `external`, puerto 8080 |
| **Workload profile** | Tipo de cómputo | Consumption, D4 |
| **Label** | URL estable de una revisión | `api---green` |
| **Dapr** | Sidecar de microservicios | pub/sub sobre Service Bus |
| **Job** | Tarea que termina | Reporte a las 07:00 |
| **secretref** | Variable que apunta a un secreto | `DB_PASSWORD=secretref:db-password` |

---

## 5. Cómo se usa

### 5.1 Del contenedor a la URL (CLI)
```bash
az containerapp env create -g rg-estudio-compute -n cae-modalima -l eastus2
az containerapp create -g rg-estudio-compute -n api-pedidos --environment cae-modalima \
  --image acrmodalima.azurecr.io/api-pedidos:1.4.0 --target-port 8080 --ingress external \
  --min-replicas 1 --max-replicas 10 --cpu 0.5 --memory 1.0Gi
az containerapp show -g rg-estudio-compute -n api-pedidos --query properties.configuration.ingress.fqdn -o tsv
```
Guion completo (VNet, identidad, ACR sin contraseña, secretos de Key Vault, reglas KEDA, Dapr, revisiones y jobs): [ejemplos/cli/container-apps.sh](ejemplos/cli/container-apps.sh). Terraform: [ejemplos/terraform/main.tf](ejemplos/terraform/main.tf). Especificación YAML completa con sondas: [ejemplos/yaml/containerapp.yaml](ejemplos/yaml/containerapp.yaml).

### 5.2 Despliegue con revisiones (azul/verde)
1. `az containerapp revision set-mode --mode multiple`.
2. Despliega con `--revision-suffix v2` (sin tráfico).
3. Prueba la etiqueta `green` de la nueva revisión.
4. Reparte: `az containerapp ingress traffic set --revision-weight api--v1=90 api--v2=10`.
5. Sube a 100 % y **desactiva** la revisión vieja.
6. Si falla: devuelve el tráfico a `v1`.

### 5.3 Cómo comprobar que quedó bien
```bash
az containerapp revision list -g <rg> -n <app> -o table
az containerapp logs show -g <rg> -n <app> --follow
az containerapp replica list -g <rg> -n <app> -o table
az containerapp exec -g <rg> -n <app> --command sh
```

---

## 6. Seguridad

| Tema | Qué hacer |
|---|---|
| **Imágenes** | De ACR con identidad (`AcrPull`), sin usuario administrador; por *digest* o etiqueta inmutable |
| **Identidad** | User-assigned por servicio; roles de datos mínimos |
| **Secretos** | Referencias a Key Vault; nunca en la imagen ni en variables sin proteger |
| **Entrada** | Ingress `internal` + Application Gateway/Front Door con WAF si es pública; restricciones por IP; mTLS si aplica |
| **Autenticación** | Autenticación integrada (Entra ID) o validación de JWT en tu aplicación |
| **Red** | Entorno en VNet, subred delegada, DNS privado; salida controlada con NAT Gateway/UDR |
| **Contenedor** | No root, sin privilegios; límites de recursos |
| **Dapr** | Habilita mTLS entre sidecars; componentes con identidad, sin cadenas |

### IAM de este servicio

| Quién | Qué hace | Rol mínimo |
|---|---|---|
| Pipeline | Desplegar revisiones | *Container Apps Contributor* (o *Contributor*) sobre la app |
| La app | Descargar imágenes | *AcrPull* a su identidad |
| La app | Leer secretos / datos | Roles de datos específicos |
| Operador | Ver logs | *Monitoring Reader* / acceso a Log Analytics |

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- `minReplicas = 1` en servicios con usuarios; `0` en workers y entornos de desarrollo.
- Sondas de salud siempre; `terminationGracePeriodSeconds` acorde con tu apagado.
- Un entorno por dominio de aislamiento (producción vs no producción).
- Identidades user-assigned y referencias a Key Vault.
- Modo de revisión **multiple** para producción, y desactivar revisiones antiguas.
- Reglas de escala con topes (`maxReplicas`) para controlar el costo y proteger la base de datos.
- Revisar `MaxRAMPercentage` y el tamaño de CPU/memoria para la JVM.

**Qué NO hacer**
- Mezclar producción y pruebas en el mismo entorno.
- Dejar revisiones viejas activas y olvidadas (consumen y confunden).
- Guardar estado en el disco de la réplica.
- Escalar a cero un servicio con JVM pesada de cara al usuario sin medir el arranque en frío.
- Suponer que la IP de salida es fija sin NAT Gateway.
- Usar Dapr "porque sí": añade piezas; úsalo cuando resuelve un problema real.
- Poner una subred demasiado pequeña al crear el entorno (no se puede ampliar sin recrear).

---

## 8. Límites, costos y versiones
- **Consumption:** pagas por vCPU-segundo, GiB-segundo y peticiones, con una cuota gratuita mensual; las réplicas *inactivas* a veces tienen tarifa reducida. **Dedicated:** pagas la capacidad del perfil. *Verifica precios.*
- Máximo de réplicas, tamaño de CPU/memoria por réplica y número de apps por entorno tienen límites: *verifica "Container Apps quotas"*.
- El tamaño de la subred y el tipo de entorno se eligen **al crear**.
- Los nombres de flags (`--scale-rule-identity`, perfiles de carga) evolucionan: confirma con `az containerapp create --help`.

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
