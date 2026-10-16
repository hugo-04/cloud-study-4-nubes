# NotebookLM · Azure · Peering y Hub-and-Spoke

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure VNet Peering y la arquitectura hub-and-spoke, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. Qué es el peering, con la analogía del puente entre edificios, y qué es hub-and-spoke (dibuja el diagrama).
2. Reglas del peering: dos sentidos, estados, no transitivo, sin solapes, global peering.
3. Las opciones de cada sentido (virtual network access, forwarded traffic, gateway transit, remote gateways) explicadas una por una con ejemplos.
4. Cómo comunicar dos spokes por el firewall del hub con Route Tables, y el ruteo asimétrico.
5. Alternativas: Virtual WAN, VPN VNet-to-VNet, Private Link.
6. Cómo se crea: CLI y Terraform, con el código de las fuentes.
7. IAM, políticas y firewall central.
8. Los 5 casos reales como historias.
9. Impacto en Java: nombres DNS, timeouts entre regiones, circuit breaker, logs que ayudan al equipo de red, en Spring Boot y Quarkus.
10. Qué hacer, qué NO hacer y troubleshooting.

Reglas: no omitas tablas, comandos ni casos; define cada término; cierra con 3 puntos de resumen y 2 preguntas de repaso.
```
