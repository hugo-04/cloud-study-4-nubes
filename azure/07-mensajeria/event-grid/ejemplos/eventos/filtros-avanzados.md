# Filtros avanzados de Event Grid: recetario

Los filtros se evalúan sobre el evento en el servicio: lo que no coincide **no se entrega ni se cobra la entrega**. Claves: `subject`, `id`, `type`, `source`, `data.<campo>` (CloudEvents) o `eventType`/`data.<campo>` (esquema de Event Grid). *Verifica operadores y límites en la doc vigente.*

| Necesidad | Operador | Clave | Valores |
|---|---|---|---|
| Solo Perú y Chile | `StringIn` | `data.region` | `PE`, `CL` |
| Todo menos pruebas | `StringNotIn` | `data.entorno` | `test`, `qa` |
| Pedidos grandes | `NumberGreaterThan` | `data.total` | `100` |
| Rango de montos | `NumberInRange` | `data.total` | `[[100, 1000]]` |
| Solo CSV | `StringEndsWith` | `subject` | `.csv` |
| Solo de una carpeta | `StringBeginsWith` | `subject` | `pedidos/PE/` |
| El campo debe existir | `IsNotNull` | `data.pagoId` | — |
| El campo no debe existir | `IsNullOrUndefined` | `data.anulado` | — |
| Contiene una palabra | `StringContains` | `data.canal` | `web`, `app` |
| Verdadero/falso | `BoolEquals` | `data.esVip` | `true` |

## Con la CLI
```bash
az eventgrid event-subscription create --name vip-peru --source-resource-id "$TOPICO_ID" \
  --endpoint-type servicebusqueue --endpoint "$COLA_ID" \
  --advanced-filter data.region StringIn PE CL \
  --advanced-filter data.esVip BoolEquals true \
  --advanced-filter data.total NumberGreaterThan 500
```
Todos los filtros avanzados se combinan con **AND**; los valores de un mismo filtro, con **OR**.

## Cuándo filtrar en Event Grid y cuándo en el consumidor
| Filtra en Event Grid | Filtra en el consumidor |
|---|---|
| Criterios simples sobre campos del evento | Reglas de negocio que consultan otros datos |
| Reducir tráfico y costo | Cuando el criterio cambia a diario |
| Aislar equipos por tipo/prefijo | Cuando necesitas auditar lo descartado |
