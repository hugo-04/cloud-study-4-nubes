# Azure · Data Lake Gen2 · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar.)

## Caso 1 · Lakehouse medallion de ventas
- **Problema:** las ventas llegaban de tiendas, e-commerce y marketplaces con formatos distintos y sin trazabilidad.
- **Solución:** `landing` (tal cual llega) → `bronze` (inmutable) → `silver` (limpio, Parquet, particionado por fecha) → `gold` (modelos de negocio). ACL por zona y por grupo.
- **Resultado:** reprocesos baratos (se vuelve a bronce) y analistas que solo ven silver/gold.
- **Lección:** zonas con propósito y permisos distintos.

## Caso 2 · El `rename` de 2 millones de archivos
- **Problema:** un trabajo Spark tardaba 40 minutos solo en "confirmar" su salida.
- **Causa:** en un contenedor sin HNS, mover la carpeta temporal a la final copiaba y borraba archivo por archivo.
- **Solución:** cuenta con HNS: el `rename` de directorio es una operación atómica de metadatos.
- **Lección:** HNS elimina el costo del renombrado masivo.

## Caso 3 · "Tengo permiso en la carpeta pero no entro"
- **Problema:** un analista recibía 403 al abrir `silver/ventas/anio=2026`.
- **Causa:** el grupo tenía `r-x` en `ventas/` pero no `--x` en la **raíz** de `silver`.
- **Solución:** `x` en cada directorio del camino.
- **Lección:** para llegar al dato necesitas ejecutar en toda la ruta.

## Caso 4 · Un rol amplio que anuló las ACL
- **Problema:** un practicante veía datos personales de `gold/clientes`.
- **Causa:** tenía *Storage Blob Data Reader* a nivel de cuenta (para otro proyecto); RBAC se evalúa antes y ya le concedía la lectura.
- **Solución:** quitar el rol amplio, usar ACL con grupos, y revisión trimestral de asignaciones de datos.
- **Lección:** RBAC amplio = las ACL no se miran.

## Caso 5 · Las ACL por defecto no llegaron a lo anterior
- **Problema:** se dio acceso a un grupo nuevo; podía ver lo nuevo pero no lo histórico.
- **Causa:** las ACL por defecto solo aplican a lo creado después.
- **Solución:** `update-recursive` sobre el árbol existente (fuera de horas pico) y luego dejar el default.
- **Lección:** default = futuro; recursivo = pasado.

## Caso 6 · Diez millones de archivos de 2 KB
- **Problema:** las consultas eran lentas y la factura de transacciones alta.
- **Causa:** una ingesta guardaba un archivo por evento.
- **Solución:** compactación periódica a Parquet de cientos de MB y ingesta por micro-lotes.
- **Lección:** pocos archivos grandes, no millones de pequeños.

## Caso 7 · Migrar una cuenta existente a HNS
- **Problema:** el lago empezó como Blob plano y las operaciones masivas eran lentas.
- **Solución:** validación previa de la migración, ventana de mantenimiento, actualización a HNS y revisión de funciones no soportadas (versionado, instantáneas).
- **Lección:** la migración es de ida: valida y planifica.

## Caso 8 · Socio con SFTP
- **Problema:** Café Andino enviaba sus archivos por SFTP a un servidor propio que nadie mantenía.
- **Solución:** SFTP del almacenamiento con usuario local, llave SSH y directorio de inicio `landing/socios/cafeandino`; evento de creación dispara el procesamiento.
- **Resultado:** un servidor menos y aislamiento por socio.
- **Lección:** SFTP es útil, pero cuesta por hora habilitado y requiere red controlada.

## Caso 9 · Event Hubs Capture hacia el lago
- **Problema:** se necesitaba conservar todos los eventos de pedidos para analítica.
- **Solución:** Capture del hub escribe Avro particionado por fecha en `bronze/pedidos/`; un trabajo lo convierte a Parquet en silver.
- **Lección:** el lago es el histórico barato de los streams.

## Caso 10 · El Private Endpoint que solo cubría `blob`
- **Problema:** Spark dentro de la VNet no podía alcanzar el lago.
- **Causa:** se creó Private Endpoint de `blob` pero no de **`dfs`**, que es el endpoint de ABFS.
- **Solución:** Private Endpoint y zona DNS privada para `dfs` además de `blob`.
- **Lección:** HNS usa dos subrecursos; crea ambos.

## Caso 11 · Borrado de una partición completa
- **Problema:** un trabajo con la ruta equivocada borró `silver/ventas/anio=2026`.
- **Solución:** *soft delete* del contenedor/blobs, restauración desde bronce (reproceso) y política de revisión previa en los trabajos de borrado.
- **Lección:** la inmutabilidad de bronce y el reproceso son el seguro real del lago.
