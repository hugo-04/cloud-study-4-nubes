# Oracle OCI · IAM · Compartimentos, grupos y políticas · Repaso

## Preguntas
1. ¿Qué dice por defecto OCI sobre los permisos?
2. ¿Qué verbos existen y cuál incluye a cuál?
3. ¿Qué es una familia de recursos?
4. ¿Hasta dónde llega una política adjunta a un compartimento?
5. ¿Por qué `any-user` es peligroso?
6. ¿Para qué sirve una cláusula `where`?
7. ¿Existen reglas de denegación?
8. ¿Qué significa `NotAuthorizedOrNotFound`?
9. ¿Por qué políticas pequeñas?
10. ¿Qué es un grupo dinámico?

## Respuestas
1. Todo está denegado hasta que una política lo permita.
2. `inspect` < `read` < `use` < `manage`; cada uno incluye lo anterior.
3. Un conjunto de tipos relacionados, como `object-family`.
4. A ese compartimento y a sus hijos.
5. Aplica a cualquier principal; sin condición abre el recurso a todos.
6. Para acotar por atributos (bucket, etiqueta, tipo de principal…).
7. No; solo hay permisos que se suman.
8. Falta permiso o el recurso no existe; OCI no lo distingue.
9. Son más fáciles de revisar y de reutilizar.
10. Un conjunto de recursos que actúan como identidad.

## Ejercicios
1. Escribe las frases para un equipo de desarrollo (dev: manage; prod: read).
2. Acota una frase de lectura de objetos a un solo bucket.
3. Corrige `Allow any-user to manage all-resources in tenancy`.
