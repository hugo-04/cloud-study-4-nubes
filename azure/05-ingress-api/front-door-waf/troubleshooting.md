# Azure · Front Door · Troubleshooting

Cada respuesta de Front Door incluye `X-Azure-Ref`. **Guárdalo siempre**: con él puedes encontrar la petición en los logs y abrir un caso de soporte.

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| **503** `Service Unavailable` | No hay orígenes sanos | Log de sondas; estado del origen | Arreglar la sonda/ruta/puerto; revisar el firewall del origen |
| **502** `Bad Gateway` | Fallo de TLS o conexión con el origen | Log de acceso (`originStatus`, error) | Certificado del origen, `certificate name check`, nombre de host |
| **504** `Gateway Timeout` | El origen tarda más que el tiempo de espera | `timeTaken`, tiempo del origen | Optimizar; patrón asíncrono; ajustar tiempo de espera |
| **403** del WAF | Regla gestionada o personalizada | `FrontDoorWebApplicationFirewallLog` | Exclusión puntual; Allow personalizado; ajustar tasa |
| **403** del origen | Restricción de acceso rechaza al Front Door | Configuración de red del origen | Permitir `AzureFrontDoor.Backend` y validar FDID; aprobar Private Link |
| **404** de Front Door | Ninguna ruta coincide con host/ruta | Patrones de la ruta; dominio asociado | Añadir el patrón; asociar el dominio a la ruta |
| **404** del origen | Host de origen incorrecto | `origin host header` | Usar el host que espera el origen |
| Dominio "Pendiente" | TXT `_dnsauth` ausente / CNAME mal | `nslookup -type=TXT _dnsauth.api...` | Crear registros; esperar propagación |
| Certificado gestionado no emite | CNAME no apunta a Front Door o CAA bloquea | `dig CNAME`, `dig CAA` | Corregir DNS; permitir la CA en CAA |
| Contenido viejo / "caché pegada" | Ruta cacheada, TTL largo | Cabecera `x-cache`, `Cache-Control` | Ajustar caché por ruta; **purgar** |
| Contenido personalizado mezclado | Caché sin `Vary`/`private` | Respuestas iguales para usuarios distintos | `Cache-Control: private`/`no-store`; desactivar caché en esa ruta |
| Cambios de configuración no se ven | Propagación en curso | Estado de implementación del endpoint | Esperar unos minutos; verificar con `x-azure-ref` |
| Origen sobrecargado en reposo | Sondas pesadas | Rutas más llamadas en el origen | `HEAD` a ruta ligera; intervalo mayor |
| Failover no ocurre | Sonda siempre OK (ruta superficial) o prioridades iguales | Estado de salud vs. realidad | Sonda representativa; prioridades distintas |
| Failover ocurre sin motivo | Sonda demasiado estricta | Historial de sondas | Ajustar muestras (`successful_samples_required`) |
| Redirección infinita | Origen redirige a HTTPS y Front Door habla HTTP | Cabecera `Location` | Reenviar por HTTPS al origen o `forward-headers` |
| IP del cliente mal leída | `X-Forwarded-For` con varias IPs | Cabecera en el origen | Tomar el primer valor confiable; usar `X-Azure-ClientIP` |
| Acceso directo al origen funciona | No se cerró el origen | `curl` al host del origen | Restricciones + FDID o Private Link |
| Private Link "Pending" | Conexión sin aprobar en el origen | Estado de la conexión privada | Aprobar en el recurso de origen |

## Secuencia recomendada
1. Toma el `X-Azure-Ref` de la respuesta fallida.
2. Busca en `FrontDoorAccessLog` por ese id: ¿qué ruta, qué origen, qué `httpStatusCode`, qué `originStatus`?
3. Si es WAF, `FrontDoorWebApplicationFirewallLog`.
4. Prueba el origen **directo** (desde una red permitida) con el mismo `Host`.
5. Revisa `FrontDoorHealthProbeLog`.
6. Compara DNS: ¿el nombre apunta al endpoint correcto?

KQL de apoyo: [ejemplos/kql/kql-frontdoor.md](ejemplos/kql/kql-frontdoor.md).
