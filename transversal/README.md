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
| [Patrones de microservicios](patrones-microservicios/README.md) | Datos, comunicación, consistencia (saga, outbox, CQRS), resiliencia y operación | Listo |
| [Arquitectura y testing](arquitectura-y-testing/README.md) | Monolito vs microservicios, hexagonal, clean, DDD, paquetes; TDD, BDD, dobles, contrato | Listo |
| [TypeScript, React y Angular](typescript-react-angular/README.md) | Frontends para microservicios: tipos como contrato, React, Angular, BFF y seguridad | Listo |

Prompt de panorama: [NotebookLM](notebooklm.md). Cada módulo trae `README.md` (teoría con casos reales), `repaso.md` y `notebooklm.md`. El código Java compila con Java 21, Spring Boot 4.1 y Quarkus 3.40 (`tools/tr-env/tr-env.sh`), el TypeScript con `tools/tscheck.py` (TypeScript 5.8, React 19, Angular 20) y el Terraform se valida y prueba con `terraform test`.
