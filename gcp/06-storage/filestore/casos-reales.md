# Google Cloud · Storage · Filestore · Casos reales

## 1. Montable desde cualquier lado
**Qué pasó:** una VM de pruebas de ModaLima borró imágenes del CMS de producción.
**Causa:** sin opciones de exportación: cualquier IP de la red podía montar en RW.
**Arreglo:** RW solo desde la subred del CMS, RO para reportes.
**Lección:** en NFS, las opciones de exportación son la política.

## 2. El root del contenedor
**Qué pasó:** un contenedor comprometido cambió permisos de todo el recurso compartido.
**Causa:** `NO_ROOT_SQUASH`.
**Arreglo:** `ROOT_SQUASH` y contenedores sin root con UID fijo.
**Lección:** nunca confíes en el root del cliente.

## 3. Pagar por lo vacío
**Qué pasó:** Café Andino pagaba 10 TiB usando 800 GiB.
**Causa:** Filestore cobra lo aprovisionado.
**Arreglo:** reducir capacidad (si el nivel lo permite) y mover archivos fríos a Cloud Storage.
**Lección:** dimensiona y revisa.

## 4. Sin vuelta atrás
**Qué pasó:** un script borró una carpeta de facturas.
**Causa:** sin snapshots.
**Arreglo:** snapshots diarios y respaldos semanales.
**Lección:** la papelera hay que configurarla.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Borrado cruzado | Exportación abierta | Rangos y modos |
| 2 | Permisos alterados | Sin squash | ROOT_SQUASH |
| 3 | Costo alto | Sobredimensión | Ajustar |
| 4 | Pérdida | Sin snapshots | Programar |
