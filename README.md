# Cloud Study · 4 Nubes

Repo **privado de estudio** para aprender, de cero a nivel intermedio, a construir **microservicios Java (Spring Boot y Quarkus)** en **Azure**, **AWS**, **Oracle Cloud (OCI)** y **Google Cloud**, más los temas **transversales** que valen en cualquier nube. Fuente de consulta «de inicio a fin por servicio».

> Los casos de vida real son **inventados** (ModaLima, Café Andino). El repo no contiene datos de clientes, cuentas ni credenciales reales.

## Cómo está organizado

```
README.md · CLAUDE.md · HANDOFF.md
azure/  aws/  oci/  gcp/        una carpeta por nube, independientes entre sí (ninguna menciona a otra)
  <nube>/README.md               índice y versiones
  <nube>/NN-capitulo/README.md   comparativa, árbol «quiero…», receta ModaLima, orden de adopción
  <nube>/NN-capitulo/<servicio>/ README · casos-reales · uso-en-java · troubleshooting · repaso · notebooklm · ejemplos/
transversal/                     temas sin nube: Terraform, Kafka, Spring Boot, Quarkus, reactivo, patrones, arquitectura y testing, frontends
tools/                           generadores y validadores (compilación Java/TypeScript, Terraform, enlaces)
```

**Navegación:** nube → capítulo → servicio. Cada servicio se lee en este orden: `README.md` (teoría en 8 secciones) → `casos-reales.md` → `uso-en-java.md` (Spring MVC, WebFlux, Quarkus imperativo y Mutiny; todo el código compila) → `troubleshooting.md` → `repaso.md`.

## Nubes

| Nube | Capítulos | Estado |
|---|---|---|
| [Azure](azure/README.md) | 00 fundamentos · 01 red · 02 IAM · 03 secretos · 04 compute · 05 ingress/API · 06 storage · 07 mensajería · 08 datos · 09 gobierno · 10 Terraform · 11 casos integrados | ✅ Completo |
| [AWS](aws/README.md) | ídem | ✅ Completo |
| [Oracle Cloud (OCI)](oci/README.md) | ídem | ✅ Completo |
| [Google Cloud](gcp/README.md) | ídem | ✅ Completo |

Los doce capítulos tienen el mismo número y propósito en las cuatro nubes, así que puedes estudiar una nube completa o el mismo capítulo en varias.

## Transversal

| Módulo | De qué trata | Estado |
|---|---|---|
| [Terraform / OpenTofu](transversal/terraform/README.md) | Lenguaje, estado, módulos, pruebas | ✅ |
| [Apache Kafka](transversal/kafka/README.md) | Particiones, grupos, garantías, DLT, esquemas, Spring/Reactor/Quarkus | ✅ |
| [Spring Boot](transversal/spring-boot/README.md) | Microservicio de producción completo | ✅ |
| [Quarkus](transversal/quarkus/README.md) | Imperativo, reactivo, tolerancia a fallos, nativo | ✅ |
| [Programación reactiva](transversal/programacion-reactiva/README.md) | Reactor, Mutiny, RxJava; cuándo hilos virtuales | ✅ |
| [Patrones de diseño](transversal/patrones-de-diseno/README.md) | Los 23 del GoF en Java 21 | ✅ |
| [Patrones de microservicios](transversal/patrones-microservicios/README.md) | Saga, outbox, CQRS, resiliencia, operación | ✅ |
| [Arquitectura y testing](transversal/arquitectura-y-testing/README.md) | Monolito vs microservicios, hexagonal, clean, DDD, TDD, BDD | ✅ |
| [TypeScript, React y Angular](transversal/typescript-react-angular/README.md) | Frontends para microservicios | ✅ |

## Videos con NotebookLM

Cada servicio, cada capítulo, cada nube y cada módulo transversal tiene su `notebooklm.md` con un prompt listo: crea un notebook, sube como fuentes los `.md` que indica el archivo y pega el prompt en «Personalizar» del Video Overview (o Audio Overview). Puntos de entrada: [`azure/notebooklm.md`](azure/notebooklm.md), [`aws/notebooklm.md`](aws/notebooklm.md), [`oci/notebooklm.md`](oci/notebooklm.md), [`gcp/notebooklm.md`](gcp/notebooklm.md) y [`transversal/notebooklm.md`](transversal/notebooklm.md). Las funciones de NotebookLM cambian: revisa su menú actual.

## Plan de estudio sugerido (12 semanas, una nube principal)

| Semana | Nube elegida | Transversal en paralelo | Práctica |
|---|---|---|---|
| 1 | 00 Fundamentos · 01 Red | Terraform | Red con dos subredes como código, destruir y recrear |
| 2 | 01 Red (privado y diagnóstico) | — | Romper el DNS privado a propósito y diagnosticarlo |
| 3 | 02 IAM · 03 Secretos | Spring Boot | Servicio que lee un secreto sin llaves |
| 4 | 04 Compute | Quarkus | Mismo servicio en contenedores administrados y en Kubernetes |
| 5 | 05 Ingress y API | Patrones de microservicios (resiliencia) | Gateway con límite de tasa y timeouts |
| 6 | 06 Storage | Patrones de diseño | Subida directa con URL firmada + claim check |
| 7 | 07 Mensajería | Kafka | Productor/consumidor idempotente con DLQ |
| 8 | 08 Datos | Arquitectura y testing | Base privada con autenticación por identidad y pruebas de integración |
| 9 | 09 Gobierno | — | Política que impide acceso público + presupuesto |
| 10 | 10 Terraform | Programación reactiva | Pipeline sin llaves con plan revisado |
| 11 | 11 Casos integrados | TypeScript/React/Angular | Tienda online con outbox y frontend |
| 12 | Repaso + otra nube | — | El mismo caso en una segunda nube |

> **Costos:** usa créditos o capas gratuitas, crea un presupuesto con alerta el primer día y destruye cada laboratorio al terminar.

## Checklist de producción (cualquier nube)

**Red:** rangos sin solapes · datos sin acceso público, con endpoint privado y DNS privado · reglas de tráfico con denegación por defecto · salida controlada y registrada.
**Identidad y secretos:** identidades de carga de trabajo en vez de llaves · secretos en el gestor, con rotación y acceso mínimo · CI/CD con federación (sin secretos guardados) · revisión de roles amplios.
**Datos:** respaldos probados con una restauración real · cifrado en reposo (con clave propia donde aplique) · RPO/RTO acordados y probados.
**Operación:** logs, métricas y alertas por síntoma · sondas liveness/readiness y autoescalado · DLQ con alerta · *timeouts*, reintentos acotados e idempotencia.
**Gobierno:** políticas de región, etiquetas y acceso público · protección contra borrado en lo crítico · infraestructura como código revisada por pull request · presupuestos y alertas de costo.

## Reglas del repo

- Aislamiento: los archivos de una nube nunca mencionan otra nube; los transversales no mencionan ninguna.
- Nada de secretos, llaves, tokens ni IDs reales; `.gitignore` excluye estados de Terraform, `.env` y llaves.
- Lo volátil (precios, límites, versiones) lleva «verifica»: los servicios cambian rápido. Contenido revisado en octubre de 2026.
- Versiones de los ejemplos: Java 21, Spring Boot 4.1, Quarkus 3.40, OpenTofu/Terraform 1.x; SDK y providers según cada nube (ver su README).

## Herramientas

`tools/` contiene los validadores usados para que todo el código compile: `javacheck.py` (bloques Java de los `.md`, en Spring y Quarkus), `tscheck.py` (bloques TypeScript/TSX), `tfcheck.sh` (Terraform `init` + `validate`), `linkcheck.py` (enlaces relativos), los generadores de documentación por nube y los `pom.xml` en `tools/maven/`. Cómo reconstruir el entorno: [`HANDOFF.md`](HANDOFF.md).
