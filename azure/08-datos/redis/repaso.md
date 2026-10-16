# Azure · Redis · Repaso

## Preguntas de repaso
1. ¿Qué es Azure Managed Redis en una frase?
   - *Servicio administrado de Redis (almacén clave-valor en memoria) con alta disponibilidad, módulos, Entra ID y geo-replicación activa.*
2. ¿Para qué se usa principalmente?
   - *Caché, sesiones y carritos, limitadores de tasa, idempotencia, bloqueos ligeros, reservas atómicas, rankings y colas pequeñas.*
3. ¿Cuándo NO se debe usar como almacén principal?
   - *Cuando es la única copia de datos valiosos: la memoria es volátil y la replicación asíncrona puede perder escrituras recientes.*
4. ¿Qué diferencia hay entre OSSCluster y EnterpriseCluster?
   - *OSSCluster expone la API de clúster (el cliente debe soportarla; mejor rendimiento); EnterpriseCluster tiene un solo endpoint con proxy (cualquier cliente; necesaria para RediSearch).*
5. ¿Se puede cambiar la política de clúster después de crear la instancia?
   - *No. Hay que crear otra instancia y migrar.*
6. ¿Qué es un slot y qué es `CROSSSLOT`?
   - *Slot = cubeta de hash (0–16 383) que decide el shard; `CROSSSLOT` ocurre cuando un comando multiclave usa claves de slots distintos.*
7. ¿Cómo se fuerza que varias claves caigan en el mismo slot?
   - *Con una etiqueta de hash `{...}` en el nombre de la clave: solo lo que va entre llaves decide el slot.*
8. ¿Qué hace la política de expulsión `VolatileLRU` y cuál es su trampa?
   - *Expulsa claves con TTL menos usadas; si tus claves no tienen TTL, nunca se expulsan y la memoria se llena.*
9. ¿Qué pasa con `NoEviction` cuando se llena la memoria?
   - *Las escrituras fallan (`OOM`). Es la política necesaria con RediSearch y para datos que no pueden perderse.*
10. ¿Qué es la estampida de caché y cómo se evita?
    - *Muchas solicitudes recargan a la vez al vencer una clave popular; se evita con TTL con jitter, una sola carga por clave y precalentamiento.*
11. ¿Qué es la caché negativa?
    - *Guardar durante poco tiempo que "no existe" para no consultar la base repetidamente por algo ausente.*
12. ¿Cómo se autentica una aplicación sin claves?
    - *Con Entra ID: token del ámbito `https://redis.azure.com/.default`, `AUTH <object id> <token>` y renovación automática del token antes de que caduque.*
13. ¿Qué pasa si el token caduca y no se renueva?
    - *Redis cierra la conexión; aparecen errores periódicos con la frecuencia de vida del token.*
14. ¿Qué biblioteca renueva el token en Java?
    - *`redis-authx-entraid` (con Lettuce): proveedor de credenciales que renueva y reautentica las conexiones abiertas.*
15. ¿Por qué un script Lua para el limitador de tasa o el stock?
    - *Para que varias operaciones (leer, comparar, escribir, poner TTL) sean atómicas; un `INCR` y un `EXPIRE` separados pueden dejar claves sin TTL.*
16. ¿Qué garantiza un bloqueo distribuido en Redis?
    - *Evita trabajo duplicado de forma "mejor esfuerzo"; no garantiza exclusión estricta (puede vencer a mitad del trabajo). Se complementa con restricciones únicas, ETag o tokens de cercado.*
17. ¿Cuándo usar Streams, Pub/Sub o un broker?
    - *Pub/Sub: avisos efímeros (invalidar L1). Streams: colas ligeras con confirmación. Service Bus/Event Hubs: mensajes con valor, durabilidad y reproducción.*
18. ¿Qué significa activo-activo en la geo-replicación?
    - *Hasta 5 instancias que aceptan escrituras en todas, con replicación bidireccional y resolución de conflictos por tipo de dato (consistencia eventual).*
19. ¿Qué hay que cuidar con claves grandes y calientes?
    - *Una clave enorme bloquea al mover o replicar; una clave caliente concentra tráfico en un shard. Divide los valores y limita colecciones.*
20. ¿Cómo debe comportarse la aplicación si Redis falla?
    - *Con tiempos de espera cortos, reconexión, disyuntor y degradación a la base de datos con límite de concurrencia: la caché es una optimización, no una dependencia dura.*

## Mini-ejercicios
1. Diseña las claves del carrito de ModaLima para OSSCluster: ¿qué etiqueta de hash usarías y qué TTL?
2. Escribe en pseudocódigo la secuencia del limitador de 100 solicitudes por minuto con una sola llamada atómica.
3. Una consulta de catálogo tarda 400 ms en la base. Calcula cuántas solicitudes por segundo evita Redis con 95 % de aciertos si llegan 2 000 por segundo.
4. Explica por qué reservar stock con "leer, restar, escribir" falla con dos pods y cómo lo resuelve el script `reservar-stock.lua`.
5. ¿Qué métricas pondrías en alertas para detectar una caché a punto de llenarse y una estampida?

## Frases para recordar
- **TTL en todo lo que sea caché, con jitter.**
- **Una conexión, token que se renueva, tiempos cortos.**
- **Operaciones compuestas → Lua.** Bloqueo con token, y la verdad en la base de datos.
- **Redis es memoria, no la fuente de verdad.**
- **En clúster, piensa en slots.**
