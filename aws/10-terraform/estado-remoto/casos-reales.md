# AWS · Estado remoto · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. Dos `apply` a la vez
**Qué pasó:** dos personas aplicaron el mismo componente con minutos de diferencia; el segundo estado pisó al primero y quedó un balanceador «huérfano». **Solución:** backend en S3 con `use_lockfile`; el segundo `apply` ahora espera o falla con el nombre de quién tiene el candado. **Lección:** el candado no es burocracia; es el cinturón de seguridad.

## 2. La contraseña en el estado
**Qué pasó:** una revisión de seguridad encontró la contraseña de una base de datos en texto claro dentro del estado, que cualquier desarrollador podía leer. **Solución:** bucket exclusivo con permisos por prefijo, KMS con clave propia, personas sin acceso y la contraseña gestionada por Secrets Manager (generada fuera del código). **Lección:** el estado no es una bóveda, pero hay que tratarlo como una.

## 3. El estado borrado
**Qué pasó:** alguien borró por error el objeto del estado de `datos`. **Solución:** el versionado conservaba la versión anterior; se restauró copiando esa versión como la actual y un `plan` confirmó «0 changes». **Lección:** sin versionado habría sido reimportar cien recursos a mano.

## 4. El estado gigante
**Qué pasó:** un solo estado con red, datos y aplicaciones tardaba 40 minutos en planificar y cualquier cambio bloqueaba a todos. **Solución:** dividir por componente y entorno (`env/prod/red`, `env/prod/datos`, `env/prod/apps`) y compartir solo salidas. **Lección:** un estado por ritmo de cambio y por radio de explosión.

## 5. Renombrar sin destruir
**Qué pasó:** al renombrar un recurso en el código, el plan quería **destruir y recrear** una base de datos. **Solución:** un bloque `moved` y la verificación de «0 to destroy» antes de aprobar. **Lección:** renombrar es una operación del estado, no solo del código.

## 6. Adoptar lo creado a mano
**Qué pasó:** un bucket creado en la consola debía pasar a Terraform. **Solución:** bloque `import` con `plan -generate-config-out`, revisión del código generado y un `plan` sin cambios antes de aprobar. **Lección:** adoptar es declarativo y revisable; copiar atributos a mano es adivinar.

## Resumen

| # | Problema | Pieza que lo resolvió |
|---|---|---|
| 1 | Dos `apply` simultáneos | Candado (`use_lockfile`) |
| 2 | Secretos legibles en el estado | KMS + permisos por prefijo + sin acceso humano |
| 3 | Estado borrado | Versionado + restauración |
| 4 | Estado enorme y lento | División por componente y entorno |
| 5 | Plan que destruye al renombrar | `moved` |
| 6 | Recurso creado a mano | `import` + `-generate-config-out` |
