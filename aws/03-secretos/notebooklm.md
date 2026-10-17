# NotebookLM · AWS · Capítulo 03 Secretos y configuración

**Fuentes a subir:** este `README.md` y los `README.md`, `casos-reales.md` y `uso-en-java.md` de las carpetas `secrets-manager`, `kms` y `parameter-store`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, sobre cómo un microservicio en AWS maneja credenciales, claves de cifrado y configuración. Habla solo de AWS; no compares con otras nubes.

Estructura obligatoria:
1. El problema: por qué nada de esto va en el código ni en variables de entorno con contraseñas.
2. Los tres servicios con su analogía: Secrets Manager (caja fuerte con cambio automático), KMS (cerrajería central) y Parameter Store (archivador con carpetas).
3. El árbol de decisión «quiero guardar…» recorrido caso por caso.
4. La tabla comparativa completa.
5. Cómo se apoyan: SecureString y secretos cifrados con KMS; permisos con IAM.
6. La receta de ModaLima, fila por fila.
7. El orden de adopción y las reglas transversales.
8. Java: caché con TTL y reintento por rotación, cifrado de sobre con contexto, lectura de la rama de parámetros con valores tipados; Spring MVC y WebFlux, Quarkus imperativo y Mutiny.
9. Errores típicos y cómo diagnosticarlos.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima y Café Andino como ejemplos; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
