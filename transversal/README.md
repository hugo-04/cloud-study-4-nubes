# Transversal · Temas independientes de la nube

Módulos que aplican igual en cualquier nube (o sin nube): herramientas, frameworks, patrones y arquitectura para microservicios en Java. Ninguno menciona un proveedor concreto; lo específico de cada nube está en su carpeta.

| Módulo | De qué trata | Estado |
|---|---|---|
| [Terraform / OpenTofu](terraform/README.md) | IaC declarativa: lenguaje, estado, módulos, pruebas | Listo |
| [Apache Kafka](kafka/README.md) | Log de eventos: particiones, grupos, garantías, DLT, esquemas | Listo |
| [Spring Boot](spring-boot/README.md) | Microservicio de producción: configuración, REST, JPA, clientes, Actuator, pruebas | Listo |
| [Quarkus](quarkus/README.md) | Build time, imperativo y reactivo, Panache, tolerancia a fallos, nativo | Listo |
| [Programación reactiva](programacion-reactiva/README.md) | Reactive Streams, Reactor, Mutiny, RxJava; cuándo sí y cuándo hilos virtuales | Listo |
| [Patrones de diseño](patrones-de-diseno/README.md) | Los 23 del GoF con código Java 21 y cuándo usarlos | Listo |

Cada módulo trae `README.md` (teoría con casos reales), `repaso.md` y `notebooklm.md`; el código Java compila con Java 21, Spring Boot 4.1 y Quarkus 3.40.
