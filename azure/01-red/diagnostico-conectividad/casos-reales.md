# Azure · Diagnóstico de conectividad · Casos reales (detectives)

## Caso 1 · "Los pods no bajan la imagen"
- **Problema:** ModaLima movió su registro a un ACR con Private Endpoint y cerró el acceso público. Los pods nuevos quedaron en `ImagePullBackOff`.
- **Pistas:** `kubectl describe pod` decía que no podía conectar. Desde un pod de diagnóstico, `nslookup` resolvía el ACR a una **IP pública**.
- **Causa:** la zona `privatelink.azurecr.io` no estaba enlazada a la VNet del clúster.
- **Solución:** crear el enlace de la zona a la VNet.
- **Lección:** DNS primero.

## Caso 2 · "El API devuelve 504 solo en campaña"
- **Problema:** en picos fallaban llamadas a un proveedor de pagos por timeout.
- **Pistas:** la métrica de **SNAT** del balanceador de salida mostraba puertos agotados; el resto sano.
- **Causa:** muchas conexiones nuevas desde pocas IP de salida.
- **Solución:** NAT Gateway con más IP públicas y pool de conexiones HTTP en la aplicación.
- **Lección:** los problemas de capacidad se ven como timeouts "intermitentes".

## Caso 3 · "Los pods no ven el sistema de inventario"
- **Problema:** una aplicación en AKS no llegaba a `10.0.5.20` de la sede central, aunque la VPN estaba arriba.
- **Pistas:** otras IP de la sede sí respondían.
- **Causa:** el `service-cidr` por defecto de AKS (`10.0.0.0/16`) **cubría** esa dirección.
- **Solución:** recrear el clúster con un `service-cidr` que no se solape.
- **Lección:** planifica los rangos de Kubernetes igual que los de la VNet.

## Caso 4 · "No puedo hacer `kubectl` desde mi casa"
- **Problema:** tras crear un clúster privado, ningún desarrollador podía usar `kubectl`.
- **Causa:** el API server solo tenía IP privada.
- **Solución:** una VM de salto con Bastion para el equipo y `az aks command invoke` para tareas puntuales; más adelante VPN con DNS correcto.
- **Lección:** privado significa que debes **planear cómo entras**.

## Caso 5 · "403 en Storage, pero la red está bien"
- **Problema:** una función recibía 403 al leer blobs por Private Endpoint.
- **Pistas:** `nslookup` daba IP privada, `nc -zv` conectaba. Es decir, ruta, DNS y puerto estaban bien.
- **Causa:** a la identidad de la función le faltaba el rol **Storage Blob Data Reader**.
- **Solución:** asignar el rol.
- **Lección:** si responde 403, la red ya funcionó; revisa identidad.

## Caso 6 · "Funcionaba ayer"
- **Problema:** un servicio dejó de conectar con la base de datos.
- **Método:** nadie sabía qué había cambiado. El *Activity Log* mostró que una política de red había añadido una regla Deny de salida en la subnet esa mañana.
- **Solución:** corregir la regla y registrar los cambios por IaC.
- **Lección:** el primer escalón es "¿qué cambió?".
