# Oracle OCI · 04 Compute

¿Dónde corre mi código? OCI ofrece cuatro respuestas, de más control a menos administración.

| Unidad | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Instancias (VM)](compute-instancias/README.md) | ¿Necesito una máquina completa? | Un departamento alquilado sin amoblar | Sistemas heredados, agentes, GPU, control del SO |
| [OKE](oke/README.md) | ¿Tengo muchos microservicios con réplicas? | Un edificio con administrador | Plataforma de microservicios, despliegues graduales |
| [Functions](functions/README.md) | ¿Es un trabajo corto disparado por un evento? | Un empleado por horas | Reacciones a eventos, tareas < 5 min |
| [Container Instances](container-instances/README.md) | ¿Solo quiero correr un contenedor, sin clúster? | Un *food truck* alquilado | Lotes largos, herramientas internas |

## Árbol de decisión: «quiero…»

```
¿Necesito controlar el sistema operativo, GPU o un agente instalado?
   └─ VM (forma flexible, imagen endurecida, grupo de instancias)

¿Tengo 5+ microservicios con réplicas, escalado y despliegues graduales?
   └─ OKE (nodos virtuales o administrados, workload identity)

¿Es una reacción corta (< 5 min) a un evento o una llamada esporádica?
   └─ Functions (idempotente, concurrencia aprovisionada si hay latencia)

¿Es un contenedor que corre minutos u horas y luego termina?
   └─ Container Instances (política NEVER, opcRetryToken)

¿Es una API pequeña siempre encendida sin necesidad de Kubernetes?
   └─ Container Instances detrás de un balanceador (o VM)
```

## Comparativa

| Característica | VM | OKE | Functions | Container Instances |
|---|---|---|---|---|
| **Qué administras** | SO, parches, runtime | Manifiestos (y nodos si son administrados) | Solo el código | Imagen y forma |
| **Unidad de despliegue** | Imagen de disco | Pod | Imagen de función | Contenedor(es) |
| **Escalado** | Grupo de instancias | HPA / autoscaler | Automático por invocación | Manual (más instancias) |
| **Duración típica** | Indefinida | Indefinida | Segundos | Minutos a horas |
| **Cobro** | OCPU/GB-hora | Nodos (+ clúster *enhanced*) | Invocación + GB-s | OCPU/GB-hora mientras corre |
| **Identidad** | Instance principal | Workload identity | Resource principal | Resource principal |
| **Error típico** | Llaves en el disco | Un solo grupo dinámico para todo | Funciones no idempotentes | `latest` y secretos en variables |

## La receta ModaLima
| Necesidad | Pieza | Por qué |
|---|---|---|
| Catálogo, carrito, pedidos, pagos | OKE con workload identity | Muchos servicios, réplicas y despliegues graduales |
| Miniaturas al subir fotos | Functions disparada por evento | Corto, esporádico, idempotente |
| Reporte de ventas nocturno | Container Instances (`NEVER`) | 40 minutos y termina |
| ERP heredado con agente propietario | VM en subred privada | Necesita el SO |

## Orden recomendado de adopción
1. Imágenes inmutables en OCIR y etiquetas fijas.
2. Identidad sin llaves: instance/resource principal o workload identity.
3. Empieza por el servicio más simple que resuelva el caso (Functions o Container Instances).
4. OKE cuando haya varios microservicios con necesidades de plataforma.
5. VM solo cuando algo exige el sistema operativo.
6. Todo en subredes privadas, como código y con etiquetas de costo.

## Reglas transversales
- Nada de llaves de API en imágenes ni discos.
- Secretos desde Vault al arrancar, nunca en variables de entorno ni configuración visible.
- Idempotencia ante reintentos (`opcRetryToken`, nombres deterministas).
- Apagado ordenado: maneja `SIGTERM`.
- Etiquetas `proyecto` y `entorno` en todo.

## Java en compute: qué construye cada `uso-en-java.md`
| Unidad | Qué construyes | Patrón común |
|---|---|---|
| VM | Planificador de encendido/apagado por horario con `ComputeClient` | Núcleo puro + adaptador del SDK |
| OKE | Auditor de versiones del clúster y node pools con `ContainerEngineClient` | Lógica pura probada sin red |
| Functions | Manejador FDK puro + cliente con reintentos y *jitter* | Reintentos solo ante fallas transitorias |
| Container Instances | Validador de tareas + `createContainerInstance` con `opcRetryToken` | Validar antes de gastar; idempotencia |

## Cómo se relaciona con otros capítulos
- [Red](../01-red/README.md): subredes privadas, NSG, NAT y puerta de servicios.
- [IAM](../02-iam/README.md): grupos dinámicos y workload identity.
- [Secretos](../03-secretos/README.md): lo que leen al arrancar.
- [Ingress y API](../05-ingress-api/README.md): cómo llega el tráfico.
- [Mensajería](../07-mensajeria/README.md): eventos y colas que disparan trabajo.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos, troubleshooting, repaso y prompt de NotebookLM.
