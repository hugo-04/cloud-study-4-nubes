# Google Cloud · Ingress y API · API Gateway · Repaso

## Preguntas
1. ¿Qué versión de OpenAPI usa?
2. ¿Qué es una configuración de API?
3. ¿Cómo llama el gateway a un Cloud Run privado?
4. ¿Qué diferencia hay entre llave de API y JWT?
5. ¿Qué cabecera recibe el backend con las claims?
6. ¿Cómo se aplican cuotas?
7. ¿Por qué el backend debe ser privado?
8. ¿Qué hace `path_translation`?
9. ¿Cómo cambias una ruta?
10. ¿Cuándo pensar en otra herramienta?

## Respuestas
1. OpenAPI 2.0.
2. Una versión inmutable de la especificación con su cuenta de backend.
3. Con un ID token de su cuenta de servicio (`run.invoker`).
4. La llave identifica al consumidor; el JWT autentica al usuario.
5. `X-Apigateway-Api-Userinfo`.
6. Con `x-google-management` y llaves de API.
7. Para que nadie se salte el gateway.
8. Define cómo se arma la URL hacia el backend.
9. Nueva configuración y actualizar el gateway.
10. Para monetización, portal y transformaciones complejas.

## Ejercicios
1. Escribe la especificación de catálogo y pedidos.
2. Define cuotas por socio.
3. Implementa en el backend la lectura de claims y la regla de dueño del pedido.
