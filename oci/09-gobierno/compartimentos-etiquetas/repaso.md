# Oracle OCI · Gobierno · Compartimentos, etiquetas y cuotas · Repaso

## Preguntas
1. ¿Qué se hereda en la jerarquía de compartimentos?
2. ¿Diferencia entre etiqueta libre y definida?
3. ¿Qué hace una etiqueta por defecto obligatoria?
4. ¿Qué es una cuota?
5. ¿Cuota o límite de servicio: cuál manda?
6. ¿Cómo organizarías los compartimentos?
7. ¿Qué pasa al mover un recurso?
8. ¿Qué permiso necesita quien etiqueta?
9. ¿Por qué no trabajar en la raíz?
10. ¿Qué cuesta todo esto?

## Respuestas
1. Las políticas y las etiquetas por defecto.
2. La libre no se valida; la definida tiene validación y permisos.
3. Exige un valor (o lo pone automáticamente) en cada recurso creado.
4. Un tope propio por compartimento.
5. Ambos: la cuota no puede superar el límite.
6. Por dueño y entorno, 2–3 niveles.
7. Cambian sus políticas efectivas.
8. `use tag-namespaces`.
9. Porque todo hereda de ella y es difícil acotar permisos.
10. Nada.

## Ejercicios
1. Diseña la jerarquía de ModaLima con prod, no-prod, red y seguridad.
2. Define 4 etiquetas obligatorias con sus listas de valores.
3. Escribe las cuotas de no-prod (OCPU, GPU, bases).
