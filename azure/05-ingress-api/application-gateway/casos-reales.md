# Azure · Application Gateway · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar.)

## Caso 1 · El 502 "misterioso"
- **Problema:** de pronto el gateway devolvía 502 a todos.
- **Pista:** *Backend health* mostraba `Unhealthy`.
- **Causa:** la sonda apuntaba a `/health`; la nueva versión ya solo exponía `/actuator/health`. El backend respondía 404.
- **Solución:** corregir la ruta de la sonda y aceptar solo 200.
- **Lección:** un 502 del gateway casi siempre significa **backend no sano o inalcanzable**; mira primero el *backend health*.

## Caso 2 · App Service que redirige a `azurewebsites.net`
- **Problema:** al entrar por `api.modalima.example`, el navegador acababa en `miapp.azurewebsites.net`.
- **Causa:** el gateway enviaba `Host: api.modalima.example` pero el App Service usaba el nombre por defecto para sus redirecciones y enlaces.
- **Solución:** en la configuración HTTP, tomar el host del backend (`pick_host_name_from_backend_address`) y añadir `X-Forwarded-Host`; en la app, `forward-headers-strategy=framework`.
- **Lección:** decide conscientemente qué `Host` ve el backend.

## Caso 3 · Falso positivo del WAF
- **Problema:** el formulario de comentarios devolvía 403 con ciertos símbolos.
- **Causa:** una regla OWASP bloqueaba el campo `comentario` por puntaje de anomalía.
- **Solución:** revisar `ApplicationGatewayFirewallLog`, **excluir ese argumento** para esa regla y esa ruta, no apagar el WAF.
- **Lección:** Detection → medir → Prevention con excepciones precisas.

## Caso 4 · Gateway atascado en "Updating"
- **Problema:** una modificación del gateway fallaba y el estado quedaba en error.
- **Causa:** alguien endureció el NSG y bloqueó `GatewayManager 65200-65535`.
- **Solución:** reponer las reglas de entrada de infraestructura y reaplicar.
- **Lección:** el NSG de la subred del gateway tiene reglas obligatorias.

## Caso 5 · Certificado vencido un sábado
- **Problema:** el certificado del listener venció y la web dejó de cargar.
- **Causa:** el certificado se había subido a mano (PFX) en el gateway.
- **Solución:** referenciar el certificado de **Key Vault sin versión** con una identidad administrada; alertar 30 días antes.
- **Lección:** la rotación debe ser un efecto de la arquitectura, no una tarea humana.

## Caso 6 · TLS extremo a extremo que no conecta
- **Problema:** con HTTPS hacia el backend, la sonda fallaba: "certificate chain not trusted".
- **Causa:** el backend usaba un certificado de una CA interna.
- **Solución:** cargar el certificado raíz como *trusted root* en las configuraciones HTTP, o usar un certificado de CA pública y validar el nombre (`CN/SAN`).
- **Lección:** TLS extremo a extremo valida cadena **y** nombre.

## Caso 7 · La IP del cliente trae puerto
- **Problema:** el servicio de antifraude fallaba al parsear la IP (`203.0.113.7:51234`).
- **Causa:** Application Gateway añade el puerto en `X-Forwarded-For`.
- **Solución:** normalizar la IP (quitar el puerto) antes de usarla; o una *rewrite rule* que la limpie.
- **Lección:** no asumas el formato de una cabecera; léelo de la documentación y pruébalo.

## Caso 8 · El reporte de 40 segundos
- **Problema:** un reporte pesado devolvía 502/504 a los ~30 s.
- **Causa:** el *timeout* de solicitud del gateway (por defecto 20 s) era menor que el tiempo del reporte.
- **Solución:** patrón asíncrono: el endpoint responde `202 Accepted` con un enlace de estado; el trabajo corre en segundo plano.
- **Lección:** no subas el *timeout* para esconder un diseño síncrono.

## Caso 9 · La factura del gateway
- **Problema:** gateways de pruebas en cada entorno con `min=2` y `max=125` 24/7.
- **Solución:** `max` realista, entornos de desarrollo compartidos o apagados; revisar la métrica de unidades de capacidad.
- **Lección:** el gateway tiene costo fijo y variable: dimensiona con datos.

## Caso 10 · Subida de archivos grande
- **Problema:** un archivo de 200 MB fallaba con 413 antes de llegar a la app.
- **Causa:** límite de cuerpo del WAF/gateway.
- **Solución:** que el cliente suba directo a Blob Storage con una **SAS** emitida por la API ([SAS](../../06-storage/sas-tokens/README.md)).
- **Lección:** los archivos grandes no deben viajar por la aplicación.
