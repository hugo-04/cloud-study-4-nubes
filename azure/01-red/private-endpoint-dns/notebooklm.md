# NotebookLM · Azure · Private Endpoint y DNS privado

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure Private Endpoint, Private Link y DNS privado, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. Qué es un Private Endpoint, con la analogía de la puerta interna y la guía telefónica.
2. Cómo funciona por dentro, paso a paso: la consulta DNS, el CNAME a privatelink, el registro A en la zona privada y la conexión a la NIC del endpoint. Muestra el diagrama.
3. Cada pieza: Private Endpoint, Private Link, connection y sus estados, group ID, zona privada, virtual network link y zone group.
4. Tabla de servicios con su group ID y su zona (Storage, SQL, PostgreSQL, Cosmos, Key Vault, Service Bus, ACR, App Service, APIM, AKS).
5. Service Endpoint vs Private Endpoint.
6. Arquitecturas de DNS: una VNet, hub-and-spoke, DNS propio con reenvío a 168.63.129.16, on-premises con DNS Private Resolver.
7. Cómo se crea: CLI y Terraform con el código de las fuentes, y cómo se verifica con nslookup.
8. IAM y políticas.
9. Los 6 casos reales como historias.
10. Uso desde Java: Azure SDK con identidad administrada, JDBC, no conectar por IP, healthchecks, en Spring Boot y Quarkus.
11. Qué hacer, qué NO hacer y la tabla de troubleshooting.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; cierra con 3 puntos de resumen y 2 preguntas de repaso.
```
