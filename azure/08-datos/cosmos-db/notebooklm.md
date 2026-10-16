# NotebookLM · Azure · Cosmos DB (API para NoSQL)

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/` (Terraform, CLI, JSON, consultas, KQL).

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure Cosmos DB (API para NoSQL), para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes ni con otras bases de datos de otras nubes.

Estructura obligatoria:
1. Qué es, con la analogía de la bodega con casilleros etiquetados; jerarquía cuenta → base → contenedor → documento; propiedades del sistema (_etag, _ts).
2. Particionamiento: partición lógica y física, límites (20 GB, 10 000 RU/s), cómo elegir la clave, claves jerárquicas, partición caliente y consulta entre particiones. Diagrama.
3. Unidades de solicitud (RU): lectura puntual, escritura, consulta; manual, autoscale y serverless; capa gratuita; mínimos y costos.
4. Los cinco niveles de consistencia con ejemplos; consistencia de sesión y propagación del token en microservicios.
5. Indexado: política por defecto, exclusiones, índices compuestos, TTL, claves únicas, búsqueda vectorial.
6. Change feed: procesador, contenedor de arrendamientos, escalado entre instancias, entrega al menos una vez, borrados, usos (Outbox, proyecciones CQRS).
7. Transacciones: lote transaccional, concurrencia optimista con ETag, patch condicional.
8. Distribución global: regiones, conmutación, escritura multiregión, zonas; copias periódica y continua con restauración a un instante.
9. Red y seguridad: Private Endpoint, firewall, desactivar claves, RBAC de datos y roles integrados frente a Azure RBAC; tabla de IAM por rol.
10. Modelado: incrustar o referenciar, agregados, arreglos sin límite, dinero en enteros y fechas ISO-8601.
11. Los 15 casos reales como historias con su lección: partición por fecha, consulta del almacén, campaña, indexado, duplicados del change feed, TTL que borró datos, stock concurrente, inquilino de 20 GB, caída de región, claves filtradas, contenedor borrado, OFFSET, modelo relacional a documento, documento de 2 MB y sesión.
12. Código Java: cliente único con Entra ID, repositorio con ETag y patch, consulta paginada, controlador con Idempotency-Key e If-Match, lote transaccional con Outbox, procesador del change feed hacia Service Bus, importación masiva, WebFlux, Quarkus imperativo y Quarkus reactivo con Mutiny, pruebas con el emulador.
13. Ejemplos de Terraform, CLI, JSON, consultas y KQL; qué hacer y qué NO hacer; límites y versiones.
14. Tabla de troubleshooting por código de estado y secuencia de diagnóstico.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
