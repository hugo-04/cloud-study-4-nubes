# Oracle OCI · Storage · File Storage · Casos reales

## 1. La carpeta que cualquiera podía escribir
**Qué pasó:** un servidor de pruebas borró por error las imágenes del catálogo de producción de ModaLima.
**Causa:** export con origen `0.0.0.0/0` y `READ_WRITE`; la subred de pruebas tenía ruta al mount target.
**Arreglo:** opciones por CIDR exacto de producción, `READ_ONLY` para los lectores y NSG del mount target.
**Lección:** en NFS, las *export options* son la política de acceso.

## 2. El root remoto
**Qué pasó:** un contenedor comprometido cambió permisos de todos los archivos.
**Causa:** `identity squash = NONE`; el root del contenedor era root en el NFS.
**Arreglo:** `ROOT` squash, contenedores sin root y UID/GID fijos.
**Lección:** nunca confíes en el root de un cliente.

## 3. El borrado sin vuelta atrás
**Qué pasó:** un script de limpieza de Café Andino borró la carpeta de facturas del mes.
**Causa:** no había snapshots.
**Arreglo:** política de snapshots diaria con retención de 30 días; restauración copiando desde `.snapshot`.
**Lección:** los snapshots son la papelera de reciclaje.

## 4. La app lenta con miles de archivos
**Qué pasó:** el listado de una carpeta con 2 millones de miniaturas tardaba minutos.
**Causa:** operación de metadatos masiva sobre NFS.
**Arreglo:** carpetas por prefijo (`ab/cd/…`) y mover las miniaturas a Object Storage.
**Lección:** NFS no es una base de datos de archivos.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Borrado desde otra red | Export abierto | CIDR exacto + NSG |
| 2 | Permisos alterados | Sin root squash | `ROOT` squash |
| 3 | Datos perdidos | Sin snapshots | Política de snapshots |
| 4 | Listados lentos | Metadatos masivos | Particionar o Object Storage |
