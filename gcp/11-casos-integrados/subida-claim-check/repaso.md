# Google Cloud · Caso integrado · Subida con claim check · Repaso

## Preguntas
1. ¿Por qué subir directo al bucket?
2. ¿Qué limita la URL firmada?
3. ¿Por qué una cuarentena?
4. ¿Cómo se valida el tipo?
5. ¿Qué evita la transición condicional?
6. ¿Qué evita `ifGenerationMatch`?
7. ¿Qué lleva el ticket?
8. ¿Quién puede leer la cuarentena?
9. ¿Cómo se limpian las subidas abandonadas?
10. ¿Qué identidad firma la URL?

## Respuestas
1. Para no pasar el archivo por la app.
2. Método, tipo, objeto y vencimiento.
3. Para que nada sin validar sea visible.
4. Por la firma de los primeros bytes.
5. Procesar dos veces el mismo evento.
6. Aprobar una versión distinta a la validada.
7. Bucket, objeto, generación y hash.
8. Solo el validador.
9. Con ciclo de vida en el prefijo.
10. La SA de Cloud Run con signBlob.

## Ejercicios
1. Agrega WEBP a la validación.
2. Diseña la condición de IAM por prefijo.
3. Agrega antivirus al flujo.
