# NotebookLM · Azure · Blob Storage

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure Blob Storage, para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes.

Estructura obligatoria:
1. Qué es, con la analogía de la bodega con casilleros; cuenta, contenedor, blob y prefijos; por qué no es un disco.
2. Cómo funciona por dentro: tipos de cuenta, tipos de blob (block, append, page) y cómo se sube un block blob por bloques. Dibuja el diagrama.
3. Tiers (Hot, Cool, Cold, Archive), permanencias mínimas y rehidratación.
4. Redundancia (LRS, ZRS, GRS, GZRS, RA-) y qué significa la replicación asíncrona.
5. Protección de datos: soft delete, versionado, snapshots, change feed, point-in-time restore, inmutabilidad, replicación de objetos.
6. Ciclo de vida, metadatos y etiquetas de índice; concurrencia con ETag y leases.
7. Cifrado, red (firewall, service endpoints, Private Endpoint), CORS y los modos de autorización de mejor a peor.
8. Rendimiento: bloques, concurrencia, particiones y el 503 ServerBusy.
9. Los 11 casos reales como historias con su lección.
10. Código Java: cliente con DefaultAzureCredential, subida en bloques con condiciones, descarga en streaming, listado por prefijo, etiquetas, tiers, ETag y lease, versión reactiva con Reactor y Quarkus con Mutiny.
11. Ejemplos de CLI, AzCopy, regla de ciclo de vida y Terraform.
12. Cuándo NO usar Blob Storage, qué hacer, qué NO hacer, costos, IAM (datos vs administración) y la tabla de troubleshooting.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
