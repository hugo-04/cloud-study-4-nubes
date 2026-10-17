# NotebookLM · Azure · Caso integrado · Clickstream con Event Hubs

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/` (Terraform, JSON, script de CLI y consultas KQL).

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre cómo construir en Azure una analítica de clics en tiempo real con Event Hubs, Data Lake y servicios de Azure, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. La analogía del conteo en la entrada de un estadio; el diagrama de colector, Event Hubs, agregador en línea, Capture y lago.
2. Cómo funciona por dentro: particiones, clave de partición, cubetas, grupos de consumidores, puntos de control, ventanas por minuto, eventos tardíos y duplicados, Capture.
3. Dimensionar con números: el ejemplo de ModaLima paso a paso (entrada, salida, unidades, particiones, auto-inflate con tope).
4. La clave caliente: qué es, por qué ocurre, cómo se detecta y cómo se corrige.
5. Lo aproximado y lo exacto: el camino en línea frente al lago y el recálculo por lotes; UPSERT idempotente.
6. Privacidad: seudónimos desde el colector, sal en Key Vault.
7. Seguridad: tabla de permisos por plano para cada identidad, amenazas y defensas.
8. Qué hacer y qué NO hacer, costos y límites.
9. Los siete casos reales como historias con su lección.
10. Código Java: planificador, detector de sesgo, anonimizador, colector, agregador por ventanas, publicador por cubetas, procesador con puntos de control, Spring MVC y WebFlux, Quarkus imperativo y reactivo, y las pruebas.
11. Troubleshooting por síntoma y la secuencia de diagnóstico.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
