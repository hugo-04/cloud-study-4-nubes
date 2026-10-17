# AWS · Módulos y entornos · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. Veinte copias del mismo código
**Qué pasó:** cada equipo copió el código de «cola con DLQ»; al descubrir que faltaba el cifrado, hubo que corregir veinte repositorios. **Solución:** un módulo `servicio-base` con el cifrado incorporado y una migración con `moved`. **Lección:** un arreglo, un lugar.

## 2. El módulo sin versión
**Qué pasó:** los entornos apuntaban a la rama `main` del módulo; un cambio «inocente» alteró el nombre de las colas y el plan de producción quería recrearlas. **Solución:** `?ref=v1.4.0` en todos los consumidores y etiquetas protegidas. **Lección:** un módulo sin versión es un cambio que ocurre sin pedir permiso.

## 3. El `count` y el orden de la lista
**Qué pasó:** al quitar el primer servicio de una lista, `count` renumeró los demás y el plan proponía destruir y recrear todos. **Solución:** `for_each` con un mapa cuya clave es el nombre del servicio. **Lección:** las claves estables evitan reemplazos en cadena.

## 4. Workspaces como entornos
**Qué pasó:** se separaban `dev` y `prod` con workspaces; alguien aplicó en el workspace equivocado. **Solución:** carpetas por entorno con backend, variables y rol propios. **Lección:** lo importante debe ser visible en la ruta, no en un estado oculto del terminal.

## 5. Renombrar sin destruir
**Qué pasó:** al renombrar `module.cola` a `module.servicio`, el plan quería borrar las colas con mensajes. **Solución:** un bloque `moved` por módulo y la verificación de «0 to destroy». **Lección:** refactorizar es cambiar la dirección en el estado, no los recursos.

## 6. El cambio que quitó el cifrado
**Qué pasó:** una variable nueva permitió apagar el cifrado «para depurar». **Solución:** se eliminó la variable, el cifrado es parte del contrato y `terraform test` verifica que las colas siempre lo tengan. **Lección:** no expongas lo que no quieres que se apague.

## Resumen

| # | Problema | Pieza que lo resolvió |
|---|---|---|
| 1 | Código copiado veinte veces | Módulo + `moved` |
| 2 | Cambios silenciosos del módulo | Versión fija (`?ref=`) |
| 3 | Recreación en cadena por `count` | `for_each` con mapa |
| 4 | Aplicar en el entorno equivocado | Carpetas por entorno |
| 5 | Plan que borra al renombrar | `moved` + «0 to destroy» |
| 6 | Cifrado desactivable | Contrato + `terraform test` |
