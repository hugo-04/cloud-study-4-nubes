# Google Cloud · Secretos · Cloud KMS · Repaso

## Preguntas
1. ¿Qué es un llavero?
2. ¿Qué propósitos puede tener una llave?
3. ¿Qué hace la versión primaria?
4. ¿Qué es el cifrado de sobre?
5. ¿Para qué AAD?
6. ¿Qué es CMEK y qué permiso necesita?
7. ¿Qué niveles de protección hay?
8. ¿Qué pasa al destruir una versión?
9. ¿Quién debe administrar y quién usar?
10. ¿Cuándo usar Secret Manager en su lugar?

## Respuestas
1. Un agrupador de llaves en una ubicación.
2. Cifrar/descifrar, firma asimétrica, descifrado asimétrico, MAC.
3. Cifra los datos nuevos.
4. Cifrar datos con una DEK y la DEK con la llave de KMS.
5. Atar el cifrado a su contexto para evitar sustituciones.
6. Que servicios de Google cifren con tu llave; su agente necesita `cryptoKeyEncrypterDecrypter`.
7. Software, HSM y externo.
8. Lo cifrado con ella ya no se puede descifrar.
9. Identidades distintas (separación de funciones).
10. Para guardar valores que la app debe leer.

## Ejercicios
1. Diseña el cifrado de documentos de clientes de ModaLima con AAD.
2. Planifica la rotación y el re-cifrado.
3. Escribe los bindings CMEK para un bucket y un tema de Pub/Sub.
