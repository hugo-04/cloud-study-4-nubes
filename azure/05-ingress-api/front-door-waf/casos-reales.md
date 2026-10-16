# Azure · Front Door · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar.)

## Caso 1 · App móvil en tres países
- **Problema:** usuarios de Perú, Colombia y Chile notaban lentitud; el backend estaba solo en EE. UU.
- **Solución:** Front Door con POP cercano, TLS en el borde, conexión optimizada hacia el origen; segundo origen en Brasil como respaldo.
- **Resultado:** el handshake TLS ocurre cerca del usuario; la latencia percibida bajó y se ganó failover.
- **Lección:** Front Door acerca el *primer salto*, no mueve tu base de datos.

## Caso 2 · El origen "escondido" que no lo estaba
- **Problema:** el WAF registraba poco, pero la app recibía ataques.
- **Causa:** los atacantes llamaban directo a `miapp.azurewebsites.net`, saltándose Front Door.
- **Solución:** restricciones de acceso por etiqueta `AzureFrontDoor.Backend` **y** validación de `X-Azure-FDID`; después, Private Link en Premium.
- **Lección:** un WAF delante de un origen abierto es una puerta con candado y una ventana abierta.

## Caso 3 · Precios obsoletos en caché
- **Problema:** un cliente veía precios de ayer en el catálogo.
- **Causa:** la ruta `/api/catalogo/*` estaba cacheada con TTL de 1 hora tras el despliegue.
- **Solución:** `Cache-Control: no-cache` para la API, caché solo para `/img/*` y `/static/*`; purga `/*` tras cada despliegue estático.
- **Lección:** cachear APIs dinámicas es un riesgo; cachea por ruta, no por perfil.

## Caso 4 · 504 a los 60 segundos
- **Problema:** exportaciones grandes fallaban con 504.
- **Causa:** tiempo de espera de respuesta del origen.
- **Solución:** patrón `202 Accepted` + estado, con descarga por SAS.
- **Lección:** no estires el tiempo de espera; rediseña la operación larga.

## Caso 5 · Dominio que no valida
- **Problema:** el dominio personalizado quedaba en "Pendiente".
- **Causa:** faltaba el TXT `_dnsauth.api` o el CNAME apuntaba a otro sitio; en el apex el DNS no admitía CNAME.
- **Solución:** crear el TXT correcto; usar registro alias/ANAME para el apex.
- **Lección:** la validación de dominio es DNS puro; verifica con `nslookup -type=txt`.

## Caso 6 · Sondas que tumban la base de datos
- **Problema:** la CPU del origen subía cada minuto sin tráfico.
- **Causa:** la sonda llamaba a `/health` que consultaba la BD, y cientos de POP la ejecutaban cada 30 s.
- **Solución:** sonda `HEAD /livez` ligera; intervalo mayor; la salud profunda queda para monitoreo interno.
- **Lección:** multiplica una sonda por el número de POP antes de decidir qué hace.

## Caso 7 · Límite de tasa que bloquea a una oficina
- **Problema:** una empresa cliente con NAT corporativo recibía 429/403 del WAF.
- **Causa:** cientos de usuarios compartían una IP pública y superaban el límite por IP.
- **Solución:** límite por IP más alto para esa ruta, o por clave de API/token en el borde de la aplicación; excepciones controladas.
- **Lección:** la IP no identifica a una persona.

## Caso 8 · Failover real a Brasil
- **Problema:** la región principal tuvo una degradación.
- **Qué pasó:** las sondas fallaron, Front Door sacó el origen de prioridad 1 y envió tráfico al origen de prioridad 2.
- **Resultado:** minutos de errores en lugar de horas; luego, el origen volvió automáticamente.
- **Lección:** el failover debe **probarse** (simula un origen caído); además, la base de datos del respaldo debe estar lista.

## Caso 9 · Migración desde el SKU clásico
- **Problema:** el perfil clásico se acercaba a su retiro.
- **Solución:** migración a Standard/Premium con la herramienta de migración, revisión de reglas y pruebas con un dominio de preproducción.
- **Lección:** los retiros se planifican con meses; revisa avisos del servicio.

## Caso 10 · Subdomain takeover evitado
- **Problema:** una campaña antigua (`promo.modalima.example`) apuntaba a un endpoint de Front Door ya eliminado.
- **Solución:** inventario DNS; borrar el CNAME huérfano y alertar con una política.
- **Lección:** un CNAME colgante es una invitación para que otro reclame tu nombre.
