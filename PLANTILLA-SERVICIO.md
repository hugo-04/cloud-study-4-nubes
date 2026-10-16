# Plantilla fija por servicio

Cada servicio vive en **su propia carpeta dentro de su nube** (`azure/04-compute/aks/`, `aws/04-compute/eks/`, etc.) y **solo habla de esa nube**. Las comparaciones entre nubes no van aquí.

## Archivos de cada carpeta de servicio

| Archivo | Para qué |
|---|---|
| `README.md` | Teoría completa: qué es, cómo funciona cada componente, cuándo sí y cuándo no, IAM y red privada |
| `casos-reales.md` | Historias con problema, solución, resultado y lección (mínimo 3) |
| `uso-en-java.md` | Cómo se usa desde Spring Boot y Quarkus, imperativo y reactivo |
| `ejemplos/` | `cli/`, `terraform/`, `java/`, `yaml/` según aplique, todo copiable |
| `troubleshooting.md` | Tabla síntoma → causa probable → cómo comprobarlo → solución |
| `repaso.md` | Preguntas de repaso y de entrevista con respuesta corta |
| `notebooklm.md` | Prompt de video solo para este servicio |

## Secciones del `README.md`

1. **Qué es**: una frase técnica y una analogía de la vida real.
2. **Cómo funciona por dentro**: cada componente por separado, con un diagrama.
3. **Para qué sirve y cuándo NO usarlo**: y cuál es la alternativa en la misma nube.
4. **Conceptos clave**: tabla de término, definición simple y ejemplo.
5. **Cómo se usa**: portal, CLI y Terraform, y cómo comprobar que quedó bien.
6. **Seguridad**: IAM (qué rol o permiso hace falta y por qué), identidad de la aplicación y red privada.
7. **Qué hacer y qué NO hacer**.
8. **Límites, costos y versiones**: lo que cambia con el tiempo va marcado con "verifica en la doc oficial".

## Reglas de escritura

- Español claro; define cada término técnico la primera vez que aparece.
- Casos de vida real inventados (ModaLima, Café Andino), nunca de un cliente real.
- Ningún secreto, ID de cuenta real ni connection string real.
- Todo comando o código que se pueda validar se valida antes de subirlo.
- Un archivo de servicio no menciona otras nubes.
