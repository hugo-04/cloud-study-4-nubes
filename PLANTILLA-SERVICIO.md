# Plantilla fija por servicio

Todo servicio del repo se documenta con estas 12 secciones, en este orden. Así los videos y los resúmenes salen siempre comparables.

---

## 1. Qué es (con analogía)
Una frase técnica y una analogía de la vida real. Ejemplo: "Una VNet es el edificio privado de tu empresa; las subnets son los pisos."

## 2. Para qué sirve y cuándo NO usarlo
- Problemas que resuelve.
- Cuándo hay una opción mejor (y cuál).

## 3. Conceptos clave
Tabla corta: término, definición simple, ejemplo.

## 4. Casos de uso de vida real (mínimo 3)
Cada uno contado como historia:
- **Problema:** qué dolía.
- **Solución:** qué servicio y cómo.
- **Resultado:** qué mejoró.
- **Lección:** qué se aprende.

## 5. Cómo se usa (paso a paso)
- Portal (clics clave).
- CLI (comandos copiables).
- Terraform (bloque mínimo).
- Cómo se verifica que quedó bien.

## 6. Qué hacer
Buenas prácticas, en bullets cortos.

## 7. Qué NO hacer
Errores típicos y por qué duelen.

## 8. Ejemplos prácticos
Código (Java cuando aplique), YAML, JSON o consultas.

## 9. Equivalencias en las 4 nubes
| Concepto | Azure | AWS | OCI | GCP |
|---|---|---|---|---|

Seguido de **diferencias reales** (lo que no es 1 a 1).

## 10. IAM y políticas del servicio
- Quién necesita qué permiso (rol mínimo).
- Cómo se ve en Azure, AWS, OCI y GCP.
- Acceso privado y red asociada.

## 11. Troubleshooting
Tabla: síntoma → causa probable → cómo comprobarlo → solución.

## 12. Repaso y entrevista
- 5 preguntas de repaso con respuesta corta.
- 3 preguntas tipo entrevista.

---

### Reglas de redacción

- Define cada término técnico la primera vez que aparece.
- Ejemplos con nombres inventados.
- Lo sensible a versión lleva "verifica en la doc oficial".
- Un solo tema por archivo; módulos grandes se dividen en subcarpetas.
