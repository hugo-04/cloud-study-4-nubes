# Google Cloud · Red · Firewall, rutas y Cloud NAT · Casos reales

## 1. El SSH abierto heredado
**Qué pasó:** un escáner encontró el puerto 22 abierto en VMs de prueba de ModaLima.
**Causa:** la red `default` con `default-allow-ssh` desde `0.0.0.0/0`.
**Arreglo:** borrar la red `default`, política jerárquica que deniega 22/3389 desde Internet e IAP para administrar.
**Lección:** prohíbe arriba lo que nunca debe pasar abajo.

## 2. La etiqueta que abrió la base
**Qué pasó:** alguien agregó la etiqueta `db` a su VM y obtuvo acceso al puerto de la base.
**Causa:** reglas por etiqueta de red.
**Arreglo:** reglas por cuenta de servicio.
**Lección:** las identidades son más difíciles de falsificar que las etiquetas.

## 3. Pagos que fallaban al azar
**Qué pasó:** el 3 % de las llamadas a la pasarela de pagos de Café Andino fallaban en horas punta.
**Causa:** Cloud NAT con pocos puertos por VM; se agotaban.
**Arreglo:** más puertos por VM, asignación dinámica y alerta de `OUT_OF_RESOURCES`.
**Lección:** NAT también se dimensiona.

## 4. La IP que cambió
**Qué pasó:** el proveedor de pagos bloqueó a la tienda tras un cambio de NAT.
**Causa:** IPs de NAT automáticas.
**Arreglo:** IPs reservadas declaradas al proveedor.
**Lección:** si alguien te tiene en lista blanca, reserva la IP.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Puerto expuesto | Red `default` | Política jerárquica + IAP |
| 2 | Acceso indebido | Regla por etiqueta | Por cuenta de servicio |
| 3 | Fallos intermitentes | Puertos NAT agotados | Más puertos + alerta |
| 4 | Bloqueo del proveedor | IP NAT cambiante | IP reservada |
