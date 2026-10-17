# Oracle OCI · Caso integrado · Landing zone · Repaso

## Preguntas
1. ¿Qué incluye una landing zone?
2. ¿Por qué planificar el CIDR?
3. ¿Qué no debe poder hacer la unidad?
4. ¿Por qué verificar después del `apply`?
5. ¿Qué cuenta como hallazgo en la verificación?
6. ¿Dónde se crean IAM y compartimentos?
7. ¿Qué controles se instalan antes de entregar?
8. ¿Cuándo no crear una landing zone?
9. ¿Qué guarda la unidad como propio?
10. ¿Qué hace la Security Zone en prod?

## Respuestas
1. Compartimentos, red, IAM, etiquetas, cuotas, presupuesto y controles de seguridad.
2. Para no solapar rangos con otras redes conectadas.
3. Modificar sus políticas o la red compartida.
4. Porque un `apply` exitoso puede dejar piezas fuera.
5. Lo que falta, lo que no cumple y lo que no se pudo comprobar.
6. En la región home.
7. Cuotas, presupuesto con alertas, Cloud Guard y Audit.
8. Para un microservicio dentro de un producto existente.
9. Su estado remoto, su runner y sus compartimentos.
10. Impide crear recursos que violan la receta.

## Ejercicios
1. Planifica rangos para 4 unidades con prod/no-prod.
2. Escribe las políticas de admins y devs de la unidad.
3. Escribe la lista de verificación posterior.
