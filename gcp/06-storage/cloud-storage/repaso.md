# Google Cloud · Storage · Cloud Storage · Repaso

## Preguntas
1. ¿Qué es la generación de un objeto?
2. ¿Cómo evitas sobrescribir?
3. ¿Qué clases hay?
4. ¿Qué es el acceso uniforme?
5. ¿Qué hace la prevención de acceso público?
6. ¿Qué consistencia ofrece?
7. ¿Cuándo usar subida reanudable?
8. ¿Qué rol escribe sin poder leer?
9. ¿Qué limita escribir al mismo objeto?
10. ¿Cómo compartes sin hacer público?

## Respuestas
1. Su número de versión, que cambia en cada escritura.
2. Con `ifGenerationMatch=0` (`doesNotExist()`).
3. Standard, Nearline, Coldline y Archive.
4. Permisos solo por IAM, sin ACL.
5. Impide otorgar acceso a `allUsers`/`allAuthenticatedUsers`.
6. Fuerte.
7. Para archivos grandes o redes inestables.
8. `roles/storage.objectCreator`.
9. Una escritura por segundo aproximadamente.
10. Con URLs firmadas.

## Ejercicios
1. Diseña nombres y ciclo de vida de los comprobantes de ModaLima.
2. Calcula el costo de 5 TB en Standard vs Coldline.
3. Escribe la política IAM con condición por prefijo.
