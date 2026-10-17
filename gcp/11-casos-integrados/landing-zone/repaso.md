# Google Cloud · Caso integrado · Landing zone · Repaso

## Preguntas
1. ¿Qué incluye la landing zone de una unidad?
2. ¿Qué lee el planificador?
3. ¿Por qué contar redes locales?
4. ¿Y rangos secundarios?
5. ¿Qué es la VPC compartida?
6. ¿Qué se hereda de la organización?
7. ¿Por qué grupos?
8. ¿Qué hace el verificador?
9. ¿Qué es un hallazgo desconocido?
10. ¿Qué rol necesita una app en la subred?

## Respuestas
1. Carpetas, proyectos, red, grupos, tags, presupuesto y lien.
2. Subredes primarias y secundarias de los proyectos host.
3. Porque ocupan rangos invisibles en la VPC.
4. Porque GKE los usa para pods y servicios.
5. Una red en un host usada por proyectos de servicio.
6. Políticas, sink de auditoría y roles de plataforma.
7. Para gestionar altas y bajas en un solo lugar.
8. Comprueba que todo existe y cumple tras el apply.
9. Lo que no se pudo comprobar.
10. `roles/compute.networkUser`.

## Ejercicios
1. Planifica la segunda unidad sin solapes.
2. Escribe la verificación de liens.
3. Diseña la revisión trimestral de grupos.
