# Oracle OCI · Secretos · Vault: secretos · Casos reales

## 1. La contraseña en la imagen
**Qué pasó:** la contraseña de la base apareció en una imagen de contenedor.
**Causa:** variable de entorno incrustada en el `Dockerfile`.
**Arreglo:** leer el secreto en el arranque con la identidad del pod.
**Lección:** nada sensible en imágenes ni repositorios.

## 2. Rotación que tumbó el servicio
**Qué pasó:** al rotar la clave de un proveedor, la app falló 10 minutos.
**Causa:** cambio directo del valor; las instancias tenían la anterior en caché.
**Arreglo:** `PENDING` → `CURRENT`, conservando `PREVIOUS`, y caché con TTL corto.
**Lección:** rotar es un proceso de dos pasos.

## 3. Vault lento, app caída
**Qué pasó:** un pico de latencia en Vault dejó sin respuesta al checkout.
**Causa:** lectura del secreto en cada pedido.
**Arreglo:** caché con TTL y *stale-if-error*.
**Lección:** el secreto es una dependencia: protégela.

## 4. El valor en el estado de Terraform
**Qué pasó:** el valor inicial de un secreto quedó visible en el estado.
**Causa:** `secret_content` literal.
**Arreglo:** estado cifrado y acceso restringido; cambiar el valor fuera de Terraform.
**Lección:** el estado es un secreto más.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Contraseña expuesta | En la imagen | Leer de Vault |
| 2 | Caída al rotar | Cambio directo | Etapas + TTL |
| 3 | Checkout caído | Lectura por petición | Caché + stale |
| 4 | Valor en el estado | Contenido literal | Proteger estado |
