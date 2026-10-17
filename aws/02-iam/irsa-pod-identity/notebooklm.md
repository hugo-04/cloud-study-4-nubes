# NotebookLM · AWS · IRSA y EKS Pod Identity

**Fuentes a subir:** los `.md` de esta carpeta y `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre IRSA y EKS Pod Identity en AWS, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. La analogía de la oficina compartida y el diagrama de los tres caminos (rol del nodo, IRSA, Pod Identity).
2. IRSA paso a paso (OIDC, confianza con sub y aud, anotación, token proyectado, AssumeRoleWithWebIdentity).
3. Pod Identity paso a paso (agente, asociación, confianza con pods.eks.amazonaws.com, etiquetas de sesión).
4. Tabla comparativa, Fargate, y el equivalente en ECS, Lambda y EC2.
5. El riesgo del IMDS y cómo cerrarlo.
6. Cómo encuentra las credenciales el SDK de Java (cadena por defecto).
7. Seguridad, qué hacer y qué no.
8. Los seis casos reales como historias con su lección.
9. Java: detectar la fuente de credenciales, GetCallerIdentity al arrancar, indicador de salud, Spring MVC y WebFlux, Quarkus imperativo y Mutiny.
10. Troubleshooting por síntoma.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
