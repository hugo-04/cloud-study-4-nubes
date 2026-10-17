# Google Cloud · Compute · Cloud Run · Repaso

## Preguntas
1. ¿Qué es una revisión?
2. ¿Qué controla la concurrencia?
3. ¿Para qué el mínimo y el máximo de instancias?
4. ¿Qué pasa con la CPU fuera de una petición?
5. ¿Cómo se llama a un servicio privado?
6. ¿Qué opciones de ingress hay?
7. ¿Cuándo usar jobs?
8. ¿Cómo hace un canario?
9. ¿Cómo se accede a la VPC?
10. ¿Cuándo preferir GKE?

## Respuestas
1. Una versión inmutable del servicio.
2. Cuántas peticiones simultáneas atiende cada instancia.
3. Evitar arranques en frío y limitar costo y conexiones.
4. Se congela si la CPU se asigna solo durante peticiones.
5. Con un ID token cuya audiencia es la URL y el rol `run.invoker`.
6. Todo, interno, e interno más balanceador.
7. Para tareas que terminan.
8. Dividiendo el tráfico entre revisiones.
9. Con Direct VPC egress o un conector.
10. Con muchos servicios y necesidades de plataforma.

## Ejercicios
1. Calcula el máximo de instancias para no superar 400 conexiones con pool de 5.
2. Diseña el canario del servicio de pedidos.
3. Mide y reduce el arranque en frío de un servicio Spring Boot.
