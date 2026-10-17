# Oracle OCI · Storage · Eventos de Object Storage · Repaso

## Preguntas
1. ¿Qué hay que activar en el bucket?
2. ¿Qué tipos de evento emite Object Storage?
3. ¿Qué destinos puede tener una regla?
4. ¿Qué garantía de entrega hay?
5. ¿Con qué campo deduplicas?
6. ¿El evento trae el contenido del archivo?
7. ¿Cómo evitas un ciclo de eventos?
8. ¿Por qué hacer `HEAD` antes de procesar?
9. ¿Hay orden garantizado?
10. ¿Qué política necesita Events para invocar una función?

## Respuestas
1. `object_events_enabled`.
2. Crear, actualizar y borrar objeto.
3. Functions, Notifications y Streaming.
4. Al menos una vez.
5. `eventID`.
6. No; solo metadatos.
7. Escribiendo el resultado en otro bucket o prefijo.
8. El objeto puede haber cambiado o desaparecido.
9. No.
10. Una política que permita a Events `use fn-invocation` sobre la función.

## Ejercicios
1. Escribe la condición de la regla para facturas en el bucket `entregas-proveedores`.
2. Diseña la tabla de deduplicación de `eventID` con expiración.
3. Diseña un flujo que avise por correo solo si el archivo supera 10 MB.
