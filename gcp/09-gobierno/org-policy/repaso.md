# Google Cloud · Gobierno · Organization Policy · Repaso

## Preguntas
1. ¿En qué se diferencia de IAM?
2. ¿Tipos de restricciones?
3. ¿Qué es una restricción personalizada?
4. ¿Para qué sirve el dry run?
5. ¿Qué es la política efectiva?
6. ¿Cómo haces una excepción acotada?
7. ¿Qué restricción evita IP pública en Cloud SQL?
8. ¿Y la que limita regiones?
9. ¿Quién debería administrar políticas?
10. ¿Qué hace `reset`?

## Respuestas
1. IAM dice quién puede; Org Policy qué configuraciones se permiten, para todos.
2. Booleanas, de lista y personalizadas.
3. Una condición CEL propia sobre campos de un recurso.
4. Para registrar violaciones sin bloquear.
5. El resultado tras herencia y fusión en un recurso.
6. Con una condición por tag.
7. `sql.restrictPublicIp`.
8. `gcp.resourceLocations`.
9. Un grupo pequeño de seguridad con `policyAdmin`, por código.
10. Vuelve al comportamiento por defecto de Google en ese nodo.

## Ejercicios
1. Escribe la línea base de 6 políticas de ModaLima.
2. Diseña una excepción por tag para un laboratorio.
3. Escribe una restricción personalizada para GKE privado.
