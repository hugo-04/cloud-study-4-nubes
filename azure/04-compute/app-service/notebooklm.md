# NotebookLM · Azure · App Service

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure App Service, para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes.

Estructura obligatoria:
1. Qué es, con la analogía del bus con ruta fija; plan vs aplicación; SKUs y cuándo usar cada familia.
2. Cómo funciona por dentro: front ends, workers, el proxy hacia tu puerto, disco efímero vs /home, ARR affinity y el límite de ~230 segundos. Dibuja el flujo de una petición.
3. Slots de despliegue: swap, slot settings, calentamiento, porcentaje de tráfico y rollback.
4. Configuración: app settings como variables de entorno, relaxed binding de Spring, referencias a Key Vault, identidad administrada.
5. Red: access restrictions, Private Endpoint (entrada) y VNet Integration (salida) con subred delegada; por qué NO son lo mismo; route all y DNS.
6. Salud y recuperación: health check, Always On y auto-heal; por qué se necesitan 2 instancias.
7. Seguridad: HTTPS, TLS, desactivar FTP y SCM básico, Easy Auth vs seguridad dentro de la app.
8. Los 8 casos reales como historias con su lección.
9. Código Java: puerto, cabeceras del proxy y la IP con puerto, filtros en Spring MVC y WebFlux, health probes, tareas programadas en varias instancias, graceful shutdown, JVM y memoria, Quarkus equivalente.
10. Ejemplos de CLI, Terraform y GitHub Actions con identidad federada.
11. Qué hacer, qué NO hacer, límites y costos, y la tabla de troubleshooting.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
