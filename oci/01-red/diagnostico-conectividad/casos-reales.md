# Oracle OCI · Red · Diagnóstico de conectividad · Casos reales

## 1. «Es la red» (y no lo era)
**Qué pasó:** pedidos fallaban con 403 al leer Object Storage y se culpó a la red.
**Causa:** el grupo dinámico no incluía los nodos nuevos.
**Arreglo:** corregir la regla del grupo dinámico.
**Lección:** un 403 es de identidad; la red estaba bien.

## 2. El timeout que era una ruta
**Qué pasó:** una subred nueva no llegaba a la base.
**Causa:** usaba la tabla de rutas por defecto, sin ruta al Service Gateway.
**Arreglo:** asociar la tabla correcta.
**Lección:** Network Path Analyzer lo mostró en un minuto.

## 3. Rechazada, no bloqueada
**Qué pasó:** «connection refused» a un servicio interno.
**Causa:** el proceso escuchaba solo en `127.0.0.1`.
**Arreglo:** escuchar en `0.0.0.0`.
**Lección:** rechazo inmediato = la red funciona.

## 4. Fallos solo a las 9:00
**Qué pasó:** errores intermitentes de salida cada mañana.
**Causa:** pico de conexiones nuevas agotaba los puertos de la NAT.
**Arreglo:** reutilizar conexiones y más NAT.
**Lección:** lo intermitente suele ser saturación.

## Resumen
| # | Síntoma | Causa | Escalón |
|---|---|---|---|
| 1 | 403 | Grupo dinámico | 6 Identidad |
| 2 | Timeout | Sin ruta al SGW | 2 Ruta |
| 3 | Rechazada | Escucha solo en loopback | 4 Servicio |
| 4 | Intermitente | Puertos NAT | Saturación |
