# AWS · Caso integrado · Subida con Claim Check · Repaso

## Preguntas
1. ¿Por qué el archivo no pasa por la API?
2. ¿Qué viaja por la cola en lugar del archivo?
3. ¿Qué se firma en la URL y qué efecto tiene?
4. ¿Para qué una cuarentena separada?
5. ¿Por qué no basta mirar la extensión?
6. ¿Cómo se evita procesar dos veces el mismo aviso?
7. ¿Qué hace el reconciliador y por qué existe?
8. ¿En qué orden se promueve un archivo y por qué?
9. ¿Cómo se protege la descarga?
10. ¿Qué NO resuelve la validación de firma?

## Respuestas
1. Para no gastar ancho de banda, memoria ni límites de la API; S3 lo recibe directo.
2. El identificador (el «ticket») y, a través del evento, la clave del objeto.
3. `Content-Type` y `Content-Length`; otro valor da 403.
4. Para que nada sin revisar toque producción y para limpiar con ciclo de vida.
5. Porque la elige quien sube; los primeros bytes dicen el formato real.
6. Transición condicional de estado: el segundo intento no cambia nada.
7. Contrasta estados con S3 y repara avisos perdidos o atascos.
8. Copiar → transición condicional → borrar cuarentena; así un reintento siempre puede continuar.
9. URL corta, bajo demanda, solo al dueño y solo si `VALIDADO`.
10. Malware dentro de un formato válido: eso requiere un escáner.

## Ejercicios
1. Añade el tipo `image/webp` (firma `RIFF....WEBP`) a `TipoArchivo`.
2. Escribe la consulta que lista cargas `SUBIDO` de más de 10 minutos.
3. Cambia la validez de la URL a 2 minutos: ¿qué debe cambiar en el front?
4. Diseña el mensaje de rechazo para el usuario sin exponer detalles internos.

## Autoevaluación
- [ ] Puedo dibujar el flujo y los estados.
- [ ] Explico por qué se borra la cuarentena al final.
- [ ] Sé diagnosticar un 403 de subida.
