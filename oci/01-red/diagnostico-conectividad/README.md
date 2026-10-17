# Oracle OCI · Red · Diagnóstico de conectividad

«No conecta» casi siempre es una de seis cosas, y casi siempre en este orden. Este documento es la **escalera de diagnóstico** de OCI: qué comprobar, con qué herramienta y cómo interpretar el síntoma.

## 1. Qué es

**Analogía:** buscar por qué no llegó una carta. ¿Estaba bien la **dirección** (DNS)? ¿Existía la **calle** (ruta)? ¿Dejó pasar el **portero** (reglas de seguridad)? ¿Había **alguien en casa** (el servicio escucha)? ¿Era el **sobre correcto** (TLS)? ¿Tenías **permiso** para entregar (identidad)? Se revisa de la primera a la última y **se para en la primera que falla**.

```
  1 DNS ─► 2 RUTA ─► 3 SEGURIDAD ─► 4 SERVICIO/PUERTO ─► 5 TLS ─► 6 IDENTIDAD
  ¿resuelve  ¿hay      ¿lista de     ¿escucha? timeout   ¿cert.   ¿401/403?
  a la IP    camino?   seguridad/    vs rechazada        válido?  ¿política?
  esperada?            NSG?
```

## 2. Cómo funciona por dentro

### El síntoma te dice el escalón
| Síntoma | Escalón probable |
|---|---|
| `UnknownHostException` / «Name or service not known» | 1 DNS |
| Resuelve a IP pública cuando esperabas privada | 1 DNS (vista privada / FQDN) |
| *Timeout* (sin respuesta) | 2 Ruta o 3 Seguridad |
| *Connection refused* (rechazo inmediato) | 4 Nadie escucha (la red está bien) |
| Error de certificado / `SSLHandshakeException` | 5 TLS |
| 401 / 403 / `NotAuthorizedOrNotFound` | 6 Identidad (la red está bien) |
| Funciona a ratos | NAT/puertos, DNS, saturación, reintentos |

> Un *timeout* nunca es de identidad, y un 403 nunca es de red.

### Herramientas de OCI
| Herramienta | Para qué |
|---|---|
| **Registros de flujo de VCN** (*Flow Logs*, servicio Logging) | Ver si el tráfico llega a la subred y qué se acepta o rechaza |
| **Network Path Analyzer** | Analiza de forma estática el camino origen → destino (rutas, reglas, gateways) y dice dónde se corta |
| **Bastion** | Entrar a recursos privados sin IP pública, con sesiones temporales |
| **Cloud Shell** | Terminal con la CLI; puede conectarse a una red privada |
| **Comandos en el recurso** | `nslookup`, `curl -v`, `openssl s_client`, `nc -zv` |
| **Auditoría (Audit)** | ¿Cambió alguien una regla o ruta hace poco? |
| **Monitoring** | Métricas del balanceador, VNIC y servicios |

### Escalera paso a paso
1. **DNS:** `nslookup nombre`. ¿IP privada esperada? Si no: [vista privada](../endpoints-privados-dns/README.md).
2. **Ruta:** la tabla de rutas de la **subred origen**: ¿hay ruta al destino (gateway, DRG, SGW)? ¿Y la de **vuelta** en el destino?
3. **Seguridad:** lista y NSG del origen (salida) y del destino (entrada), puerto y protocolo; con o sin estado.
4. **Puerto:** `nc -zv ip puerto` desde el origen. Rechazado = el servicio no escucha o escucha en otra interfaz.
5. **TLS:** `openssl s_client -connect nombre:443 -servername nombre`: fecha, cadena y nombre.
6. **Identidad:** la política IAM del principal, el grupo dinámico, el compartimento correcto.

### Para fallos intermitentes
| Sospecha | Cómo verlo |
|---|---|
| Puertos de la NAT agotados | Métricas de la NAT Gateway; reutiliza conexiones |
| DNS lento o con caché | `networkaddress.cache.ttl` en la JVM |
| Reintentos agresivos | Métricas de la aplicación; *backoff* con *jitter* |
| Saturación del balanceador | Métricas de conexiones y 5xx |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| «No conecta» sin más datos | Sube la escalera de 1 a 6 |
| Quieres saber el camino sin generar tráfico | Network Path Analyzer |
| Necesitas ver si el paquete llegó | Registros de flujo |
| Cambiar reglas al azar hasta que funcione | **No** |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Registro de flujo** | Línea por conexión: origen, destino, puerto, acción |
| **Network Path Analyzer** | Calculadora estática del camino |
| **Timeout vs rechazo** | Silencio (se descarta) vs respuesta «no» (nadie escucha) |
| **Ruta de vuelta** | La respuesta también necesita camino |
| **Bastion** | Puerta temporal a recursos privados |

## 5. Cómo se usa
1. Activa **registros de flujo** en las subredes críticas: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Ten a mano el comprobador: [`ejemplos/cli/escalera.sh`](ejemplos/cli/escalera.sh) o el de [Java](uso-en-java.md), y un pod de diagnóstico con la **misma cuenta de servicio** que la app.
3. Sigue la escalera; anota qué escalón falló y qué lo arregló (alimenta el [runbook](../../11-casos-integrados/README.md)).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Guardia (primer nivel) | `read virtual-network-family`, `read logging-family`, `use network-path-analyzer…` *(verifica el verbo vigente)* | — |
| Operaciones | Cambios acotados con aprobación | — |
| Bastion | Sesiones temporales con propósito y caducidad | Acceso al recurso durante la sesión |

- Los registros de flujo contienen direcciones IP: trátalos como datos sensibles.
- El pod de diagnóstico debe tener la **misma identidad** que la aplicación y caducidad automática.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Seguir el orden de la escalera | Cambiar reglas «a ver si funciona» |
| Probar desde el mismo lugar que falla | Probar solo desde tu laptop |
| Mirar **primero** qué cambió (Audit) | Suponer sin evidencia |
| Registros de flujo en subredes críticas | Activarlos recién cuando hay incidente |
| Documentar el hallazgo | Arreglar y olvidar |

## 8. Límites, costos y versiones
- **Costo:** los registros de flujo se cobran como logs (ingesta y almacenamiento); Network Path Analyzer no tiene costo adicional por análisis. *(verifica)*
- **Retención:** define la retención del grupo de logs; costos suben con el volumen.
- **Terraform:** `oci_logging_log_group`, `oci_logging_log` (servicio `flowlogs`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
