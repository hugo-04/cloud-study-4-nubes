# Azure · Azure Files · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar.)

## Caso 1 · Un sistema heredado que necesita una carpeta compartida
- **Problema:** el ERP de ModaLima deja y lee archivos de conciliación en `\\servidor\conciliacion`; al migrar a Azure no puede cambiarse.
- **Solución:** share premium SMB montado en la VM del ERP con identidad; instantáneas diarias con Azure Backup.
- **Resultado:** migración sin tocar código y sin servidor de archivos que parchear.
- **Lección:** Azure Files sirve cuando el requisito es "una ruta de archivos".

## Caso 2 · Pods de AKS que comparten una carpeta
- **Problema:** tres réplicas del procesador debían leer los mismos archivos de entrada; con discos administrados solo un pod podía montarlos.
- **Solución:** PVC `ReadWriteMany` con el controlador CSI de Azure Files y "reclamar por renombrado" para repartir el trabajo.
- **Lección:** disco = un nodo a la vez; Files = muchos a la vez.

## Caso 3 · "Funciona en la VM de Azure, no en mi oficina"
- **Problema:** el equipo de contabilidad no podía montar el share desde casa.
- **Causa:** el proveedor de internet bloquea el puerto 445.
- **Solución:** VPN a la VNet + Private Endpoint; para integraciones, el SDK por HTTPS (443).
- **Lección:** SMB no viaja por Internet: siempre red privada.

## Caso 4 · Se borró el share equivocado
- **Problema:** un `terraform destroy` en el entorno equivocado borró un share de producción.
- **Solución:** *soft delete* de shares (7 días) permitió restaurarlo con sus instantáneas; se añadió bloqueo `CanNotDelete` al recurso.
- **Lección:** *soft delete* + bloqueos antes del primer incidente.

## Caso 5 · Desactivamos las claves y se cayó medio sistema
- **Problema:** al poner `shared_access_key_enabled = false` dejaron de montar App Service y un volumen de Container Apps.
- **Causa:** esos servicios montaban el share con la **clave de la cuenta**.
- **Solución:** separar una cuenta para esos montajes (con red cerrada y rotación de claves) y mantener sin claves las cuentas con acceso por identidad.
- **Lección:** revisa quién usa claves **antes** de desactivarlas.

## Caso 6 · Listar una carpeta de 3 millones de archivos tarda minutos
- **Problema:** el job nocturno hacía `Files.list` sobre una carpeta plana enorme en un share estándar.
- **Solución:** particionar por fecha (`/2026/10/16/`), mover lo procesado y pasar a premium.
- **Lección:** el rendimiento de metadatos depende de la estructura y del nivel.

## Caso 7 · Archivos leídos a medias
- **Problema:** el procesador tomaba archivos que el proveedor aún estaba copiando y fallaba el análisis.
- **Solución:** escribir como `.part` y renombrar; el lector ignora `.part` y exige que el archivo no cambie en 30 segundos.
- **Lección:** los sistemas de archivos no tienen "transacción de escritura": créala con renombrado atómico.

## Caso 8 · Dos réplicas procesaron el mismo archivo
- **Problema:** una factura se generó dos veces.
- **Causa:** ambas listaron la carpeta y tomaron el mismo archivo.
- **Solución:** reclamar con `Files.move(ATOMIC_MOVE)` hacia `procesando/`: solo una gana; la otra recibe `NoSuchFileException`.
- **Lección:** el renombrado atómico es un candado barato.

## Caso 9 · Aplicación lenta porque escribía temporales en el share
- **Problema:** un servicio de reportes tardaba 8 veces más tras migrar.
- **Causa:** generaba archivos temporales y logs sobre el share montado (latencia de red en cada escritura pequeña).
- **Solución:** temporales en disco local/efímero y solo el resultado final al share.
- **Lección:** el share es almacenamiento compartido, no disco de trabajo.

## Caso 10 · Perfiles de usuario lentos (escritorios virtuales)
- **Problema:** el inicio de sesión tardaba 90 segundos.
- **Solución:** share premium en la misma región que los escritorios, Private Endpoint, ajuste de cuota para subir IOPS.
- **Lección:** en premium, la cuota aprovisionada define el rendimiento; mide y dimensiona.

## Caso 11 · DNS que apuntaba a la IP pública
- **Problema:** con Private Endpoint creado, los servidores locales seguían yendo por Internet y fallaban.
- **Causa:** el DNS local no reenviaba `privatelink.file.core.windows.net` a Azure.
- **Solución:** reenviador condicional hacia el resolvedor de Azure (o Private Resolver).
- **Lección:** el Private Endpoint sin DNS correcto no sirve.
