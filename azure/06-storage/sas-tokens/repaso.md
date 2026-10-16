# Azure · SAS tokens · Repaso

## Preguntas de repaso
1. ¿Qué es una SAS y por qué decimos que es una credencial "al portador"?
   - *URL firmada con acceso delegado, limitado y temporal; quien la tiene, accede.*
2. ¿Diferencia entre SAS de delegación de usuario, de servicio y de cuenta?
   - *Delegación: firmada con una clave de Entra ID (la recomendada); servicio y cuenta: firmadas con la clave de la cuenta.*
3. ¿Qué permisos pones para que un cliente suba un archivo nuevo? ¿Y para que lo descargue?
   - *Subida: `cw` (blob único). Descarga: `r`.*
4. ¿Qué roles necesita el backend que emite SAS de delegación?
   - *Storage Blob Delegator (a nivel de cuenta o superior) y un rol de datos con el permiso que va a delegar.*
5. ¿Por qué una SAS de delegación puede dejar de funcionar sin haber vencido?
   - *Porque el acceso efectivo es la intersección con los permisos del firmante; si pierde el rol, deja de funcionar.*
6. ¿Cómo se revoca una SAS?
   - *Delegación: revocar claves de delegación o quitar permisos al firmante. Servicio: borrar la política almacenada. Cuenta: rotar la clave.*
7. ¿Qué limita y qué NO limita una SAS?
   - *Limita recurso, permisos, tiempo, IP y protocolo; NO limita el tamaño ni valida el contenido.*
8. ¿Por qué no usar `st` igual a la hora actual?
   - *El desfase de reloj puede dejarla "aún no válida"; usa −5 min o sin `st`.*
9. ¿Para qué sirven `rscd` y `rsct`?
   - *Controlar `Content-Disposition` y `Content-Type` de la respuesta, p. ej. el nombre de descarga.*
10. ¿Qué pasa con una SAS en una cuenta solo privada?
    - *Solo funciona para clientes que alcancen el Private Endpoint.*
11. ¿Cómo evitas llamar a `getUserDelegationKey` en cada petición?
    - *Cachea la clave (hasta su vencimiento, con margen) y reutilízala.*
12. ¿Por qué el nombre del blob lo genera el servidor?
    - *Evita colisiones, sobrescrituras y ataques de ruta.*

## Entrevista
- Diseña la subida de un archivo de 500 MB desde un navegador con análisis antivirus y procesamiento asíncrono.
- ¿Cómo revocarías de inmediato un acceso temporal entregado hace 10 minutos?
- ¿Cómo darías acceso de escritura a un proveedor externo con el menor riesgo posible?
- ¿Cómo limitas el tamaño de lo que sube un cliente si la SAS no lo hace?

## Ejercicio práctico
1. Genera con la CLI una SAS de lectura de 5 minutos y una de escritura (`cw`) de 10; pruébalas con `curl`.
2. Implementa el endpoint de [uso en Java](uso-en-java.md) con caché de la clave de delegación.
3. Sube un archivo desde [subida.js](ejemplos/web/subida.js) en bloques y confirma con la API.
4. Quita el rol al firmante y observa el 403; restáuralo.
5. Ejecuta `revoke-delegation-keys` y comprueba que las SAS vigentes mueren.
