# Azure · Key Vault · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar.)

## Caso 1 · La contraseña que llegó a Git
- **Problema:** un desarrollador de ModaLima subió `application.properties` con la contraseña de la base de datos a un repositorio.
- **Acciones inmediatas:** **rotar la contraseña primero**, luego limpiar el historial, revisar accesos recientes y activar el escaneo de secretos del repositorio.
- **Solución estructural:** la contraseña vive en Key Vault y la app la lee con Managed Identity (rol *Key Vault Secrets User*).
- **Lección:** rotar primero, investigar después. Un secreto expuesto se considera comprometido para siempre.

## Caso 2 · Rotación sin caída
- **Problema:** rotar la clave de la API de pagos obligaba a redesplegar y dejaba la tienda caída unos minutos.
- **Solución:** secreto versionado + **doble credencial** (el proveedor acepta la vieja y la nueva) + la app relee el secreto cada 5 minutos.
- **Resultado:** rotación mensual automática sin interrupción.
- **Lección:** diseña la aplicación para **tolerar el cambio de credenciales**.

## Caso 3 · "Borraron la clave y no abre nada"
- **Problema:** alguien eliminó la clave CMK que cifraba el storage de reportes; los datos dejaron de ser legibles.
- **Causa:** el vault no tenía *purge protection* y la clave estaba en uso.
- **Solución:** se recuperó gracias al *soft delete*; después se activó *purge protection* y un bloqueo contra borrado del vault.
- **Lección:** la clave es **tan importante como los datos**. Protégela más.

## Caso 4 · Certificado vencido en un sábado
- **Problema:** el certificado TLS del dominio venció y las compras se cayeron.
- **Solución:** certificados en Key Vault con renovación automática, alerta `CertificateNearExpiry` y un panel con fechas de vencimiento.
- **Lección:** el vencimiento de certificados es un incidente 100 % evitable.

## Caso 5 · El 429 de las 8 de la noche
- **Problema:** durante una campaña, la API leía el secreto de la base de datos **en cada petición**. El vault respondió `429 Too Many Requests` y los pedidos fallaron.
- **Causa:** miles de lecturas por segundo contra un solo vault.
- **Solución:** el secreto se carga al arrancar y se **cachea 5 minutos**; ante 401/403 de la base se vuelve a leer una sola vez.
- **Lección:** el vault es una caja fuerte, no una variable de entorno de alta frecuencia.

## Caso 6 · La referencia que nunca se resolvía
- **Problema:** en App Service, `DB_PASSWORD` mostraba literalmente `@Microsoft.KeyVault(...)` en vez del valor.
- **Causas encontradas (en este orden):** la app no tenía identidad; la identidad no tenía *Secrets User*; el vault tenía acceso público cerrado y la app no estaba integrada a la VNet.
- **Solución:** habilitar identidad, asignar el rol, integrar la app a la VNet y enlazar la zona DNS privada.
- **Lección:** Identidad + Permiso + Red + DNS: las cuatro, o no funciona.

## Caso 7 · Un vault para todos los entornos
- **Problema:** dev, test y prod compartían un vault. Un desarrollador con rol en dev podía leer la contraseña de producción.
- **Solución:** un vault por aplicación y por entorno; en dev, secretos distintos y de bajo riesgo.
- **Lección:** el vault es una frontera de seguridad; no la compartas entre entornos.

## Caso 8 · Cifrado de reportes con envelope encryption
- **Problema:** Café Andino guardaba reportes con datos personales en Blob y querían controlar la clave.
- **Solución:** la app genera una clave AES por archivo, cifra localmente y **envuelve** esa clave con una clave RSA del vault (`wrapKey`); guarda el archivo cifrado y la clave envuelta juntos.
- **Resultado:** el vault solo ve claves pequeñas, nunca los archivos; revocar la clave maestra deja ilegibles todos los reportes.
- **Lección:** cifra los datos localmente y usa el vault para proteger la clave.
