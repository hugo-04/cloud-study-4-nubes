# Azure · Cosmos DB · Troubleshooting

Sigue el flujo: **¿llega a la cuenta? → ¿se autentica y autoriza? → ¿el código de estado qué dice? → ¿cuántas RU gasta? → ¿está repartido?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| Tiempo de espera al conectar / `408` | Red: DNS devuelve IP pública con acceso público cerrado, firewall, puertos 10250–10255 bloqueados (modo directo) | `nslookup <cuenta>.documents.azure.com`; reglas de firewall/NSG | Zona DNS privada enlazada; abrir puertos del modo directo o usar modo Gateway |
| `401 Unauthorized` | Token inválido o de otro *tenant*; cliente con clave cuando las claves están desactivadas | Registros `CDBDataPlaneRequests` (401) | Usar `DefaultAzureCredential`; sin claves en la configuración |
| `403 Forbidden` con rol *Contributor* | Falta un **rol de datos de Cosmos** (los roles de Azure no dan acceso a documentos) | `az cosmosdb sql role assignment list` | Asignar *Data Contributor/Reader* con el alcance correcto |
| `403` por firewall | IP/VNet no permitida o acceso público desactivado sin Private Endpoint | Mensaje del error; red de la cuenta | Private Endpoint o agregar IP/VNet |
| `404` en una lectura que "debería existir" | Clave de partición equivocada (incluida mayúscula/minúscula o tipo), `id` distinto, contenedor/base incorrectos | Leer con la clave que tiene el documento en el Explorador de datos | Enviar la **misma** clave que guarda el documento |
| `409 Conflict` | Ya existe (`id` + clave) o clave única violada | Mensaje del error | Idempotencia: tratar como "ya hecho"; revisar claves únicas |
| `412 Precondition Failed` | ETag o predicado del patch no coinciden | Código en la respuesta | Releer y reintentar; revisar contención |
| `413 Request Entity Too Large` | Documento > 2 MB o lote demasiado grande | Tamaño del documento | Dividir documentos; mover binarios a Blob; evitar arreglos sin límite |
| `429 Too Many Requests` | RU insuficientes o **partición caliente** | Métrica *Normalized RU Consumption* y `CDBPartitionKeyRUConsumption` | Autoscale, más RU, corregir la clave; el SDK reintenta |
| Consultas lentas / muchas RU | Consulta entre particiones, falta de índice compuesto, funciones en el filtro, `OFFSET` alto, `SELECT *` | `getRequestCharge()`; `CDBQueryRuntimeStatistics`; Explorador → *Query Stats* | Fijar la clave, índices compuestos, proyectar campos, paginar con token |
| `ORDER BY` falla ("composite index needed") | Falta índice compuesto para varias propiedades | Mensaje del error | Añadir el índice compuesto en la política de indexación |
| Documentos "desaparecen" | `defaultTtl` o `ttl` activos | Configuración de TTL del contenedor y del documento | Revisar TTL; restaurar desde copia continua |
| No se ve el `ttl` por documento | El contenedor no tiene TTL activado (`defaultTtl` ausente) | Propiedades del contenedor | `defaultTtl = -1` para habilitarlo sin vencimiento por defecto |
| Change feed no entrega cambios | Prefijo/arrendamientos distintos, procesador detenido, nombre de instancia repetido | Contenedor `leases`; métrica de retraso | Prefijo estable, instancia con nombre único, revisar errores del manejador |
| Change feed procesa lo mismo varias veces | Entrega *at-least-once*, error en el manejador, reinicios | Registros del manejador | Idempotencia; cola de errores; no dejar tareas asíncronas sin esperar |
| No aparecen los borrados en el change feed | Modo "última versión" no incluye borrados | Modo del procesador | Borrado lógico + TTL (o modo de todas las versiones y eliminaciones, *verifica disponibilidad*) |
| `Partition key reached maximum size of 20 GB` | Partición lógica demasiado grande | `CDBPartitionKeyStatistics` | Clave jerárquica o nueva clave; migrar datos |
| Lecturas desactualizadas | Nivel de consistencia más débil; sesión no propagada | Nivel de la cuenta y de la solicitud | Propagar token de sesión o fortalecer el nivel (con costo) |
| Latencia alta entre regiones | Escritura en otra región, `preferredRegions` no configuradas | Regiones de la cuenta; cabecera de diagnóstico | Configurar regiones preferidas; escritura multiregión si procede |
| Errores tras *failover* | Cliente sin reintento o con una sola región | Registros 503 | Regiones preferidas y reintentos; pruebas periódicas |
| `Request rate is large` en el plano de control | Demasiadas llamadas de administración (crear contenedores en bucle) | `CDBControlPlaneRequests` | Reducir frecuencia; crear contenedores en el despliegue, no en cada arranque |
| Emulador no conecta (pruebas) | Certificado no confiable, modo directo en contenedor | Mensaje TLS | Importar el certificado; `gatewayMode()` |
| Costo inesperado | RU de más, muchas regiones, copia continua, índices excesivos, contenedores con throughput dedicado ocioso | Costos por recurso y métricas de RU | Autoscale, excluir índices, compartir RU en bases de desarrollo, serverless en dev |

## Secuencia recomendada
1. **Código de estado** (401/403/404/409/412/413/429/503): casi siempre el diagnóstico está ahí.
2. **Red y DNS:** `nslookup`, Private Endpoint, puertos del modo directo.
3. **Identidad y rol de datos** (no el rol de Azure).
4. **RU por operación:** `getRequestCharge()`, tabla `CDBDataPlaneRequests`.
5. **Reparto:** *Normalized RU Consumption*, `CDBPartitionKeyRUConsumption`.
6. **Modelo:** ¿la consulta lleva la clave? ¿índice compuesto? ¿documento demasiado grande?
7. **Change feed:** arrendamientos, retraso, idempotencia.
8. **Aplicación:** cliente único, regiones preferidas, reintentos y tiempos.

Consultas en [ejemplos/kql](ejemplos/kql/kql-cosmos.md); comandos en [ejemplos/cli](ejemplos/cli/cosmos-db.sh); consultas de ejemplo en [ejemplos/consultas](ejemplos/consultas/consultas-cosmos.md).
