# NotebookLM · Azure · Front Door

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure Front Door con WAF, para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes.

Estructura obligatoria:
1. Qué es, con la analogía de recepciones en aeropuertos de todo el mundo; global, anycast, borde de Microsoft.
2. Cómo funciona por dentro: POP, TLS en el borde, WAF, caché, red troncal, origen. Dibuja el diagrama.
3. Jerarquía de objetos: perfil, endpoint, dominio personalizado, grupo de orígenes, origen, ruta, conjunto de reglas, política de seguridad.
4. Balanceo y failover: sondas de salud, prioridad, latencia adicional y peso.
5. Caché y compresión: qué cachear, TTL, purga y por qué no cachear APIs dinámicas.
6. Conjuntos de reglas: redirecciones, reescrituras, cabeceras de seguridad.
7. Cabeceras: X-Azure-FDID, X-Azure-Ref, X-Forwarded-For, X-Azure-ClientIP.
8. Cómo cerrar el origen: etiqueta AzureFrontDoor.Backend + FDID, y Private Link en Premium.
9. WAF: Standard vs Premium, Detection vs Prevention, límite de tasa, filtro geográfico, bots.
10. Los 10 casos reales como historias con su lección.
11. Código Java: validar X-Azure-FDID, registrar X-Azure-Ref, IP del cliente, Cache-Control y ETag, endpoint de sonda ligero, imperativo (Spring MVC, Quarkus) y reactivo (WebFlux).
12. Terraform, CLI y KQL; cuándo NO usar Front Door, qué hacer, qué NO hacer, costos y la tabla de troubleshooting.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
