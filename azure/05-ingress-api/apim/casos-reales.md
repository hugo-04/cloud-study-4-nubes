# Azure · APIM · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar.)

## Caso 1 · API para un socio comercial
- **Problema:** un distribuidor necesitaba consultar stock; no se quería dar acceso directo al backend.
- **Solución:** un **producto** "Socios Retail" con suscripción propia, límite de 100 llamadas por minuto, cuota mensual y solo operaciones de lectura.
- **Resultado:** acceso controlado y medible; si abusa, se revoca solo su clave.
- **Lección:** APIM convierte "tu backend" en "un producto con reglas".

## Caso 2 · Versión 2 sin romper la 1
- **Problema:** cambiar el formato de la respuesta de pedidos rompería la app móvil antigua.
- **Solución:** `/v2/pedidos` nueva y `/v1` marcada como obsoleta con fecha de retiro; cabecera `Deprecation`/`Sunset` desde una política.
- **Lección:** el contrato de una API es una promesa.

## Caso 3 · 401 que "no tenía sentido"
- **Problema:** `validate-jwt` rechazaba tokens válidos de Entra ID.
- **Causa:** la audiencia configurada era `api://modalima-pedidos` pero el token v1 traía el GUID de la app (`aud`) y emisor `sts.windows.net`.
- **Solución:** unificar la versión del token (`accessTokenAcceptedVersion = 2` en el registro de la API) y lista de audiencias/emisores correcta.
- **Lección:** decodifica el token (jwt.ms) y compara `aud`, `iss` y `ver` con la política.

## Caso 4 · Límite por IP que bloqueaba a todos
- **Problema:** `rate-limit-by-key` por IP devolvía 429 a todos los usuarios.
- **Causa:** APIM estaba detrás de Application Gateway; `context.Request.IpAddress` era siempre la IP del gateway.
- **Solución:** usar la IP de `X-Forwarded-For` (primera, sin puerto) o, mejor, la clave por **suscripción o `sub`/`appid` del JWT**.
- **Lección:** el límite se hace sobre quien se quiere medir, no sobre la IP del último salto.

## Caso 5 · 504 al backend en AKS
- **Problema:** APIM (modo interno) devolvía 504; el backend funcionaba desde un pod.
- **Causa:** el NSG de la subred del balanceador interno de AKS no permitía la subred de APIM; además, el DNS interno no resolvía.
- **Solución:** regla NSG, zona privada con el registro del balanceador y *timeout* explícito.
- **Lección:** 504 de APIM = alcanzabilidad o lentitud del backend; aplica la [escalera RPDSI](../../01-red/diagnostico-conectividad/README.md).

## Caso 6 · Lógica de negocio en XML
- **Problema:** una política de 400 líneas calculaba descuentos y era imposible de probar.
- **Solución:** mover el cálculo al microservicio; APIM quedó solo con seguridad, límites y transformaciones simples.
- **Lección:** las políticas son infraestructura, no dominio.

## Caso 7 · Secreto rotado que rompió la integración
- **Problema:** tras rotar la clave del proveedor, APIM seguía usando la anterior.
- **Causa:** el named value secreto se leía de Key Vault con una **versión fija**.
- **Solución:** referencia al secreto **sin versión** (APIM la refresca periódicamente) y alerta de errores.
- **Lección:** referencia sin versión para rotar sin despliegue.

## Caso 8 · Capacidad al 95 %
- **Problema:** lentitud generalizada en horas pico.
- **Causa:** tier Developer en un entorno que se había "promovido" a producción.
- **Solución:** migrar a Premium/Standard v2 con autoescala y alertar la métrica de capacidad al 70 %.
- **Lección:** el tier es una decisión de arquitectura, no de presupuesto inicial.

## Caso 9 · `terraform apply` falla: "nombre ya existe"
- **Problema:** se destruyó y recreó APIM con el mismo nombre; falló.
- **Causa:** **soft-delete**: el recurso borrado seguía reservado.
- **Solución:** purgar el APIM eliminado o usar otro nombre; en Terraform, configurar el comportamiento de purga.
- **Lección:** los recursos con soft-delete retienen su nombre.

## Caso 10 · Reintentos que duplicaron pedidos
- **Problema:** una política `retry` sobre `POST /pedidos` creó pedidos duplicados cuando el backend tardó.
- **Solución:** quitar el reintento de POST; añadir cabecera `Idempotency-Key` y deduplicación en el backend.
- **Lección:** reintenta solo operaciones idempotentes, o hazlas idempotentes.

## Caso 11 · Rastreo abierto en producción
- **Problema:** un tercero usó `Ocp-Apim-Trace` y vio cabeceras internas y rutas del backend.
- **Solución:** desactivar el rastreo para suscripciones no administrativas; revisar qué se expone en el cuerpo de error.
- **Lección:** los diagnósticos son para tu equipo, no para tus clientes.

## Caso 12 · Gateway autoalojado para una tienda sin buena conexión
- **Problema:** el POS de tiendas con red inestable necesitaba el catálogo con latencia baja.
- **Solución:** gateway autoalojado en el clúster local de la tienda con caché, sincronizado con el plano de administración.
- **Lección:** el plano de datos puede acercarse al cliente sin perder la gestión central.
