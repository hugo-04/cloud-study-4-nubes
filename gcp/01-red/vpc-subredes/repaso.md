# Google Cloud · Red · VPC y subredes · Repaso

## Preguntas
1. ¿La VPC es regional o global?
2. ¿Y las subredes?
3. ¿Para qué sirven los rangos secundarios?
4. ¿Qué hace Private Google Access?
5. ¿Qué es Shared VPC?
6. ¿Qué rol necesita un proyecto de servicio?
7. ¿Se puede reducir una subred?
8. ¿Por qué no usar modo automático?
9. ¿Qué decide el tráfico dentro de una VPC?
10. ¿Qué cuesta en una VPC?

## Respuestas
1. Global.
2. Regionales.
3. IPs para pods y servicios de GKE.
4. Acceso a APIs de Google sin IP externa.
5. Una red de un proyecto host usada por proyectos de servicio.
6. `roles/compute.networkUser` sobre la subred.
7. No, solo ampliar.
8. Sus rangos fijos chocan al conectar redes.
9. Las reglas de firewall.
10. El tráfico entre zonas/regiones y a Internet, y los flow logs.

## Ejercicios
1. Diseña subredes y secundarios para 2 regiones de ModaLima con GKE.
2. Calcula el rango de pods para 50 nodos con 110 pods.
3. Diseña la Shared VPC con permisos por equipo.
