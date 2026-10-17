# Transversal · Terraform · Repaso

## Preguntas
1. ¿Qué significa que Terraform sea declarativo?
2. ¿Qué guarda el estado y por qué es sensible?
3. ¿Para qué sirve el lock file?
4. ¿`for_each` o `count` para una lista de colas?
5. ¿Qué hace un bloque `moved`?
6. ¿Diferencia entre `precondition` y `check`?
7. ¿Por qué aplicar un plan guardado?
8. ¿Qué es la deriva y cómo se detecta?
9. ¿Qué NO debe gestionar Terraform?
10. ¿Qué prueba `terraform test`?

## Respuestas
1. Describes el estado final y la herramienta calcula los pasos.
2. La relación código-recursos con atributos; incluye secretos.
3. Fija versiones y hashes de providers para todos.
4. `for_each`: claves estables, no depende del orden.
5. Renombra direcciones sin destruir recursos.
6. `precondition` bloquea el recurso; `check` solo avisa.
7. Para aplicar exactamente lo revisado.
8. Cambios fuera de Terraform; con `plan -refresh-only`.
9. Configuración interna de VMs, despliegues frecuentes de la app y datos de negocio.
10. Planes o applies de un módulo con aserciones sobre salidas y recursos.

## Ejercicios
1. Agrega una validación que limite `replicas` a 1–20.
2. Convierte un `count` sobre una lista a `for_each` con `moved`.
3. Escribe una prueba que falle si prod tiene menos de 3 réplicas.
