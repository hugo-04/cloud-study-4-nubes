# Google Cloud

Documentación de estudio de Google Cloud enfocada en **microservicios con Java (Spring Boot y Quarkus)**. Cada servicio vive en su propia carpeta y habla solo de Google Cloud.

## Versiones usadas en los ejemplos

Java 21 · Spring Boot 4.1 · Quarkus 3.40 · Google Cloud libraries-bom 26.90 · Terraform/OpenTofu con el proveedor `hashicorp/google`. Los ejemplos de Terraform se validan con `init` + `validate`; el código Java se compila contra las bibliotecas reales. *Verifica versiones vigentes.*

## Orden de estudio y estado

| # | Capítulo | Servicios | Estado |
|---|---|---|---|
| 00 | [Fundamentos](00-fundamentos/README.md) | Organización, carpetas, proyectos, regiones/zonas, APIs, ADC, facturación | Listo |
| 01 | [Red](01-red/README.md) | VPC y subredes, firewall/rutas/NAT, conectividad híbrida, acceso privado, diagnóstico | Listo |

## Cómo usar cada carpeta de servicio

1. `README.md` → teoría completa.
2. `casos-reales.md` → historias.
3. `uso-en-java.md` → código Spring Boot y Quarkus.
4. `ejemplos/` → CLI y Terraform listos para copiar.
5. `troubleshooting.md` → qué revisar cuando falla.
6. `repaso.md` → autoevaluación.
7. `notebooklm.md` → prompt para generar el video.

Prompt del video de toda la nube: [notebooklm.md](notebooklm.md).
