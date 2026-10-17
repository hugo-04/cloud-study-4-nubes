# Google Cloud · Secretos · Secret Manager · Casos reales

## 1. La cuota de lecturas en el Cyber
**Qué pasó:** el checkout de ModaLima recibía errores 429 de Secret Manager en horas punta.
**Causa:** se leía la contraseña de la base en cada petición.
**Arreglo:** caché de 5 minutos con gracia ante fallos.
**Lección:** los secretos se leen al arrancar y se renuevan cada tanto.

## 2. La rotación que tumbó la base
**Qué pasó:** tras rotar, las réplicas viejas no conectaban.
**Causa:** se cambió la contraseña en la base antes de que las apps leyeran la versión nueva.
**Arreglo:** usuario doble (A/B) o contraseña nueva válida en paralelo, cambio de versión, y luego retiro.
**Lección:** rotar es un proceso de varios pasos.

## 3. Todos leían todo
**Qué pasó:** el servicio de catálogo podía leer el token de la pasarela de pagos.
**Causa:** `secretAccessor` a nivel de proyecto.
**Arreglo:** IAM por secreto.
**Lección:** cada secreto, su política.

## 4. La versión destruida
**Qué pasó:** un script de limpieza de Café Andino destruyó la versión que usaba un servicio fijado a ella.
**Causa:** destruir sin deshabilitar y observar.
**Arreglo:** deshabilitar, esperar, revisar Audit Logs de acceso y recién destruir.
**Lección:** destruir es irreversible.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | 429 | Lectura por petición | Caché |
| 2 | Conexiones fallidas | Rotación brusca | Doble validez |
| 3 | Acceso cruzado | Rol de proyecto | Por secreto |
| 4 | Servicio roto | Versión destruida | Deshabilitar primero |
