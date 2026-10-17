# AWS · KMS · Repaso

## Preguntas
1. ¿Sale la clave de KMS de AWS en claro?
   - *No; las operaciones se hacen dentro de KMS.*
2. ¿Qué es el cifrado de sobre y por qué se usa?
   - *Cifrar el dato con una clave de datos y esta con KMS; evita el límite de 4 KB y reduce llamadas.*
3. ¿Qué es la política de clave?
   - *La raíz de la autorización de la clave.*
4. ¿Para qué sirve el contexto de cifrado?
   - *Autentica el dato con sus etiquetas y aparece en CloudTrail.*
5. ¿Por qué CMK en lugar de `aws/s3` si compartes entre cuentas?
   - *Las claves administradas por AWS no permiten compartir ni editar la política.*
6. ¿Qué pasa al borrar una clave?
   - *Los datos cifrados con ella quedan irrecuperables; hay ventana de 7–30 días.*
7. ¿Cómo reduces las llamadas a KMS desde S3?
   - *S3 Bucket Keys.*
8. ¿Qué condición limita el uso de una clave a un servicio?
   - *`kms:ViaService`.*
9. ¿Qué tamaño máximo tiene `Encrypt` directo?
   - *4 KB.*
10. ¿Qué diferencia hay entre administrar y usar una clave?
    - *Administrar: gestionar política/estado; usar: cifrar/descifrar. Se separan.*

## Ejercicios
1. Diseña las claves de ModaLima (por dominio y entorno) con sus alias.
2. Escribe la política de clave con administradores y usuarios separados.
3. Calcula el costo de 10 claves y 50 millones de solicitudes con y sin Bucket Keys.
4. Describe el flujo de cifrado de sobre de un campo `numeroTarjeta` con contexto.

## Autoevaluación
- [ ] Sé explicar el cifrado de sobre.
- [ ] Sé qué decide la política de clave.
- [ ] Siempre uso contexto de cifrado.
- [ ] Sé qué hacer antes de borrar una clave.
