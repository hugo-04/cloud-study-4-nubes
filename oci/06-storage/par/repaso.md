# Oracle OCI · Storage · PAR · Repaso

## Preguntas
1. ¿Qué es una PAR?
2. ¿Qué tipos de acceso existen?
3. ¿Cuántas veces puedes ver la URL de una PAR?
4. ¿Qué permiso necesita quien la crea?
5. ¿Cómo revocas una PAR?
6. ¿Por qué no registrar la URL?
7. ¿Cuándo usar `ObjectWrite` en lugar de `AnyObjectWrite`?
8. ¿Qué pasa si el creador pierde permisos?
9. ¿Qué vencimiento es razonable para una descarga?
10. ¿Cuándo NO usar PAR?

## Respuestas
1. Una URL con secreto que da acceso limitado sin credenciales de OCI.
2. `ObjectRead`, `ObjectWrite`, `ObjectReadWrite` y las variantes `Any*`.
3. Una sola, al crearla.
4. `PAR_MANAGE` más los permisos que delega.
5. Borrándola con su id.
6. Porque es una credencial de portador.
7. Cuando el backend fija el nombre del objeto (casi siempre).
8. La PAR deja de funcionar.
9. Entre 5 y 15 minutos.
10. Para acceso permanente de un sistema: usa IAM.

## Ejercicios
1. Diseña el flujo de subida directa de fotos de productos de ModaLima.
2. Escribe la política mínima para emitir PAR de lectura solo bajo `pedidos/`.
3. Diseña la rotación semanal de las PAR de proveedores de Café Andino.
