# Oracle OCI · Caso integrado · Subida con claim check · Repaso

## Preguntas
1. ¿Por qué el archivo no pasa por la API?
2. ¿Qué tipo de PAR se usa?
3. ¿Qué es la cuarentena?
4. ¿Cómo validas el tipo real?
5. ¿Qué dispara la validación?
6. ¿Por qué `renameObject`?
7. ¿Qué viaja por la cola?
8. ¿Qué hace el reconciliador?
9. ¿Qué es una transición condicional?
10. ¿Qué limpia la cuarentena si todo falla?

## Respuestas
1. Para no consumir memoria ni ancho de banda de los servicios.
2. `ObjectWrite` con nombre fijo y vencimiento corto.
3. Un prefijo donde los archivos esperan validación.
4. Con la firma de los primeros bytes y el tamaño.
5. El evento `createobject` del bucket.
6. Mueve dentro del bucket sin copiar los datos y con condiciones.
7. Un ticket con objeto, huella y tamaño.
8. Expira pendientes y limpia restos.
9. Cambiar de estado solo si el actual es el esperado.
10. Su regla de ciclo de vida.

## Ejercicios
1. Agrega el paso de antivirus antes de aprobar.
2. Diseña el registro de estado en NoSQL (clave, TTL, versión).
3. Escribe el reconciliador.
