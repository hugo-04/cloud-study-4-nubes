# AWS · SG, NACL, rutas y NAT · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. «Abrimos el 5432 un ratito»
**Qué pasó:** para depurar, alguien abrió la base a `0.0.0.0/0` y se olvidó. En horas había intentos de fuerza bruta. **Solución:** regla de AWS Config + revisión en el pipeline que rechaza `0.0.0.0/0` en puertos que no sean 80/443; acceso a datos solo por referencia a SG. **Lección:** lo temporal se queda para siempre.

## 2. La NACL que rompió las respuestas
**Qué pasó:** tras añadir una NACL «más segura», las llamadas empezaron a colgarse. **Causa:** permitía el 443 de entrada pero no los puertos efímeros de salida (sin estado). **Solución:** regla de salida `1024–65535`. **Lección:** la NACL no recuerda; la ida y la vuelta se declaran.

## 3. Una regla, 40 IP
**Qué pasó:** los 12 grupos de seguridad repetían los CIDR de un proveedor; al cambiar uno, se olvidaron tres. **Solución:** lista de prefijos compartida. **Lección:** nombra los conjuntos.

## 4. El NAT que se agotó
**Qué pasó:** una tarea que llama a una API de terceros empezó a fallar con timeouts intermitentes. **Causa:** miles de conexiones nuevas a la misma IP:puerto por una sola IP de NAT (puertos de origen agotados; métrica `ErrorPortAllocation`). **Solución:** reutilizar conexiones (pool), repartir en varios NAT/IP y consultar el límite vigente. **Lección:** el NAT también tiene límites de conexiones.

## 5. SG que apuntaba a un CIDR que cambió
**Qué pasó:** al migrar la app a otras subredes, la base la rechazó. **Causa:** el SG de datos permitía el CIDR antiguo. **Solución:** referencia a SG. **Lección:** referencia identidades, no ubicaciones.

## 6. 300 grupos huérfanos
**Qué pasó:** nadie sabía cuáles se podían borrar; el límite de SG por ENI estaba cerca. **Solución:** etiquetas obligatorias, regla de Config de SG sin uso y limpieza trimestral. **Lección:** el orden también es seguridad.

| Problema | Solución |
|---|---|
| Puertos abiertos «temporales» | Config + revisión en pipeline |
| NACL sin retorno | Puertos efímeros |
| CIDR repetidos | Lista de prefijos |
| NAT agotado | Pool + más IP |
| CIDR en el SG | Referencia entre SG |
| SG huérfanos | Etiquetas + limpieza |
