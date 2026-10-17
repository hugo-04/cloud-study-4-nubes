# Google Cloud · Mensajería · Managed Kafka · Troubleshooting

## Lista ordenada
1. **Red:** ¿la subred del cliente está registrada en el clúster? ¿DNS resuelve el bootstrap? ¿9092 abierto?
2. **Autenticación:** `security.protocol=SASL_SSL`, `sasl.mechanism=OAUTHBEARER` y el handler de Google en el classpath.
3. **Autorización:** `roles/managedkafka.client` para la cuenta de la app.
4. **Tema:** ¿existe? ¿particiones y réplicas esperadas?
5. **Consumo:** lag por grupo y estado de rebalanceos.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Timeout al conectar | Red | Subred, DNS, firewall |
| `SaslAuthenticationException` | Handler o credenciales | Dependencia + ADC |
| `TopicAuthorizationException` | IAM/ACL | Rol o ACL |
| `UnknownTopicOrPartition` | Tema no creado | Créalo como código |
| Rebalanceos continuos | `max.poll.interval.ms` corto | Procesa en lotes o súbelo |
