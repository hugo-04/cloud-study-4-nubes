# AWS · Diagnóstico de conectividad · Troubleshooting

Esta es la **escalera general** de conectividad. Sube un peldaño cuando el anterior está limpio.

| Peldaño | Pregunta | Herramienta | Si falla, mira |
|---|---|---|---|
| 1 | ¿Resuelve el nombre y a qué IP? | `dig`, `ConnCheck` | DNS privado, zona privada, caché de la JVM |
| 2 | ¿La configuración permite el camino? | Reachability Analyzer | Rutas, SG, NACL, peering/TGW, endpoint |
| 3 | ¿Qué vio la red? | Flow Logs (origen y destino) | `REJECT` → SG/NACL; sin registro en destino → ruta/NACL |
| 4 | ¿Escucha el servicio? | `ss -ltnp`, `nc -vz` | Proceso, puerto, `0.0.0.0` vs `127.0.0.1` |
| 5 | ¿Funciona TLS/HTTP? | `curl -v`, `openssl s_client` | Certificado, SNI, proxy |
| 6 | ¿Falla solo a veces? | Métricas NAT/ALB/TGW, pool | Puertos, idle timeout, capacidad |

## Síntomas puntuales

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| Reachability dice «alcanzable» y falla | Problema de aplicación, DNS o intermitente | Peldaños 1, 4–6 | No es de configuración de red |
| Reachability dice «no alcanzable» | El componente de la explicación | Explicación del análisis | Corregir ese componente y re-analizar |
| Flow Logs sin datos | Destino sin permisos/filtro o aún en retraso | Estado del Flow Log | Política del destino; esperar unos minutos |
| `REJECT` del origen hacia el destino | SG de origen (salida) o SG/NACL de destino | Reglas de ambos | Abrir lo mínimo |
| El destino registra `ACCEPT` y la app no responde | Servicio caído o escucha solo en localhost | `ss -ltnp` | Corregir el enlace del servicio |
| `Connection reset` tras inactividad | Idle timeout del NAT/NLB | Tiempo de inactividad | Vida corta del pool |
| `ErrorPortAllocation` sube | Puertos del NAT agotados | Métrica del NAT | Pool, más IP/NAT |
| No puedo entrar a la máquina por SSM | Rol sin permisos o sin endpoint de SSM | Rol de instancia, endpoints `ssm`, `ssmmessages`, `ec2messages` | Permisos y endpoints |
| ECS Exec no abre sesión | Falta habilitar `enableExecuteCommand` o permisos del rol de tarea | Configuración de la tarea | Habilitarlo y dar permisos de SSM Messages |
| Muchos `REJECT` desconocidos desde internet | Escaneo habitual | Origen y puertos | Es ruido si no hay puertos abiertos; no abras nada |
