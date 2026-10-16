# NotebookLM · Azure · Workload Identity

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure Workload Identity Federation para pods de AKS y pipelines, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. Qué es, con la analogía del convenio de confianza entre dos edificios.
2. Cómo funciona por dentro, paso a paso: token proyectado del ServiceAccount, intercambio con Entra ID, credencial federada con issuer, subject y audience. Dibuja el flujo.
3. Las piezas: OIDC issuer, webhook de workload identity, ServiceAccount, managed identity y credencial federada.
4. Las variables que recibe el pod y el subject exacto.
5. El mismo mecanismo con GitHub Actions.
6. Cuándo NO usarlo, y por qué aad-pod-identity está obsoleto.
7. Cómo se crea: CLI, YAML de Kubernetes y Terraform con el código de las fuentes.
8. Los 6 casos reales como historias.
9. Código Java: no cambia, DefaultAzureCredential y WorkloadIdentityCredential, con Spring Boot y Quarkus; cómo diagnosticar dentro del pod.
10. Qué hacer, qué NO hacer y la tabla de errores AADSTS.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; cierra con 3 puntos de resumen y 2 preguntas de repaso.
```
