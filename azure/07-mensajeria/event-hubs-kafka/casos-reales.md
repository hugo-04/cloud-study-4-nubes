# Azure · Event Hubs (Kafka) · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar. Cada caso: problema → causa → solución → lección.)

## Caso 1 · Cadena de frío con sensores (Café Andino)
- **Problema:** 4.000 cámaras refrigeradas envían temperatura cada 10 segundos. Si una sube de 8 °C durante 5 minutos, hay que avisar a la tienda y registrar el incidente.
- **Solución:** los sensores publican en `lecturas-frio` con **clave = `camaraId`**. Un procesador de flujo (Stream Analytics o un servicio propio) mantiene una ventana de 5 minutos por cámara y emite alertas; **Capture** guarda todo en el lago para auditoría sanitaria.
- **Por qué Event Hubs:** volumen constante y alto, varios lectores (alertas, tablero, auditoría), necesidad de volver a leer.
- **Lección:** la clave de partición por dispositivo da orden por cámara y reparte bien la carga.

## Caso 2 · Clics de la tienda en línea (ModaLima)
- **Problema:** marketing, antifraude y búsqueda querían los mismos clics, cada uno a su ritmo; el equipo web los enviaba a tres APIs distintas.
- **Solución:** un solo event hub `clics-web` con **tres grupos de consumidores** (`analitica`, `antifraude`, `busqueda`) más Capture hacia el lago.
- **Resultado:** el equipo web publica una vez; cada equipo se suscribe sin pedir permiso ni cambiar al emisor.
- **Lección:** el grupo de consumidores es la unidad de independencia.

## Caso 3 · Migrar un Kafka propio a Event Hubs
- **Problema:** un clúster Kafka en máquinas virtuales costaba más en operación (parches, discos, ZooKeeper) que en cómputo.
- **Solución:** cambiar `bootstrap.servers`, `security.protocol=SASL_SSL` y el mecanismo SASL; los *topics* se crearon como event hubs con Terraform; Kafka Connect siguió corriendo en contenedores.
- **Lo que costó:** una funcionalidad (compactación por clave en un topic de estado) requería nivel Premium o rediseño; se movió ese estado a una base de datos.
- **Lección:** el protocolo es compatible, pero revisa la lista de funciones por nivel antes de prometer fecha.

## Caso 4 · CDC con Debezium (pedidos hacia buscador y lago)
- **Problema:** el buscador de productos y el lago de datos se alimentaban con consultas nocturnas pesadas a la base de pedidos.
- **Solución:** Debezium lee el log de transacciones de PostgreSQL y publica cada cambio en `pedidos-cdc` con **clave = clave primaria**; un consumidor actualiza el índice de búsqueda y Capture entrega los archivos al lago. **Schema Registry** con compatibilidad `Backward` evita que un cambio de columna rompa a los consumidores.
- **Lección:** CDC + clave primaria = orden por registro, y los reintentos son seguros si la escritura es idempotente.

## Caso 5 · La partición caliente
- **Problema:** 8 particiones, 3 consumidores al límite y 5 casi sin trabajo. El lag subía solo en una.
- **Causa:** la clave era `region` y el 90 % del tráfico venía de `PE`: un solo carril concentraba casi todo.
- **Solución:** clave por `clienteId` (muchos valores) conservando `region` como dato dentro del evento.
- **Lección:** una buena clave tiene **alta cardinalidad y distribución pareja**; revisa el reparto por partición antes de salir a producción.

## Caso 6 · Lag creciente tras una campaña
- **Problema:** durante una campaña, el tablero mostraba datos con 40 minutos de atraso.
- **Causa:** 8 particiones pero solo 3 réplicas del consumidor, cada una apenas aguantando.
- **Solución:** subir a 8 réplicas (una por partición) y autoescalar con **KEDA** según el lag del grupo; optimizar el procesamiento por lotes.
- **Lección:** el tope de paralelismo es el número de particiones: si lo necesitas mayor, se decide **al diseñar**.

## Caso 7 · Reprocesar tras un error de código
- **Problema:** un bug dejó mal calculado el total de ventas durante 6 horas.
- **Solución:** se corrigió el código y se lanzó un procesador con el grupo `reproceso` posicionado en la hora del error (`EventPosition.fromEnqueuedTime`) que escribió a una tabla temporal; después se cambió la vista. Capture sirvió de respaldo cuando una partición ya había salido de la retención.
- **Lección:** el valor del log es poder rebobinar; por eso la retención y Capture son decisiones de diseño, no detalles.

## Caso 8 · Rebalances en cascada
- **Problema:** cada pocos minutos los consumidores "se reiniciaban" y el lag oscilaba.
- **Causa:** el procesamiento de un lote de 500 registros tardaba más de `max.poll.interval.ms`; Kafka expulsaba al consumidor del grupo y reasignaba particiones, que ahora hacía otro que también se pasaba.
- **Solución:** `max.poll.records=100`, procesar en paralelo controlado dentro del lote y subir `max.poll.interval.ms` solo si hace falta.
- **Lección:** el tiempo entre `poll()` consecutivos es un contrato con el grupo.

## Caso 9 · El evento venenoso
- **Problema:** una partición dejó de avanzar; el mismo registro fallaba una y otra vez.
- **Causa:** un productor viejo enviaba un JSON con un campo con otro tipo; el consumidor lanzaba excepción y nunca hacía commit.
- **Solución:** `ErrorHandlingDeserializer` + `DefaultErrorHandler` con reintentos acotados y **envío a `errores-clics`** con el motivo y el offset original; alerta si ese event hub recibe algo.
- **Lección:** Event Hubs no tiene DLQ por mensaje: la construyes tú, y debe existir desde el día uno.

## Caso 10 · Limitación en Black Friday
- **Problema:** `ThrottledRequests` > 0 y productores con errores `ServerBusy`.
- **Causa:** auto-inflate alcanzó su tope de 6 TU; además, los productores enviaban evento por evento.
- **Solución:** subir el tope a 12 TU para la campaña, agrupar en lotes (`linger.ms=20`) y reintentar con retroceso; después de la campaña, **reducir TU manualmente** (no bajan solas).
- **Lección:** auto-inflate sube, nunca baja; el costo se vigila.

## Caso 11 · Logs de plataforma hacia el SIEM
- **Problema:** el equipo de seguridad necesitaba todos los registros de diagnóstico de Azure en su SIEM externo.
- **Solución:** las configuraciones de diagnóstico de recursos y de la suscripción envían a un event hub `plataforma-logs`; el conector del SIEM lee con su propio grupo.
- **Lección:** Event Hubs es el "conducto" estándar entre Azure y herramientas externas de observabilidad.

## Caso 12 · Event sourcing con límites claros
- **Problema:** se quiso usar el event hub como base de datos de eventos de pedidos "para siempre".
- **Causa:** la retención es limitada (días); pasados los días, el histórico desaparecería.
- **Solución:** el log sirve para propagar y reproducir en ventana corta; el **histórico permanente** vive en el lago (Capture) o en una tabla de eventos en la base de datos; las vistas se reconstruyen desde ahí.
- **Lección:** Event Hubs es un log de **transporte con memoria corta**, no un almacén eterno.

## Caso 13 · Duplicados en facturación
- **Problema:** algunas facturas salían dos veces tras reiniciar un pod.
- **Causa:** el consumidor hacía commit **antes** de terminar de procesar (para "ir rápido") y, en otro punto, reprocesaba por una caída posterior al guardado pero previa al commit.
- **Solución:** commit después de procesar y **restricción única por `eventId`**; la segunda inserción se ignora.
- **Lección:** al menos una vez + idempotencia = efecto exactamente una vez.

## Caso 14 · Costo desbordado
- **Problema:** la factura de Event Hubs de pruebas era mayor que la de producción.
- **Causa:** un namespace Premium creado "para probar" con varias PU encendidas todo el mes, sin tráfico.
- **Solución:** Standard con auto-inflate acotado en desarrollo, políticas de etiquetas y presupuesto con alerta (ver gobierno).
- **Lección:** la capacidad se paga por hora, haya o no eventos.
