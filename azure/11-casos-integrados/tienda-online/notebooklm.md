# NotebookLM · Azure · Caso integrado · Tienda online

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/` (Terraform de la red privada, esquema SQL, evento JSON, script de verificación y consultas KQL).

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre la arquitectura de una tienda en línea construida con servicios de Azure, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. La analogía de la tienda con vitrina, mostrador, trastienda y archivo; el diagrama completo de Front Door con WAF, API Management, ingreso interno, AKS, Azure SQL, Redis, Service Bus, Blob y Key Vault.
2. El viaje de una compra en diez pasos, marcando cuáles son síncronos y cuáles asíncronos.
3. La tabla de capas: qué servicio resuelve cada necesidad y por qué.
4. El problema de guardar y avisar: las cuatro estrategias, por qué falla cada una y cómo la bandeja de salida lo resuelve; el publicador con FOR UPDATE SKIP LOCKED; la detección de duplicados con MessageId; la bandeja de entrada idempotente; el orden y las sesiones.
5. La red privada: subredes, NSG, Private Endpoint y zonas DNS privadas, y cómo comprobarla desde un pod.
6. Seguridad: la tabla de permisos por plano para cada identidad, las amenazas y sus defensas.
7. Qué hacer y qué NO hacer; costos principales y requisitos como el nivel Premium de Service Bus para Private Endpoint.
8. Los ocho casos reales como historias con su lección y el resumen de patrones.
9. Código Java: transacción, bandejas, servicio de pedidos, publicador, consumidor idempotente, Spring MVC y WebFlux, Quarkus imperativo y reactivo, y cómo se prueba.
10. Troubleshooting por síntoma y la secuencia de diagnóstico.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
