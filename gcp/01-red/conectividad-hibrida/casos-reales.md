# Google Cloud · Red · Conectividad · Casos reales

## 1. El peering que no llegaba a la oficina
**Qué pasó:** la VPC de analítica, emparejada con la de tienda, no alcanzaba la oficina conectada por VPN a tienda.
**Causa:** peering no transitivo y rutas personalizadas sin exportar/importar.
**Arreglo:** exportar rutas personalizadas en tienda e importarlas en analítica (o Shared VPC).
**Lección:** el peering no reenvía rutas aprendidas salvo que lo pidas.

## 2. La región sorda
**Qué pasó:** solo las VMs de una región veían la red de la oficina.
**Causa:** modo de enrutamiento `REGIONAL`.
**Arreglo:** cambiar a `GLOBAL`.
**Lección:** revisa el modo de enrutamiento con varias regiones.

## 3. El túnel único
**Qué pasó:** un mantenimiento del proveedor de Internet cortó la conexión con la planta de Café Andino durante horas.
**Causa:** VPN clásica con un túnel.
**Arreglo:** HA VPN con dos túneles y BGP.
**Lección:** redundancia desde el diseño.

## 4. El anuncio por defecto
**Qué pasó:** todo el tráfico a Internet empezó a salir por la oficina.
**Causa:** el router local anunció `0.0.0.0/0` por BGP.
**Arreglo:** filtros de anuncios y prioridad de rutas.
**Lección:** controla qué aceptas por BGP.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Sin tránsito | Peering no transitivo | Exportar/importar o Shared VPC |
| 2 | Una región sin rutas | Modo regional | `GLOBAL` |
| 3 | Corte total | Un túnel | HA VPN |
| 4 | Salida por la oficina | Anuncio 0/0 | Filtros BGP |
