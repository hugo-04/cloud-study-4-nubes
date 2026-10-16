# Azure · VNet y Subnets · Casos reales

Todos los casos son inventados con fines de estudio.

## Caso 1 · "Café Andino" y la base de datos expuesta
- **Problema:** una cafetería con pedidos online tenía su base de datos accesible desde internet "porque era más fácil de probar".
- **Solución:** una VNet `10.10.0.0/16` con tres subnets: `snet-web` (10.10.0.0/24), `snet-app` (10.10.1.0/24), `snet-data` (10.10.2.0/24). La base quedó sin IP pública y solo accesible desde `snet-app`.
- **Resultado:** un escaneo externo ya no encontró la base de datos.
- **Lección:** segmenta por capas y niega por defecto entre ellas.

## Caso 2 · El rango que se solapaba
- **Problema:** ModaLima creó `vnet-prod` con `10.0.0.0/16`. Meses después la oficina conectó su red con VPN, y la red de la oficina también era `10.0.0.0/16`.
- **Causa:** nadie había documentado los rangos; se eligió el primero que vino a la mente.
- **Solución:** crear una VNet nueva con `10.20.0.0/16` y migrar los recursos. Tomó dos semanas.
- **Lección:** una hoja de rangos IP compartida evita meses de dolor.

## Caso 3 · Subnet llena durante una campaña
- **Problema:** durante el Cyber Day, el clúster de AKS no podía crear más nodos: "subnet is full".
- **Causa:** `snet-aks` era un `/24` (251 IP) y con el modelo de red clásico cada pod consume una IP de la subnet.
- **Solución:** mover a un modelo de red con **overlay** (los pods no consumen IP de la subnet) y ampliar la subnet.
- **Lección:** dimensiona subnets pensando en el pico, no en el promedio, y elige el modelo de red de AKS con tiempo.

## Caso 4 · La VM que ya no salía a internet
- **Problema:** tras crear una VNet nueva, una VM de pruebas no podía descargar paquetes.
- **Causa:** la subnet era privada por defecto y no había NAT Gateway ni IP pública.
- **Solución:** crear un **NAT Gateway** y asociarlo a la subnet.
- **Lección:** la salida a internet es una decisión explícita; no la des por hecha.
