# Oracle OCI · Storage · Object Storage · Repaso

## Preguntas
1. ¿Qué es el namespace?
2. ¿Qué niveles de almacenamiento hay?
3. ¿Cómo evitas sobrescribir un objeto?
4. ¿Para qué sirve el ETag?
5. ¿Qué hace una regla de ciclo de vida?
6. ¿Cuándo usar multipart?
7. ¿Cómo se comparte un objeto de un bucket privado?
8. ¿Cómo se accede sin Internet desde una subred privada?
9. ¿Qué permiso necesita el servicio para usar tu llave?
10. ¿Qué pasa al leer un objeto en `Archive`?

## Respuestas
1. Un nombre único del tenancy que forma parte de las URL de Object Storage.
2. Standard, InfrequentAccess y Archive.
3. Con `If-None-Match: *`.
4. Para detectar la versión del objeto y hacer escrituras condicionales.
5. Mueve de nivel o borra objetos por prefijo y edad.
6. Para objetos grandes (desde ~100 MB) o redes inestables.
7. Con una PAR.
8. Con la puerta de servicios.
9. `use keys` sobre esa llave.
10. Falla hasta restaurarlo.

## Ejercicios
1. Diseña el esquema de nombres de los comprobantes de ModaLima.
2. Escribe las reglas de ciclo de vida de los respaldos de Café Andino.
3. Escribe la política mínima para que la app de pedidos solo escriba bajo `pedidos/`.
