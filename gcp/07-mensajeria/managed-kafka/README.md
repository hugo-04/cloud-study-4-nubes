# Google Cloud · Mensajería · Managed Service for Apache Kafka

**Apache Kafka administrado** por Google: tú defines el clúster (vCPU, memoria, subredes) y los temas; Google opera brokers, parches, almacenamiento y réplicas. Tus clientes Kafka de siempre (Spring Kafka, Quarkus Messaging, Kafka Streams) se conectan con **SASL sobre TLS** usando identidades de **IAM**. El detalle de Kafka en sí (particiones, grupos, offsets, exactly-once) está en el módulo transversal [Kafka](../../../transversal/kafka/README.md).

## 1. Qué es

**Analogía:** un centro de distribución con estantes numerados (particiones). Google construye y mantiene el almacén; tú decides cuántos estantes tiene cada pasillo (tema) y quién puede entrar.

```
 VPC del cliente (subred en southamerica-west1)
   │  Private Service Connect (lo crea el servicio)
   ▼
 Clúster "eventos-modalima" (vCPU/memoria, 3 zonas)
   ├── tema clickstream   (12 particiones, rf 3)
   └── tema pedidos       (6 particiones,  rf 3)
   ▲
 Productores/consumidores Java · bootstrap.<cluster>.<region>.managedkafka.<proyecto>.cloud.goog:9092
   SASL_SSL + OAUTHBEARER (token de la cuenta de servicio)
```

## 2. Cómo funciona por dentro

| Pieza | Qué es |
|---|---|
| **Clúster** | Capacidad en vCPU y memoria; Google reparte brokers en zonas |
| **Subredes** | Dónde se publican los endpoints (PSC) para tus clientes |
| **Tema** | Particiones + factor de réplica + configuraciones (`retention.ms`, `cleanup.policy`) |
| **Grupos de consumidores** | Visibles y administrables desde la API |
| **Almacenamiento** | Escalado automático, con capa de bajo costo *(verifica)* |
| **Connect** | Clústeres de Kafka Connect administrados para conectores *(verifica)* |
| **Autenticación** | SASL OAUTHBEARER con tokens de Google o SASL/PLAIN con llave (evítalo) |
| **Autorización** | Roles IAM (`managedkafka.client`) y ACL de Kafka *(verifica)* |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Ya usas Kafka (Streams, Connect, clientes existentes) | Managed Kafka |
| Necesitas orden por clave, compactación y relectura por offset | Managed Kafka |
| Eventos simples entre servicios, sin operar particiones | [Pub/Sub](../pubsub/README.md) |
| Tareas a un endpoint con tasa | [Cloud Tasks](../cloud-tasks/README.md) |
| Reaccionar a eventos de Google | [Eventarc](../eventarc/README.md) |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Partición** | Unidad de orden y paralelismo |
| **Factor de réplica** | Copias de cada partición (3 por defecto) |
| **Grupo de consumidores** | Reparto de particiones entre instancias |
| **Bootstrap** | Dirección inicial a la que se conectan los clientes |
| **OAUTHBEARER** | SASL con token de acceso de Google |

## 5. Cómo se usa
1. Clúster y tema con Terraform: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Configuración de cliente Spring: [`ejemplos/kafka/application.yml`](ejemplos/kafka/application.yml) (necesita la biblioteca del *login handler* de Google en el classpath).
3. Revisión de temas y desde [Java](uso-en-java.md) con `AdminClient`.
4. CLI: [`ejemplos/cli/kafka.sh`](ejemplos/cli/kafka.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `roles/managedkafka.admin` | — |
| Apps | — | `roles/managedkafka.client` (+ ACL por tema si las usas) |
| Auditoría | `roles/managedkafka.viewer` | — |

- Solo accesible por red privada (PSC en tus subredes); firewall de 9092 hacia esos endpoints.
- TLS siempre; prefiere OAUTHBEARER con Workload Identity a llaves en base64.
- CMEK opcional para el almacenamiento *(verifica)*.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Elegir particiones por paralelismo y clave | Cambiar particiones a la ligera (rompe el orden por clave) |
| Productores con `acks=all` e idempotencia | `acks=1` en datos de negocio |
| Temas como código | Auto-creación de temas |
| Vigilar lag por grupo | Enterarte por los usuarios |
| Una cuenta por aplicación | Una cuenta compartida |

## 8. Límites, costos y versiones
- **Costo:** vCPU-hora + memoria-hora del clúster, almacenamiento por GB y tráfico entre zonas/regiones *(verifica)*.
- **Límites** (verifica): vCPU mínimas (3), relación memoria/vCPU, particiones por clúster.
- **Versión de Kafka:** la gestiona Google *(verifica)*; clientes `kafka-clients` 3.x/4.x.
- **Terraform:** `google_managed_kafka_cluster`, `google_managed_kafka_topic`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
