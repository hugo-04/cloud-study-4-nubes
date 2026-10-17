# Oracle OCI · Secretos · Vault: llaves (KMS) · Repaso

## Preguntas
1. ¿Qué diferencia hay entre llave maestra y llave de datos?
2. ¿Por qué se usa cifrado de sobre?
3. ¿Qué se guarda junto al dato cifrado?
4. ¿Qué protege el AAD?
5. ¿Qué pasa al rotar una llave?
6. ¿Por qué el borrado es «programado»?
7. ¿Cuándo eliges HSM?
8. ¿Para qué dos endpoints?
9. ¿Qué política necesita una aplicación para cifrar?
10. ¿Puedes exportar la llave maestra?

## Respuestas
1. La maestra nunca sale del Vault; la de datos es de un solo uso y se usa localmente.
2. Para no enviar datos grandes y no exponer la maestra.
3. La llave envuelta, el IV y el texto cifrado.
4. Ata el dato a su contexto (por ejemplo, el id del registro).
5. Se crea una versión nueva; lo anterior sigue funcionando.
6. Para tener una ventana de arrepentimiento.
7. Datos sensibles o requisitos de cumplimiento.
8. Uno administra, el otro opera criptografía.
9. `use keys` sobre su llave concreta.
10. No, por diseño.

## Ejercicios
1. Dibuja el flujo de cifrar y descifrar un comprobante.
2. Escribe la política mínima para `app-tienda`.
3. Define el procedimiento para borrar una llave sin riesgo.
