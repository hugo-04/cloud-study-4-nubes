# Oracle OCI · Caso integrado · Clickstream · Repaso

## Preguntas
1. ¿Por qué la clave es la sesión?
2. ¿Qué es una ventana fija?
3. ¿Qué es la marca de agua?
4. ¿Qué haces con un evento tardío?
5. ¿Cuándo haces commit del offset?
6. ¿Dónde vive el historial?
7. ¿Cómo evitas datos personales?
8. ¿Qué pieza limita la tasa de entrada?
9. ¿Cómo reprocesas una hora concreta?
10. ¿Para qué NO sirve este caso?

## Respuestas
1. Da orden por sesión y reparte la carga.
2. Un bloque de tiempo sin solaparse (1 minuto).
3. El límite de tiempo antes del cual ya no se esperan eventos.
4. Se cuenta si está dentro del retraso permitido; si no, aparte.
5. Después de escribir el agregado.
6. En Object Storage vía Service Connector.
7. Con identificadores aleatorios y sin IP ni correo completos.
8. API Gateway.
9. Con un cursor `AT_TIME` (dentro de la retención) o desde el historial.
10. Para conteos exactos de facturación.

## Ejercicios
1. Calcula particiones para 4 MB/s en el Cyber con margen.
2. Diseña el formato del evento de clic.
3. Escribe el reproceso desde Object Storage.
