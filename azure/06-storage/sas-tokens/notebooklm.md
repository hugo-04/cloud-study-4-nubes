# NotebookLM · Azure · SAS tokens

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre las SAS (Shared Access Signature) de Azure Storage, para un ingeniero Java de microservicios que quiere dominarlas de inicio a fin. No compares con otras nubes.

Estructura obligatoria:
1. Qué es una SAS, con la analogía de la llave de un solo casillero que caduca en 15 minutos; por qué es una credencial al portador.
2. Anatomía de la URL: cada parámetro (sv, st, se, sr, sp, spr, sip, si, rscd, sig y los de delegación) explicado con ejemplos.
3. Cómo funciona por dentro: quién firma, qué comprueba Storage, y por qué en la SAS de delegación el acceso efectivo es la intersección con los permisos del firmante.
4. Los tres tipos (delegación de usuario, servicio, cuenta), la clave de delegación (hasta 7 días) y la política de acceso almacenada.
5. Permisos: tabla completa de letras (r, a, c, w, d, l, t, m...) y combinaciones para subir, reemplazar, descargar y listar.
6. Lo que una SAS no hace: no limita tamaño, no valida contenido, no se revoca individualmente si es ad hoc.
7. Revocación: revocar claves de delegación, borrar la política, rotar la clave.
8. Flujo de subida directa desde el navegador con bloques, CORS y confirmación; patrón de descarga con rscd.
9. Los 11 casos reales como historias con su lección.
10. Código Java: emitir SAS de delegación con la clave cacheada, endpoint de solicitud y confirmación, SAS de servicio con política almacenada, versión reactiva y Quarkus con Mutiny; y el código JavaScript del navegador.
11. Ejemplos de CLI y Terraform.
12. Cuándo NO usar una SAS, qué hacer, qué NO hacer, IAM (Delegator más rol de datos) y la tabla de troubleshooting con cómo depurar una firma.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
