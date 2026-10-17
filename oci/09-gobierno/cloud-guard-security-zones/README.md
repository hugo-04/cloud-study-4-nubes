# Oracle OCI · Gobierno · Cloud Guard y Security Zones

**Cloud Guard** vigila continuamente tu tenancy: detecta configuraciones riesgosas (bucket público, puerto 22 abierto a Internet, llaves viejas) y actividad sospechosa, y puede **corregir** automáticamente con *responders*. **Security Zones** va un paso antes: **impide** crear recursos que violen reglas en compartimentos protegidos.

## 1. Qué es

**Analogía:** Cloud Guard es el guardia que recorre el edificio de noche y anota ventanas abiertas (y si se lo permites, las cierra). Security Zones es la cerradura de la sala de servidores que ni siquiera deja entrar a quien no cumple las reglas.

```
 Cloud Guard (región de reporte)
   Target: compartimento modalima (y descendientes)
     ├─ Detector de configuración  → "bucket público", "SSH abierto a 0.0.0.0/0" …
     ├─ Detector de actividad      → "política modificada por usuario inusual" …
     ├─ Detector de amenazas       → comportamiento anómalo de usuarios *(verifica)*
     └─ Responder                  → notificar / corregir (hacer privado el bucket)
   Problemas → riesgo CRITICAL/HIGH/MEDIUM/LOW → Events/Notifications

 Security Zone "prod-segura" (receta: sin IP pública en VM, buckets privados, cifrado con CMK…)
   └─ compartimento prod → la API RECHAZA lo que viola la receta
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Target** | Compartimento (y sus hijos) que Cloud Guard vigila, con recetas asociadas |
| **Receta de detector** | Reglas de detección (configuración, actividad, amenazas, instancias) con riesgo y condiciones |
| **Receta de responder** | Acciones: notificar o corregir automáticamente |
| **Problema** | Una detección abierta sobre un recurso, con riesgo, etiquetas y estado |
| **Región de reporte** | Donde se consolidan los problemas de todas las regiones |
| **Security Zone** | Compartimento con una receta de políticas preventivas |
| **Security Zone recipe** | Lista de políticas («deny public buckets», «require CMK»…) |

### Flujo
1. Cloud Guard evalúa recursos periódicamente y escucha eventos.
2. Una regla coincide → se abre un **problema** con riesgo.
3. Si hay *responder* en modo automático, corrige; si no, notifica.
4. Lo resuelves, lo descartas con motivo o se cierra solo cuando el recurso cumple.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Saber si hay buckets públicos o SSH abierto en todo el tenancy | **Cloud Guard** |
| Impedir de raíz VMs con IP pública en prod | **Security Zones** |
| Corregir automáticamente lo obvio (bucket público) | *Responder* automático |
| Analizar logs de aplicación | **No**: Logging Analytics/SIEM |
| Escaneo de vulnerabilidades del SO o imágenes | **No**: Vulnerability Scanning |
| Reemplazar revisiones de diseño | **No**: es una red de seguridad |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Detectivo vs preventivo** | Avisar después vs impedir antes |
| **Riesgo** | Prioridad del problema |
| **Corrección automática** | El *responder* arregla sin intervención |
| **Problema descartado** | Aceptado con justificación (excepción documentada) |
| **Postura de seguridad** | Resumen del estado de cumplimiento |

## 5. Cómo se usa
1. Habilita Cloud Guard, crea el target y una Security Zone para prod: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Prioriza los problemas abiertos con SLA por riesgo: [uso en Java](uso-en-java.md).
3. Consulta problemas: [`ejemplos/cli/cloud-guard.sh`](ejemplos/cli/cloud-guard.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Seguridad | `manage cloud-guard-family`, `manage security-zone` | — |
| Equipos de producto | `read cloud-guard-problems` de su compartimento | — |
| Cloud Guard (servicio) | Política de servicio para leer recursos y corregir | — |

- Empieza con *responders* en **notificar**; automatiza solo correcciones seguras.
- Excepciones (descartes) siempre con motivo y fecha de revisión.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Target en la raíz del tenancy o de cada unidad | Vigilar solo algunos compartimentos |
| SLA por riesgo (CRITICAL 24 h, HIGH 7 días) | Cientos de problemas abiertos sin dueño |
| Security Zone en prod | Confiar solo en la detección |
| Clonar recetas y ajustarlas | Desactivar reglas «ruidosas» sin analizar |
| Problemas → Events → Notifications | Revisar la consola una vez al mes |

## 8. Límites, costos y versiones
- **Costo:** Cloud Guard y Security Zones sin cargo; pagas lo que disparen (notificaciones) *(verifica)*.
- **Límites** (verifica): targets, recetas, reglas personalizadas.
- **Terraform:** `oci_cloud_guard_cloud_guard_configuration`, `oci_cloud_guard_target`, `oci_cloud_guard_detector_recipe`, `oci_cloud_guard_security_recipe`, `oci_cloud_guard_security_zone`.
- **SDK:** `CloudGuardClient` (`oci-java-sdk-cloudguard`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
