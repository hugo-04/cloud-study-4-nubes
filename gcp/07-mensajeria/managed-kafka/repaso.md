# Google Cloud · Mensajería · Managed Kafka · Repaso

## Preguntas
1. ¿Qué administra Google y qué tú?
2. ¿Cómo llegan los clientes al clúster?
3. ¿Qué mecanismo SASL se recomienda?
4. ¿Qué rol necesita una app?
5. ¿De qué depende el orden?
6. ¿Por qué no sirven más consumidores que particiones?
7. ¿Qué configura un tema?
8. ¿Cómo se cobra?
9. ¿Cuándo preferir Pub/Sub?
10. ¿Qué configuración de productor es segura?

## Respuestas
1. Google: brokers, parches, almacenamiento; tú: capacidad, subredes, temas y acceso.
2. Por endpoints privados (PSC) en tus subredes.
3. OAUTHBEARER con tokens de Google.
4. `roles/managedkafka.client`.
5. De la partición, que decide la clave.
6. Cada partición la consume un solo miembro del grupo.
7. Particiones, réplicas y configuraciones como retención.
8. vCPU, memoria, almacenamiento y tráfico.
9. Si no necesitas el ecosistema Kafka ni operar particiones.
10. `acks=all` y `enable.idempotence=true`.

## Ejercicios
1. Dimensiona particiones para 5 000 eventos/s con consumidores de 400 eventos/s.
2. Escribe el tema `pedidos` con Terraform y retención de 7 días.
3. Configura un consumidor Quarkus con OAUTHBEARER.
