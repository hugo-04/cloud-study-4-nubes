# Oracle OCI · Red · DRG, peering e híbrido · Casos reales

## 1. Dev hablaba con prod
**Qué pasó:** una prueba en dev borró datos de un servicio de prod.
**Causa:** ambas VCN estaban adjuntas a la DRG con la misma tabla de rutas.
**Arreglo:** tablas de rutas separadas: spokes solo ven al hub.
**Lección:** conectar no es lo mismo que permitir.

## 2. El túnel que se caía los lunes
**Qué pasó:** VPN inestable cada lunes por la mañana.
**Causa:** un solo túnel IPSec y el proveedor de Internet de la oficina reiniciaba el router.
**Arreglo:** dos túneles con dispositivos distintos y alarma de estado.
**Lección:** redundancia desde el inicio.

## 3. Ruta de vuelta que faltaba
**Qué pasó:** de on-premises llegaban peticiones pero las respuestas no volvían.
**Causa:** la subred de OCI no tenía ruta a la oficina por la DRG.
**Arreglo:** ruta `192.168.0.0/16` → DRG.
**Lección:** las rutas son de ida **y** de vuelta.

## 4. CIDR solapado con la compra de otra empresa
**Qué pasó:** una adquisición trajo una red `10.30.0.0/16`.
**Causa:** coincidía con la VCN de ModaLima.
**Arreglo:** NAT en un tramo intermedio mientras se renumeraba.
**Lección:** el verificador de solapes debe correr antes de aceptar conexiones.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Dev afecta a prod | Misma tabla de rutas | Tablas por rol |
| 2 | VPN inestable | Un túnel | Dos túneles |
| 3 | Sin respuesta | Falta ruta de vuelta | Ruta a la DRG |
| 4 | CIDR repetido | Sin verificación | Verificador + NAT temporal |
