# Reglas de suscripción (filtros) en Service Bus

Cada suscripción de un tópico es una **cola virtual con sus propias reglas**. Un mensaje se copia a la suscripción **si coincide con al menos una regla** (las reglas se combinan con **OR**). Al crear una suscripción, el servicio añade la regla `$Default` con filtro "todo" (`1=1`): si quieres filtrar, **bórrala o reemplázala**, o recibirás todo.

## Tipos de filtro

| Tipo | Qué evalúa | Costo | Ejemplo |
|---|---|---|---|
| **Booleano** | `TrueFilter` (todo) / `FalseFilter` (nada) | Mínimo | Pausar una suscripción con `FalseFilter` |
| **Correlación** | Igualdad con propiedades del sistema y de aplicación (`Label/Subject`, `CorrelationId`, `ContentType`, `To`, `ReplyTo`, `SessionId`, propiedades propias) | **Bajo (rápido)** | `Label = 'pedido.pagado'` |
| **SQL** | Expresión sobre propiedades (`=`, `<>`, `<`, `>`, `AND`, `OR`, `IN`, `LIKE`, `EXISTS`, funciones) | Mayor | `region = 'PE' AND total > 100` |

Los filtros miran **propiedades**, no el cuerpo del mensaje: el productor debe **copiar al encabezado** lo que haga falta filtrar (`region`, `total`, tipo).

## Acciones de regla (SQL)
Una regla puede modificar propiedades del mensaje copiado:

```sql
-- Filtro
region = 'PE'
-- Acción
SET prioridad = 'alta'; SET sys.Label = 'pedido.local'
```

## Patrones

| Necesidad | Diseño |
|---|---|
| Cada equipo recibe solo sus eventos | Una suscripción por equipo con filtro de correlación por tipo |
| Auditoría de todo | Suscripción con `$Default` (todo) y auto-forward a una cola |
| Segmentar por región o monto | Filtros SQL |
| Pausar un consumidor sin perder mensajes | Cambiar a `FalseFilter` (deja de copiarse) o detener el procesador (los mensajes esperan en la suscripción) |
| Priorizar | Suscripciones/colas distintas por prioridad y más consumidores en la alta |

## Errores típicos
| Síntoma | Causa |
|---|---|
| La suscripción recibe todo | Quedó la regla `$Default` |
| No llega nada | El filtro mira una propiedad que el productor no puso o con otro tipo (`total` como texto) |
| Filtro SQL falla y los mensajes desaparecen | Error de evaluación: usa `dead_lettering_on_filter_evaluation_error = true` para verlos |
| Cambios de regla "no tienen efecto" | Aplica a mensajes **nuevos**; los ya copiados no se reevalúan |
| Rendimiento bajo con miles de reglas | Prefiere filtros de correlación y menos reglas por suscripción |
