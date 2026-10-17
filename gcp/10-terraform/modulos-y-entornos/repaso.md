# Google Cloud · Terraform · Módulos y entornos · Repaso

## Preguntas
1. ¿Qué es un módulo raíz?
2. ¿Por qué fijar la versión del módulo?
3. ¿Directorios o workspaces para entornos?
4. ¿Qué aísla de verdad a los entornos?
5. ¿Para qué sirven las validaciones?
6. ¿Dónde se configura el provider?
7. ¿Qué es un bloque `moved`?
8. ¿Cómo detectas deriva?
9. ¿Qué es un módulo pasamanos?
10. ¿Cómo promueves una versión?

## Respuestas
1. El directorio donde se ejecuta plan/apply.
2. Para que un entorno no cambie sin decisión explícita.
3. Directorios.
4. Proyecto y SA por entorno.
5. Para rechazar valores inválidos en el plan.
6. En el módulo raíz.
7. Una forma de renombrar recursos sin recrearlos.
8. Con `plan -refresh-only`.
9. Un módulo que envuelve un recurso sin agregar valor.
10. Subiendo el `ref` en dev, luego staging, luego prod.

## Ejercicios
1. Agrega una validación de regiones permitidas.
2. Escribe un `moved` para renombrar el módulo.
3. Diseña la promoción de v1.5.0.
