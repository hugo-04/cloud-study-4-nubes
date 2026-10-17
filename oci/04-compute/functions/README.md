# Oracle OCI · Compute · Functions (código bajo demanda)

Escribes una función, la subes como imagen de contenedor y OCI la ejecuta cuando algo la invoca: un evento, una llamada HTTP, un mensaje. No hay servidores que administrar y pagas por ejecución.

## 1. Qué es

**Analogía:** un empleado por horas. No pagas el sueldo completo: lo llamas cuando llega un trabajo, lo hace y se va. La primera vez del día tarda un poco en llegar (arranque en frío).

```
 Evento / API Gateway / SDK ──► OCI Functions ──► contenedor de TU función (se crea si no hay)
                                      │
                       identidad: resource principal ──► Object Storage, Queue, Vault…
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Aplicación** | Agrupa funciones; define subredes, configuración y registros |
| **Función** | Imagen en OCIR + memoria (128–1024 MB aprox.) + tiempo máximo (hasta ~300 s) *(verifica)* |
| **Fn Project** | Marco de código abierto en el que se basa; CLI `fn` |
| **FDK** | Kit de desarrollo (Java, Python, Node…) que lee la entrada y escribe la salida |
| **Invocación** | `Sync` (esperas respuesta) o `Detached` (asíncrona, sin respuesta) |
| **Concurrencia aprovisionada** | Instancias calientes reservadas para evitar arranques en frío |
| **Resource principal** | La función obtiene credenciales de OCI sin llaves |
| **Configuración** | Pares clave/valor a nivel de aplicación o función |

### Ciclo de una invocación
1. Llega la petición (por el endpoint de invocación de **esa** función).
2. Si no hay contenedor caliente, se arranca uno (*arranque en frío*).
3. Tu manejador procesa y responde; el contenedor se conserva un tiempo para reutilizarlo.

### Quién la dispara
- **Events** (por ejemplo, objeto creado en un bucket), **API Gateway**, **Notifications**, **Service Connector** (colas, streaming), el **SDK**.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Procesar un archivo recién subido | Función disparada por un evento |
| Tarea corta y esporádica (< 5 min) | Función |
| API con tráfico constante y baja latencia estricta | [OKE](../oke/README.md) o VM |
| Trabajo de horas | [Container Instances](../container-instances/README.md) |
| Requiere estado local persistente | **No** |
| Cadena de 10 funciones que se llaman entre sí | **No**: coreografía con mensajería |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Arranque en frío** | Demora de la primera invocación |
| **Sync / Detached** | Esperar respuesta / disparar y olvidar |
| **Idempotencia** | Repetir la invocación no duplica el efecto |
| **Resource principal** | La función se identifica sola |
| **Memoria** | También define la CPU disponible |

## 5. Cómo se usa
1. Crea aplicación y función: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf) y [`ejemplos/fn/func.yaml`](ejemplos/fn/func.yaml).
2. Da permisos con grupo dinámico (`resource.type = 'fnfunc'`).
3. Invoca con reintentos desde [Java](uso-en-java.md).
4. CLI: [`ejemplos/cli/funciones.sh`](ejemplos/cli/funciones.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Desarrolladores | `manage functions-family` en dev, `read` en prod | — |
| Quien invoca | — | `use fn-invocation` sobre esa función |
| La función | — | Resource principal con política mínima |

- Aplicación en **subred privada**; salida por NAT/puerta de servicios.
- Secretos de [Vault](../../03-secretos/README.md), no en la configuración.
- Entradas externas: valida y limita tamaño.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Funciones pequeñas y de un solo propósito | Monolitos dentro de una función |
| Idempotencia (los eventos se repiten) | Suponer «exactamente una vez» |
| Tiempo máximo ajustado | Tiempo máximo siempre al tope |
| Concurrencia aprovisionada si la latencia importa | Ignorar el arranque en frío |
| Registros estructurados sin datos personales | Registrar cuerpos completos |
| Reintentos con *backoff* en el cliente | Reintentos inmediatos en bucle |

## 8. Límites, costos y versiones
- **Costo:** por invocación y por GB-segundo; cuota gratuita mensual *(verifica)*; concurrencia aprovisionada cuesta aparte.
- **Límites** (verifica): tamaño de la carga, tiempo máximo, memoria, concurrencia.
- **Terraform:** `oci_functions_application`, `oci_functions_function`.
- **SDK:** `FunctionsManagementClient`, `FunctionsInvokeClient` (`oci-java-sdk-functions`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
