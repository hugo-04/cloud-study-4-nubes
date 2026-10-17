# Oracle OCI · Red · Service Gateway, endpoints privados y DNS privado · Casos reales

## 1. Resolvía en mi laptop, no en el pod
**Qué pasó:** `pedidos-db` funcionaba desde la laptop (VPN) pero no en OKE.
**Causa:** la vista privada no estaba asociada al resolutor de la VCN de OKE.
**Arreglo:** asociar la vista y probar desde un pod.
**Lección:** la prueba de DNS se hace donde corre la aplicación.

## 2. Objeto grande, factura grande
**Qué pasó:** costo de salida alto tras cargas de reportes.
**Causa:** sin Service Gateway; el tráfico a Object Storage salía por NAT.
**Arreglo:** gateway y ruta al CIDR del servicio.
**Lección:** a los servicios de Oracle se va por el pasillo.

## 3. El endpoint que resolvía a una IP pública
**Qué pasó:** la base «privada» aceptaba conexiones desde fuera de la VCN.
**Causa:** la aplicación usaba el FQDN público; el privado nunca se resolvía.
**Arreglo:** usar el FQDN privado documentado y cerrar el acceso público.
**Lección:** privada la ruta **y** el nombre.

## 4. Conflicto de zonas con on-premises
**Qué pasó:** las consultas a `corp.interno` fallaban desde OCI.
**Causa:** faltaba la regla del endpoint de reenvío hacia el DNS de la oficina.
**Arreglo:** regla de reenvío por dominio.
**Lección:** define qué DNS manda en cada dominio.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | No resuelve en el pod | Vista sin asociar | Asociar al resolutor |
| 2 | Costo de salida alto | Sin Service Gateway | Gateway + ruta |
| 3 | «Privada» pero pública | FQDN equivocado | FQDN privado |
| 4 | Dominio corporativo falla | Sin reenvío | Regla de reenvío |
