# Google Cloud · Gobierno · Jerarquía y etiquetas · Repaso

## Preguntas
1. ¿Cuáles son los niveles de la jerarquía?
2. ¿Qué se hereda?
3. ¿Diferencia entre label y tag?
4. ¿Dónde conviene poner los tags?
5. ¿Para qué sirve un lien?
6. ¿Qué rol vincula tags?
7. ¿Cómo se usa un tag en IAM?
8. ¿Qué labels pedirías siempre?
9. ¿Se puede quitar abajo un permiso dado arriba?
10. ¿Dónde se ven los labels en costos?

## Respuestas
1. Organización, carpetas, proyectos y recursos.
2. IAM, políticas de organización y tags.
3. El label informa; el tag tiene permisos y efecto en políticas.
4. En carpetas, para que hereden.
5. Para impedir el borrado de un proyecto.
6. `roles/resourcemanager.tagUser`.
7. Con una condición `resource.matchTag(...)`.
8. `equipo`, `entorno`, `centro-costo`.
9. No con IAM normal; sí con políticas de denegación.
10. En la exportación de facturación.

## Ejercicios
1. Diseña la jerarquía de ModaLima con tres entornos.
2. Escribe una condición de IAM solo para `entorno=no-prod`.
3. Define el validador de labels del pipeline.
