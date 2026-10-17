# Oracle OCI · Ingress y API · WAF · Casos reales

## 1. El comentario con apóstrofe
**Qué pasó:** las reseñas de ModaLima que contenían «l'Oréal» devolvían 403.
**Causa:** la protección de inyección SQL marcaba el apóstrofe del campo `comentario`.
**Arreglo:** exclusión de ese argumento solo en la ruta de reseñas; validación y consultas parametrizadas en la app.
**Lección:** ajusta en `CHECK` antes de bloquear y excluye con precisión.

## 2. El WAF esquivado
**Qué pasó:** un escáner atacaba directo a una IP del backend sin pasar por el WAF.
**Causa:** el backend tenía IP pública y NSG abierto.
**Arreglo:** backend sin IP pública y NSG solo desde el LB.
**Lección:** el WAF solo protege lo que pasa por él.

## 3. Credenciales al por mayor
**Qué pasó:** miles de intentos de inicio de sesión por minuto contra Café Andino.
**Causa:** sin límite de tasa en `/login`.
**Arreglo:** 10 intentos por minuto por IP con castigo de 5 minutos, más bloqueo progresivo por cuenta en la app.
**Lección:** combina el límite del WAF con defensas de la aplicación.

## 4. El bloqueo de los repartidores
**Qué pasó:** la app de repartidores, detrás de una NAT de la operadora, recibía 429.
**Causa:** muchos usuarios legítimos compartían una IP pública.
**Arreglo:** límite separado y más alto para la ruta de la app autenticada.
**Lección:** la IP no siempre es una persona.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | 403 legítimos | Falso positivo | Exclusión precisa |
| 2 | Ataques directos | Backend expuesto | Solo desde el LB |
| 3 | Fuerza bruta | Sin tasa | Límite + defensa en app |
| 4 | 429 masivos | NAT compartida | Límites por ruta |
