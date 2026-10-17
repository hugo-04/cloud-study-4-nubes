# Oracle OCI · 09 Gobierno

¿Cómo mantengo ordenado, seguro y pagable un tenancy con muchos equipos? Estructura, vigilancia, evidencia y dinero.

| Unidad | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Compartimentos, etiquetas y cuotas](compartimentos-etiquetas/README.md) | ¿Dónde vive cada cosa, de quién es y cuánto puede crecer? | Pisos, etiquetas en muebles y topes por piso | Estructura, costos por dueño, topes |
| [Cloud Guard y Security Zones](cloud-guard-security-zones/README.md) | ¿Qué está mal configurado y cómo lo impido? | El guardia nocturno y la cerradura | Postura de seguridad |
| [Audit](audit/README.md) | ¿Quién hizo qué y cuándo? | El libro de visitas con cámaras | Forense, cumplimiento, detección |
| [Presupuestos y costos](budgets-costos/README.md) | ¿Cuánto gasto y me voy a pasar? | La app del banco con presupuestos | Alertas, showback |

## Árbol de decisión: «quiero…»

```
¿Separar equipos/entornos y sus permisos?            → Compartimentos (2–3 niveles)
¿Saber de quién es cada recurso y cuánto cuesta?     → Etiquetas definidas obligatorias (de costo)
¿Impedir que un compartimento cree X o más de N?     → Cuotas
¿Detectar configuraciones riesgosas en todo el tenancy? → Cloud Guard (y corregir lo obvio)
¿Impedir de raíz configuraciones prohibidas en prod?  → Security Zones
¿Saber quién cambió algo?                             → Audit (+ copia a Object Storage)
¿Enterarme antes de pasarme del presupuesto?          → Presupuesto con alerta proyectada
```

## Comparativa

| Característica | Compartimentos/etiquetas/cuotas | Cloud Guard / Security Zones | Audit | Presupuestos |
|---|---|---|---|---|
| **Tipo de control** | Estructural / preventivo (cuotas) | Detectivo / correctivo / preventivo | Evidencia | Aviso |
| **Actúa** | Al crear recursos | Continuamente / al crear | Siempre | Periódicamente |
| **Costo** | Sin cargo | Sin cargo | Sin cargo (la copia sí) | Sin cargo |
| **Error típico** | Etiquetas libres | Problemas sin dueño | Retención corta | Creer que frena el gasto |

## La receta ModaLima
| Necesidad | Pieza | Por qué |
|---|---|---|
| Separar prod/no-prod por producto | Compartimentos `modalima/prod`, `modalima/no-prod` | Políticas heredadas claras |
| Gasto por producto | Etiqueta `Gobierno.centro_costo` obligatoria y de costo | Showback |
| No-prod sin GPU | Cuota `zero gpu-family` | Tope duro |
| Bucket público jamás | Cloud Guard con corrección + Security Zone en prod | Detectar y prevenir |
| Cumplimiento 7 años | Audit → Object Storage con retención | Evidencia |
| Aviso de sobrecosto | Presupuesto proyectado + reporte por servicio | Reaccionar a tiempo |

## Orden recomendado de adopción
1. Compartimentos y espacio de etiquetas como código (landing zone).
2. Etiquetas obligatorias y cuotas en no-prod.
3. Cloud Guard en la raíz con triaje y SLA.
4. Audit con retención máxima y copia.
5. Presupuestos por producto con alertas proyectadas.
6. Security Zones en prod.

## Reglas transversales
- Nadie trabaja en la raíz del tenancy.
- Todo cambio de gobierno pasa por código y revisión.
- Excepciones con motivo, dueño y vencimiento.
- Identidades nominales para que Audit tenga sentido.
- Prevenir donde se pueda, detectar en todo lo demás.

## Java en gobierno: qué construye cada `uso-en-java.md`
| Unidad | Qué construyes | Patrón común |
|---|---|---|
| Compartimentos y etiquetas | Revisor de etiquetas obligatorias y profundidad | Paginación + reglas puras |
| Cloud Guard | Triaje con SLA por riesgo | Reloj inyectable |
| Audit | Detector de operaciones sensibles fuera de horario/IP | Zona horaria explícita |
| Costos | Proyección de cierre por servicio | Fechas en UTC |

## Cómo se relaciona con otros capítulos
- [Fundamentos](../00-fundamentos/README.md): tenancy, regiones y costos.
- [IAM](../02-iam/README.md): políticas por compartimento.
- [Mensajería](../07-mensajeria/README.md): Events y Notifications para alertas.
- [Terraform](../10-terraform/README.md): todo esto como código.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos, troubleshooting, repaso y prompt de NotebookLM.
