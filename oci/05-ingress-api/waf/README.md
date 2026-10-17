# Oracle OCI · Ingress y API · WAF (Web Application Firewall)

Filtro de capa 7 que inspecciona cada petición HTTP antes de que llegue a tu aplicación: bloquea inyección SQL, XSS y otros ataques conocidos, limita la tasa por cliente y restringe rutas por origen. En OCI se adjunta al **Load Balancer** (WAF regional) o se usa en el borde (WAF de borde).

## 1. Qué es

**Analogía:** el detector de metales a la entrada de un concierto. No sabe quién compró entrada (eso es autenticación), pero detiene a quien trae algo peligroso, y si alguien intenta entrar cien veces por minuto, lo aparta.

```
 Internet ──► Load Balancer ──► [WAF: política]
                                  1. control de acceso (IP, país, ruta, cabeceras)
                                  2. límite de tasa (por IP)
                                  3. protecciones (SQLi, XSS, RCE… reglas tipo OWASP)
                                  └─ acción: ALLOW / CHECK (solo registra) / RETURN_HTTP_RESPONSE (403, 429)
                              ──► backends
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Política WAF** | Acciones + módulos de reglas; reutilizable |
| **Web App Firewall** | La «instalación»: une una política con un Load Balancer |
| **Acciones** | `ALLOW`, `CHECK` (detectar y registrar), `RETURN_HTTP_RESPONSE` (código, cabeceras, cuerpo) |
| **Request access control** | Reglas con condición (JMESPATH) + acción por defecto |
| **Request rate limiting** | Límite por periodo y duración del castigo |
| **Request protection** | Capacidades de protección (conjuntos de reglas versionados), inspección del cuerpo y exclusiones |
| **Network address lists** | Listas de IP/CIDR reutilizables |
| **Registros** | Logging del WAF: qué regla coincidió y qué hizo |

### Orden de evaluación
1. **Control de acceso**: la primera regla que coincide aplica su acción; si es terminal, se detiene.
2. **Límite de tasa**.
3. **Protecciones**: puntuación colaborativa o reglas individuales.
4. Si nada bloquea, la petición pasa al backend (y existen módulos de respuesta).

### Detectar antes de bloquear
Toda política nueva empieza en `CHECK`: observas los registros, agregas **exclusiones** para falsos positivos (por ejemplo, un campo de texto libre) y recién pasas a bloquear.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Tienda o API pública expuesta a Internet | **WAF** sobre el LB |
| Fuerza bruta en el inicio de sesión | Límite de tasa del WAF + bloqueo de cuenta en la app |
| Panel de administración solo desde la oficina | Control de acceso por IP (mejor aún: no exponerlo) |
| Autenticar usuarios | **No**: [API Gateway](../api-gateway/README.md) o la app |
| Tráfico TCP/UDP no HTTP | **No**: no aplica al [NLB](../network-load-balancer/README.md) |
| Reemplazar la validación de entradas | **Nunca**: el WAF es una capa más |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Falso positivo** | Petición legítima bloqueada |
| **Exclusión** | Ignorar un argumento o cookie concreto en una regla |
| **Capacidad de protección** | Conjunto de reglas con clave y versión |
| **Puntuación colaborativa** | Varias reglas suman; se bloquea al superar un umbral |
| **JMESPATH** | Lenguaje de las condiciones (`http.request.url.path`, `connection.source.address`) |

## 5. Cómo se usa
1. Política con acciones, acceso, tasa y protecciones en modo `CHECK`: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf) (`modo_bloqueo = false`).
2. Adjunta al LB y observa los registros dos semanas.
3. Audita que la política cumpla el mínimo (protecciones, tasa, bloqueo) con [Java](uso-en-java.md).
4. Cambia a `modo_bloqueo = true`. CLI: [`ejemplos/cli/waf.sh`](ejemplos/cli/waf.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Seguridad | `manage waf-family` | — |
| Auditoría | `read waf-family` | Registros del WAF |
| Clientes | — | Toda petición pasa por la política |

- Los backends deben aceptar tráfico **solo desde el LB**; si no, el WAF se esquiva.
- Registros sin datos personales innecesarios; retención acotada.
- Revisión de exclusiones: cada una abre un hueco.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Empezar en `CHECK` y ajustar | Bloquear el primer día y romper el checkout |
| Exclusiones precisas (un campo, una ruta) | Desactivar una protección entera |
| Límite de tasa en login, búsqueda y checkout | Un único límite global |
| Versionar la política como código | Cambios a mano en la consola |
| Validar entradas también en la app | Confiar solo en el WAF |

## 8. Límites, costos y versiones
- **Costo:** por instancia de WAF y por millón de peticiones; hay una cuota gratuita mensual *(verifica)*.
- **Límites** (verifica): reglas por política, tamaño de cuerpo inspeccionado, listas de direcciones.
- **Terraform:** `oci_waf_web_app_firewall_policy`, `oci_waf_web_app_firewall`, `oci_waf_network_address_list`.
- **SDK:** `WafClient` (`oci-java-sdk-waf`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
