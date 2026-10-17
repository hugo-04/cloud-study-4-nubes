# NotebookLM · Azure · Caso integrado · Subida con Claim Check

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/` (Terraform, esquema SQL, JSON de eventos y tickets, script de CLI y consultas KQL).

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre cómo construir en Azure la subida segura de archivos con el patrón Claim Check, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. La analogía del buzón con zona de revisión; el diagrama completo desde la app hasta los procesadores.
2. Los nueve pasos del flujo, con qué servicio interviene en cada uno y por qué.
3. Blob Storage con contenedores de cuarentena y validados, SAS de delegación de usuario frente a SAS con clave de cuenta, CORS para subir desde el navegador, Event Grid hacia una cola, política de ciclo de vida.
4. La máquina de estados de la subida: estados, transiciones permitidas, control optimista, eventos duplicados, validador repetible y conciliador.
5. Validación: tamaño, tipo real por bytes mágicos, hash, política de archivos; por qué no confiar en la extensión.
6. Claim Check: el ticket, el aviso mediante la bandeja de salida y los consumidores.
7. Seguridad: tabla de permisos por plano para cada identidad, amenazas y defensas.
8. Los ocho casos reales como historias con su lección.
9. Código Java: reglas puras, repositorio, iniciar subida, validador, conciliador, adaptador de Blob y cola, Spring MVC y WebFlux, Quarkus imperativo y reactivo, y las pruebas.
10. Troubleshooting por síntoma y la secuencia de diagnóstico.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de Café Andino y ModaLima; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
