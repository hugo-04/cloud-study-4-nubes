# Oracle OCI · Compute · OKE · Repaso

## Preguntas
1. ¿Qué administra Oracle y qué administras tú?
2. ¿Diferencia entre clúster basic y enhanced?
3. ¿Qué son los nodos virtuales?
4. ¿Qué ventaja tiene el CNI nativo? ¿Y su riesgo?
5. ¿En qué orden se actualiza?
6. ¿Por qué API privada?
7. ¿Qué hacen `requests` y `limits`?
8. ¿Cómo se identifica un pod ante OCI?
9. ¿Cuándo no usar OKE?
10. ¿Cómo llega el tráfico externo?

## Respuestas
1. Oracle: plano de control; tú: nodos (salvo virtuales), imágenes y aplicaciones.
2. Enhanced habilita workload identity, nodos virtuales y complementos gestionados.
3. Capacidad por pod sin servidores visibles.
4. Cada pod tiene IP de la VCN; consume IP de la subred.
5. Plano de control primero, luego los node pools.
6. Reduce la superficie de ataque.
7. Reserva y limita CPU/memoria por contenedor.
8. Con workload identity vía su ServiceAccount.
9. Con pocas piezas, poco equipo o tareas esporádicas.
10. Por un balanceador de OCI creado desde un Service/Ingress.

## Ejercicios
1. Dimensiona la subred de pods para 200 pods.
2. Escribe un Deployment con probes y límites.
3. Planifica la actualización de 1.31 a 1.32.
