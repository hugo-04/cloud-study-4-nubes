# Azure · 04 Compute

Dónde corre tu código. Regla: **elige el nivel más administrado que cubra tu necesidad**; cada paso hacia abajo da control pero también trabajo.

| Opción | Analogía | Elígela cuando |
|---|---|---|
| [App Service](app-service/README.md) | Bus con ruta fija | Una o pocas APIs/webs HTTP con tráfico estable, slots y cero Kubernetes |
| [Function Apps](function-apps/README.md) | Taxi por viaje | Código corto disparado por eventos, timers, orquestaciones |
| [Container Apps](container-apps/README.md) | Mensajería con tu camión | Contenedores, escala a cero, workers por cola, sin operar Kubernetes |
| [AKS](aks/README.md) | Flota propia con central | Muchos servicios, control fino, operadores, mallas, equipo de plataforma |
| Máquina virtual | Auto alquilado | Software que no se puede contenerizar |

## Árbol de decisión
```
¿Es código corto disparado por un evento?              → Function Apps
¿Es una web/API única o pocas, sin contenedores?        → App Service
¿Tienes contenedores y quieres escalar a cero / colas?  → Container Apps
¿Necesitas la API de Kubernetes, operadores, mallas?    → AKS
```

## Cuadro comparativo

| | App Service | Function Apps | Container Apps | AKS |
|---|---|---|---|---|
| Unidad de despliegue | JAR/WAR o imagen | Paquete de funciones | Imagen | Imagen + manifiestos |
| Escala a cero | No | Sí (Flex/Consumption) | Sí | Con KEDA (los nodos no) |
| Escala por eventos | Limitado | Nativo | KEDA integrado | KEDA (add-on) |
| Revisiones/azul-verde | Slots | Slots (según plan) | Revisiones | Estrategias de Kubernetes |
| Control de red/nodos | Bajo | Bajo | Medio | Total |
| Curva de aprendizaje | Baja | Media | Media | Alta |
| Modelo de costo | Plan por hora | Por ejecución / instancias | Por uso de vCPU/GiB | Nodos por hora |

Cada carpeta trae: teoría, casos reales, uso desde Java, ejemplos (CLI, Terraform, YAML, Java), troubleshooting, repaso y prompt de NotebookLM.
