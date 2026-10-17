# Transversal · Temas independientes de la nube

Módulos que aplican igual en cualquier nube (o sin nube): herramientas, frameworks, patrones y arquitectura para microservicios en Java. Ninguno menciona un proveedor concreto; lo específico de cada nube está en su carpeta.

| Módulo | De qué trata | Estado |
|---|---|---|
| [Terraform / OpenTofu](terraform/README.md) | IaC declarativa: lenguaje, estado, módulos, pruebas | Listo |
| [Apache Kafka](kafka/README.md) | Log de eventos: particiones, grupos, garantías, DLT, esquemas | Listo |

Cada módulo trae `README.md` (teoría con casos reales), `repaso.md` y `notebooklm.md`; el código Java compila con Java 21, Spring Boot 4.1 y Quarkus 3.40.
