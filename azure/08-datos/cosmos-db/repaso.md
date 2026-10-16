# Azure · Cosmos DB · Repaso

## Preguntas de repaso
1. ¿Qué es Cosmos DB (API para NoSQL) en una frase?
   - *Base de datos de documentos JSON administrada, repartida automáticamente por clave de partición, con latencia de milisegundos y cobro por unidades de solicitud (RU).*
2. ¿Qué es una RU y cuánto cuesta una lectura puntual de 1 KB?
   - *Moneda del costo de una operación; una lectura puntual de 1 KB cuesta aproximadamente 1 RU.*
3. ¿Qué identifica de verdad a un documento?
   - *`id` + valor de la clave de partición.*
4. ¿Cómo se elige una buena clave de partición?
   - *Alta cardinalidad, reparto parejo de lecturas y escrituras, presente en las consultas frecuentes; pensando primero en las consultas.*
5. ¿Qué es una partición lógica y una física? ¿Cuáles son sus límites?
   - *Lógica = mismo valor de clave (máx. 20 GB); física = infraestructura interna (máx. 10 000 RU/s) que aloja muchas lógicas.*
6. ¿Qué es una partición caliente y cómo se nota?
   - *Una clave concentra el tráfico; 429 con RU libres globalmente; se ve en *Normalized RU Consumption* y `CDBPartitionKeyRUConsumption`.*
7. ¿Manual, autoscale o serverless?
   - *Manual para carga constante, autoscale para picos (paga ≥ 10 % del máximo), serverless para desarrollo y cargas pequeñas (una región).*
8. ¿Cuáles son los cinco niveles de consistencia y cuál es el por defecto?
   - *Strong, Bounded staleness, Session (por defecto), Consistent prefix, Eventual.*
9. ¿Qué garantiza *Session* y cuál es la trampa en microservicios?
   - *Leer tus propias escrituras dentro de una sesión; hay que propagar el token de sesión entre instancias.*
10. ¿Por qué se excluyen rutas del índice?
    - *Cada propiedad indexada encarece las escrituras; excluir lo que no filtras ahorra RU.*
11. ¿Qué es el change feed y qué garantía ofrece?
    - *Registro ordenado de cambios por partición; entrega al menos una vez, así que el manejador debe ser idempotente.*
12. ¿Para qué sirve el contenedor `leases`?
    - *Guarda el progreso del procesador y reparte los rangos entre instancias.*
13. ¿Qué transacciones existen?
    - *ACID dentro de una partición lógica (lote transaccional de hasta 100 operaciones, procedimientos almacenados); no hay transacciones entre particiones o contenedores.*
14. ¿Cómo evitas "el último en escribir gana"?
    - *ETag con `If-Match` (412 si cambió) o `patch` condicional.*
15. ¿Cómo se autentica una aplicación sin claves?
    - *Identidad administrada + rol de datos de Cosmos (*Data Contributor/Reader*); claves desactivadas con `disableLocalAuth`.*
16. ¿Por qué el rol *Owner* de Azure no puede leer documentos?
    - *Los permisos de datos son roles de Cosmos distintos de los de Azure RBAC.*
17. ¿Cómo se restaura un contenedor borrado?
    - *Con copia continua: restauración a un instante en una cuenta nueva (autoservicio); con copia periódica, mediante soporte.*
18. ¿Cuándo NO usar Cosmos DB?
    - *Joins complejos, informes ad hoc, transacciones multi-entidad, archivos grandes, datos muy relacionales.*

## Entrevista
- Diseña el modelo de pedidos de ModaLima: documento, clave de partición, índices y por qué.
- Una API recibe 429 en horas pico con RU disponibles. ¿Qué investigas y cómo lo resuelves?
- ¿Cómo implementas Outbox con Cosmos DB sin una base relacional?
- Explica cómo propagarías el token de sesión entre microservicios.
- ¿Cómo migrarías de una clave de partición equivocada a la correcta con mínima interrupción?
- ¿Qué cambia en el código entre Spring MVC, WebFlux y Quarkus reactivo?

## Ejercicio práctico
1. Despliega el [Terraform](ejemplos/terraform/main.tf) en `dev` (serverless).
2. Inserta el [documento de ejemplo](ejemplos/json/pedido-ejemplo.json) y mide las RU de una lectura puntual y de una consulta entre particiones.
3. Cambia la política de indexación con [politica-indexado.json](ejemplos/json/politica-indexado.json) y compara el costo de escritura.
4. Implementa el repositorio con ETag: provoca un 412 con dos clientes y resuélvelo con reintento.
5. Crea el pedido y su evento con **lote transaccional** y publica con el **procesador del change feed**; reinicia el servicio y comprueba la idempotencia.
6. Provoca un 429 con la importación masiva y observa el comportamiento del SDK.
7. Revisa en Log Analytics las consultas de [KQL](ejemplos/kql/kql-cosmos.md).
8. Desactiva las claves y comprueba que solo funciona con Entra ID.
