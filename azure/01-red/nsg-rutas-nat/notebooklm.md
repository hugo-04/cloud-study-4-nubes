# NotebookLM · Azure · NSG, Rutas y NAT

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure NSG, Route Tables (UDR) y NAT Gateway, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. Qué son las tres piezas, con la analogía del guardia, las señales y la puerta de salida.
2. NSG por dentro: campos de una regla, prioridades, estado, reglas por defecto una por una, y POR QUÉ hace falta un Deny aunque exista un Allow. Muestra el orden de evaluación entre NSG de subnet y de NIC.
3. Service tags y ASG con ejemplos.
4. Rutas: del sistema y UDR, tipos de siguiente salto, prefijo más largo, el patrón 0.0.0.0/0 hacia un firewall y el ruteo asimétrico.
5. NAT Gateway: SNAT, puertos, idle timeout, IP estática.
6. Cómo se crea: CLI y Terraform, con el código de las fuentes.
7. IAM y políticas recomendadas.
8. Los 5 casos reales contados como historias.
9. Impacto en Java: pools de conexiones, timeouts, idle, reintentos, en Spring Boot y Quarkus, imperativo y reactivo.
10. Qué hacer, qué NO hacer y troubleshooting con los comandos de Network Watcher.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; cierra con 3 puntos de resumen y 2 preguntas de repaso.
```
