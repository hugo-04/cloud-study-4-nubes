# Oracle OCI · Red · VCN y subredes · Casos reales

## 1. El CIDR que no se podía conectar
**Qué pasó:** al crear el peering con la red de la oficina de ModaLima, la conexión fue imposible.
**Causa:** ambas redes usaban `10.0.0.0/16`.
**Arreglo:** renumerar la VCN (recrear) con un plan de CIDR único.
**Lección:** el plan de direcciones se hace antes del primer recurso.

## 2. Los pods que se quedaron sin IP
**Qué pasó:** OKE dejó de crear pods con «no hay IP disponibles» en una subred `/26`.
**Causa:** con red de pods nativa cada pod usa una IP de la subred; se agotaron al escalar.
**Arreglo:** subred de pods `/22` y límites de réplicas.
**Lección:** dimensiona por pods, no por nodos.

## 3. La base de datos con IP pública
**Qué pasó:** una auditoría encontró la base accesible desde Internet.
**Causa:** subred pública «por rapidez» y lista de seguridad abierta.
**Arreglo:** subred privada, ruta solo local y NSG que admite solo a la aplicación.
**Lección:** pública solo el balanceador.

## 4. Salida a Internet que cobraba de más
**Qué pasó:** el costo de salida subió por descargas de Object Storage.
**Causa:** el tráfico hacia Object Storage salía por la NAT hacia Internet.
**Arreglo:** Service Gateway y ruta al CIDR del servicio.
**Lección:** a los servicios de Oracle se llega por la puerta de servicio.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Peering imposible | CIDR solapados | Plan único |
| 2 | Pods sin IP | Subred pequeña | `/22` + límites |
| 3 | Base expuesta | Subred pública | Privada + NSG |
| 4 | Salida cara | Sin Service Gateway | Ruta al servicio |
