# Azure · Ingress en AKS · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar.)

## Caso 1 · Doce balanceadores y una factura
- **Problema:** cada servicio exponía su propio `Service type=LoadBalancer`; 12 IP públicas y 12 balanceadores.
- **Solución:** una sola entrada con reglas por host y ruta; los servicios pasaron a `ClusterIP`.
- **Resultado:** una IP, un certificado, un WAF; la factura bajó y la superficie de ataque también.
- **Lección:** el ingress existe para que expongas **una** puerta, no doce.

## Caso 2 · Enlaces `http://` en una API HTTPS
- **Problema:** la API devolvía `Location: http://api.modalima.example/pedidos/42` y los clientes móviles fallaban por HTTPS-only.
- **Causa:** el controlador terminaba el TLS y la app, sin `forward-headers`, creía hablar HTTP.
- **Solución:** `server.forward-headers-strategy=framework` (Spring) / `quarkus.http.proxy.proxy-address-forwarding=true`.
- **Lección:** detrás de un proxy, el framework debe confiar en las cabeceras `X-Forwarded-*` (solo del proxy de confianza).

## Caso 3 · Subida de fotos con 413
- **Problema:** los usuarios no podían subir imágenes de 3 MB.
- **Causa:** el límite de cuerpo del controlador era 1 MB.
- **Solución:** subir el límite **solo** en la ruta `/fotos` (anotación por Ingress), no globalmente.
- **Lección:** los límites son defensa; amplíalos donde hace falta.

## Caso 4 · Notificaciones en vivo que se cortaban cada 4 minutos
- **Problema:** una pantalla con Server-Sent Events se desconectaba sola.
- **Causa:** el balanceador de Azure cerraba conexiones inactivas tras ~4 minutos.
- **Solución:** *heartbeat* cada 30 s desde el servidor y reconexión en el cliente.
- **Lección:** las conexiones largas necesitan latidos menores que el tiempo de inactividad de cada salto.

## Caso 5 · Canary con Gateway API
- **Problema:** liberar `pedidos v2` con riesgo.
- **Solución:** un `HTTPRoute` con `backendRefs` pesados: 90 % `svc-pedidos-v1`, 10 % `svc-pedidos-v2`; monitoreo y subida gradual.
- **Lección:** el reparto por pesos es parte de la API estándar; no necesitas anotaciones propietarias.

## Caso 6 · El controlador que se retira
- **Problema:** el equipo usaba el NGINX de la comunidad y se anunció su retiro.
- **Solución:** inventario de Ingress y anotaciones propietarias; migración a Gateway API con Application Gateway for Containers, servicio por servicio.
- **Lección:** minimiza anotaciones específicas del controlador: reducen el costo de migrar.

## Caso 7 · IP del cliente siempre igual
- **Problema:** el rate limit por IP bloqueaba a todos porque veía la IP de un nodo.
- **Causa:** `externalTrafficPolicy: Cluster` con SNAT; la IP original se perdía.
- **Solución:** `externalTrafficPolicy: Local` y la sonda de salud correcta del balanceador; lectura de `X-Forwarded-For` confiable.
- **Lección:** si tu lógica usa la IP del cliente, asegúrate de que llegue.

## Caso 8 · Panel interno expuesto
- **Problema:** Grafana publicado con un Ingress público "para la demo" quedó semanas.
- **Solución:** Ingress interno + acceso por la red corporativa; política de Azure que prohíbe `LoadBalancer` público fuera del namespace de plataforma.
- **Lección:** lo que se publica "temporalmente" se queda; impónlo con políticas.

## Caso 9 · Certificados que se renuevan solos
- **Problema:** un certificado venció un sábado.
- **Solución:** cert-manager con Let's Encrypt (DNS-01 en Azure DNS con Workload Identity) y alertas de expiración.
- **Lección:** la renovación manual es un incidente esperando ocurrir.
