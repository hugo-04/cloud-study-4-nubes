# Diseño de ACL para un lago (ejemplo ModaLima)

## Principios
1. **Grupos, no personas.** Una ACL por persona agota el límite de entradas y es imposible de auditar.
2. **Dos juegos de entradas:** *acceso* (lo que ya existe) y *por defecto* (lo que se cree después).
3. **`x` en toda la ruta.** Sin `--x` en la raíz y en cada carpeta intermedia, el grupo no llega.
4. **Los roles de datos saltan las ACL.** Si alguien tiene *Storage Blob Data Contributor/Reader* sobre la cuenta, las ACL no lo frenan.
5. **Primero la plantilla, luego los datos.** Fija las ACL por defecto en los directorios padre antes de cargar.

## Grupos
| Grupo | Quién | Qué necesita |
|---|---|---|
| `g-lago-ingenieria` | Ingeniería de datos | Escribir en bronze/silver |
| `g-lago-analistas` | Analistas/BI | Leer silver/gold |
| `g-lago-pipelines` | Identidades de los pipelines | Escribir en landing/bronze |
| `g-lago-admin` | Administradores del lago | *Storage Blob Data Owner* (súper-usuario) |

## Matriz de permisos
| Ruta | `g-lago-pipelines` | `g-lago-ingenieria` | `g-lago-analistas` |
|---|---|---|---|
| `landing/` | `rwx` | `r-x` | — |
| `bronze/` | `rwx` | `rwx` | — |
| `silver/` (raíz) | — | `--x` | `--x` |
| `silver/ventas/` | — | `rwx` (+ default) | `r-x` (+ default) |
| `gold/` | — | `rwx` | `r-x` (+ default) |

## Cómo comprobarlo (checklist)
1. `az storage fs access show -f silver -p ventas` → ¿aparecen las dos entradas por grupo (acceso y default)?
2. Crea un archivo nuevo y comprueba que **hereda** la ACL por defecto.
3. Con una cuenta de un analista: listar `ventas/` (debe funcionar) y escribir (debe fallar con 403).
4. Revisa que ninguna identidad de usuario tenga un rol de datos a nivel de cuenta.
5. Registra en el diagnóstico los `403` por ACL para detectar rutas mal configuradas.

## Errores típicos
| Síntoma | Causa |
|---|---|
| El grupo ve la carpeta pero no entra | Falta `x` en un directorio padre |
| Archivos nuevos no heredan permisos | No había ACL por defecto cuando se crearon |
| "Funciona para algunos usuarios y no para otros" | Algunos tienen un rol de datos (salta ACL) y otros dependen de ACL |
| La operación recursiva dejó fallos | Reanudar con el token de continuación; revisar rutas bloqueadas |
| Se borraron entradas existentes | Se usó `set` (reemplaza) en lugar de `update` |
