# NotebookLM · Azure · Ingress en AKS

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre cómo entra el tráfico a un clúster de Azure Kubernetes Service (Ingress y Gateway API), para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes.

Estructura obligatoria:
1. Qué es un ingress, con la analogía del recepcionista de un edificio; por qué no un balanceador por servicio.
2. Cómo funciona por dentro: DNS, IP del controlador, Service LoadBalancer, controlador, Service, pods. Dibuja el diagrama.
3. Ingress vs Gateway API: objetos, roles y por qué Gateway API es el futuro.
4. Opciones de controlador en Azure: add-on de application routing, Application Gateway for Containers, AGIC, malla Istio, terceros; y la situación del NGINX de la comunidad.
5. Entrada pública vs interna y anotaciones del balanceador de Azure.
6. TLS: cert-manager con Let's Encrypt, certificados en Key Vault, terminación en un balanceador externo.
7. Qué ve la aplicación Java: cabeceras X-Forwarded-*, enlaces correctos, IP real del cliente y su confianza.
8. Tiempos y tamaños: inactividad del balanceador, timeouts del proxy, límite de cuerpo; SSE y WebSocket con latido.
9. Apagado sin errores: readiness, preStop, graceful shutdown.
10. Los 9 casos reales como historias con su lección.
11. Código Java (Spring MVC, WebFlux, Quarkus con Mutiny), YAML de Ingress y Gateway API, CLI y Terraform.
12. Cuándo NO usar un ingress, qué hacer, qué NO hacer, costos y la tabla de troubleshooting con la escalera de diagnóstico.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
