# NotebookLM · Azure · AKS

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure Kubernetes Service (AKS), para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes.

Estructura obligatoria:
1. Qué es, con la analogía de la flota con central de logística; qué administra Azure y qué administras tú.
2. Cómo funciona por dentro: plano de control, node pools system y user, y los objetos de Kubernetes (pod, deployment, service, ingress, configmap, secret, hpa, pdb, networkpolicy, serviceaccount). Dibuja el diagrama.
3. Red: Azure CNI Overlay, CNI con IP de la VNet, Cilium, kubenet heredado; rangos que no deben solaparse; tráfico saliente (loadBalancer, NAT Gateway, UDR); clúster privado.
4. Identidad: Entra ID con Azure RBAC, identidad del clúster y del kubelet, Workload Identity y CSI con Key Vault.
5. Escalado: HPA, KEDA y Cluster Autoscaler como cadena; actualizaciones, canales, drenado y por qué un PDB imposible las bloquea.
6. Almacenamiento (Disk, Files, Blob), seguridad por capas y observabilidad (Container Insights, Managed Prometheus).
7. AKS estándar frente a AKS Automatic y cuándo NO usar AKS.
8. Los 13 casos reales como historias con su lección.
9. Código Java en Kubernetes: la JVM dentro del contenedor (memoria, GC, CPU), tres sondas, apagado ordenado, hablar con otros servicios por DNS y timeouts, hilos virtuales, imperativo vs reactivo en Spring y Quarkus, métricas y CronJob.
10. Ejemplos de CLI, Terraform y los siete manifiestos YAML; Dockerfiles.
11. Qué hacer, qué NO hacer, límites y costos, y la tabla de troubleshooting con el método de afuera hacia adentro.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
