# AWS · Parameter Store · Repaso

## Preguntas
1. ¿Qué tipos de parámetro existen?
   - *String, StringList y SecureString.*
2. ¿Para qué sirve `GetParametersByPath`?
   - *Leer toda una rama de la jerarquía con paginación.*
3. ¿Cuándo usar Secrets Manager en vez de Parameter Store?
   - *Cuando la credencial necesita rotación automática.*
4. ¿Qué necesitas para leer un SecureString?
   - *`WithDecryption=true` y `kms:Decrypt`.*
5. ¿Cómo diseñas los permisos?
   - *Por ruta: `parameter/prod/pedidos/*`.*
6. ¿Qué ofrece el nivel avanzado?
   - *8 KB, más parámetros y políticas de caducidad.*
7. ¿Qué es una etiqueta de versión?
   - *Un alias que apunta a una versión concreta.*
8. ¿Por qué cachear los parámetros?
   - *Evitar costo, latencia y estrangulamiento.*
9. ¿Qué es AppConfig y cuándo?
   - *Despliegue gradual y validado de configuración y banderas.*
10. ¿Por qué no guardar un `SecureString` con Terraform?
    - *El valor queda en el estado.*

## Ejercicios
1. Diseña la jerarquía de parámetros de tres servicios y dos entornos.
2. Escribe la política de lectura por ruta con SecureString.
3. Decide para cada valor de una lista (URL, contraseña, bandera, certificado) dónde vive.
4. Implementa en pseudocódigo el refresco cada 5 minutos con valores por defecto.

## Autoevaluación
- [ ] Sé elegir entre Parameter Store, Secrets Manager y AppConfig.
- [ ] Diseño permisos por ruta.
- [ ] Sé cachear y refrescar la configuración.
- [ ] Sé qué parámetros no deben pasar por Terraform.
