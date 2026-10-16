# Azure · AKS · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar.)

## Caso 1 · Quince servicios, un clúster
- **Problema:** 15 microservicios con ciclos de despliegue distintos y necesidad de escalar de forma independiente; en App Service eran 15 planes y una factura difícil de explicar.
- **Solución:** AKS con pools `system` y `user`, HPA por servicio, KEDA para consumidores de cola, ingress interno y APIM delante.
- **Resultado:** despliegues independientes y escalado por servicio; costo por nodo compartido.
- **Lección:** AKS vale la pena cuando la **complejidad ya existe**; antes es un costo.

## Caso 2 · `OOMKilled` con 512 MB de heap
- **Problema:** pods de Spring Boot reiniciados cada pocas horas con `OOMKilled`.
- **Causa:** `limits.memory: 512Mi` y `-Xmx512m`. La JVM usa memoria fuera del heap (metaspace, hilos, buffers directos, código compilado) y superó el límite del contenedor.
- **Solución:** `-XX:MaxRAMPercentage=70`, límite de memoria de 768 Mi y medición real con métricas de la JVM.
- **Lección:** heap ≠ memoria del proceso. Deja margen entre el heap y el límite del contenedor.

## Caso 3 · La latencia p99 y el límite de CPU
- **Problema:** picos de latencia cada pocos segundos sin causa aparente.
- **Causa:** `limits.cpu: 500m` provocaba *throttling* (la JVM y su recolector de basura se "congelaban" al agotar la cuota).
- **Solución:** quitar el límite de CPU (dejando `requests` realistas) y vigilar `container_cpu_cfs_throttled_seconds_total`.
- **Lección:** `requests` de CPU para planificar; el límite de CPU suele hacer más daño que bien a las JVM.

## Caso 4 · La JVM elige el recolector equivocado
- **Problema:** pods de 1 CPU con GC muy pausado.
- **Causa:** con menos de 2 CPU o menos de ~1.8 GB, la JVM elige **SerialGC** por defecto.
- **Solución:** fijar explícitamente el recolector (`-XX:+UseG1GC` o `-XX:+UseParallelGC`) y dimensionar a 2 CPU para servicios de latencia.
- **Lección:** la JVM se autoconfigura según lo que *ve*; en contenedores, eso lo definen los límites.

## Caso 5 · El upgrade que no terminaba
- **Problema:** la actualización de nodos llevaba horas "en progreso".
- **Causa:** un servicio con **1 réplica** y un PDB `minAvailable: 1`: el drenado no podía mover el único pod.
- **Solución:** mínimo 2 réplicas y `maxUnavailable: 1`; los PDB se revisan antes de cada ventana de mantenimiento.
- **Lección:** un PDB imposible bloquea la plataforma.

## Caso 6 · Se acabaron las IP
- **Problema:** `Pending` por falta de direcciones IP al escalar de 20 a 80 pods en AKS con subred /24.
- **Causa:** Azure CNI en modo "subred de nodos": cada pod consume una IP de la VNet.
- **Solución:** migrar a **Azure CNI Overlay**: los pods usan un rango overlay y la subred solo da IP a los nodos.
- **Lección:** el modelo de red se elige al inicio; planifica rangos o usa overlay.

## Caso 7 · 502 durante cada despliegue
- **Problema:** unos segundos de errores en cada *rollout*.
- **Causa:** el pod recibía tráfico mientras ya se apagaba (la actualización de endpoints no es instantánea) y no había apagado ordenado.
- **Solución:** `readinessProbe` real, `preStop: sleep 10`, `terminationGracePeriodSeconds: 45` y `server.shutdown=graceful`.
- **Lección:** apagar bien es tan importante como arrancar bien.

## Caso 8 · Agotamiento de puertos SNAT
- **Problema:** errores intermitentes `Connection timed out` hacia una API externa en horas pico.
- **Causa:** muchas conexiones salientes nuevas por segundo a un mismo destino a través del balanceador del clúster; los puertos SNAT se agotaron.
- **Solución:** **NAT Gateway** para el egreso y *keep-alive*/pool de conexiones en los clientes HTTP.
- **Lección:** reutiliza conexiones y dimensiona el egreso ([NSG, rutas y NAT](../../01-red/nsg-rutas-nat/README.md)).

## Caso 9 · DNS lento por `ndots:5`
- **Problema:** cada llamada a un dominio externo tardaba decenas de ms extra y CoreDNS estaba al 90 % de CPU.
- **Causa:** `ndots:5` hace que un nombre como `api.proveedor.com` se pruebe primero con los sufijos del clúster (varias consultas inútiles).
- **Solución:** usar FQDN con punto final en los clientes críticos, bajar `ndots` con `dnsConfig` y activar **NodeLocal DNSCache**.
- **Lección:** el DNS es una dependencia que se satura.

## Caso 10 · Consumidores que escalan a cero
- **Problema:** workers de colas corriendo 24/7 con la cola vacía casi siempre.
- **Solución:** KEDA con un `ScaledObject` sobre Service Bus (autenticación por Workload Identity): de 0 a 20 réplicas según el backlog.
- **Resultado:** el pool de batch (nodos spot) se reduce a 0 nodos de noche.
- **Lección:** escalar por evento ahorra más que escalar por CPU en cargas de colas.

## Caso 11 · Se cierra el API server
- **Problema:** una auditoría marcó el API server expuesto a Internet.
- **Solución:** clúster privado, cuentas locales deshabilitadas, acceso con Entra ID desde una red de administración y el pipeline con *runner* dentro de la VNet.
- **Lección:** el plano de control también se protege.

## Caso 12 · Secretos fuera de Git
- **Problema:** manifiestos con `Secret` en Base64 dentro del repositorio.
- **Solución:** CSI Secrets Store + Workload Identity: el secreto vive en Key Vault, se monta como archivo y se rota sin redesplegar.
- **Lección:** Base64 no es cifrado.

## Caso 13 · Un fin de semana de clústeres de prueba
- **Problema:** tres clústeres de laboratorio encendidos todo el fin de semana.
- **Solución:** `az aks stop` programado, pool de usuarios con autoescalado a 0 y presupuesto con alerta.
- **Lección:** los nodos se pagan por hora aunque no corra nada útil.
