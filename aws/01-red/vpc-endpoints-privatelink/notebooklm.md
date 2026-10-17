# NotebookLM · AWS · VPC Endpoints, PrivateLink y Route 53

**Fuentes a subir:** los `.md` de esta carpeta y `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre VPC Endpoints, AWS PrivateLink y Route 53 privado, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. La analogía del pasillo interno al banco y los tres caminos: NAT, gateway, interfaz.
2. Tipos de endpoint: gateway (S3 y DynamoDB, gratis), interfaz (ENI por AZ, DNS privado), balanceador de puerta de enlace; paso a paso de un endpoint de interfaz.
3. PrivateLink para publicar un servicio propio (NLB + endpoint service) y cuándo usarlo en lugar de peering.
4. Route 53: zonas privadas, Resolver entrante y saliente.
5. Cuándo sirve y cuándo no (costos por hora y por AZ frente al NAT).
6. Seguridad: política de endpoint, aws:SourceVpce, aprobación de conexiones.
7. Qué hacer y qué no; límites.
8. Los seis casos reales como historias con su lección.
9. Java: DNS privado y comprobación de IP privada, endpointOverride solo si hace falta, SDK síncrono y asíncrono, Spring MVC y WebFlux, Quarkus imperativo y Mutiny.
10. Troubleshooting por síntoma.

Reglas: no omitas tablas, comandos ni casos; define cada término al usarlo; usa ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
