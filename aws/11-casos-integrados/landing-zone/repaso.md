# AWS · Caso integrado · Landing zone · Repaso

## Preguntas
1. ¿Por qué una cuenta por carga y entorno?
2. ¿Qué diferencia hay entre un SCP y una política de IAM?
3. ¿Por qué la cuenta de administración no aloja cargas?
4. ¿Por qué `CreateAccount` exige consultar el estado?
5. ¿Cómo se evita el solapamiento de CIDR?
6. ¿Por qué `prevent_destroy` en las cuentas?
7. ¿Qué cubre el trail de organización?
8. ¿Por qué «no se pudo verificar» debe ser un hallazgo?
9. ¿Qué comprueba la verificación nocturna?
10. ¿Cuándo no hace falta una landing zone?

## Respuestas
1. Limita el radio de un error y separa permisos, costos y auditoría.
2. El SCP es un techo que no concede permisos; la política de IAM concede dentro de ese techo.
3. Tiene poder sobre toda la organización; mezclar cargas aumenta el riesgo.
4. Es una operación asíncrona que puede tardar o fallar.
5. Con un asignador que reparte bloques alineados y valida contra los usados y reservados.
6. Porque cerrar una cuenta es casi irreversible.
7. A todas las cuentas y regiones, hacia la cuenta de logs.
8. Porque si no se puede mirar, no se puede asegurar el cumplimiento.
9. Trail de organización, Config, presupuesto, cifrado de EBS por defecto, etiquetas y ubicación en la OU.
10. En un prototipo de una sola cuenta.

## Ejercicios
1. Asigna tres redes /20 en `10.20.0.0/16` con `10.20.16.0/20` ocupado.
2. Escribe el SCP que impide crear recursos fuera de dos regiones.
3. Añade a la verificación la regla «la cuenta tiene el alias de cuenta definido».
4. Diseña la alerta para presupuestos al 80 % del pronóstico.

## Autoevaluación
- [ ] Puedo dibujar el árbol de OU y qué SCP aplica en cada nivel.
- [ ] Sé crear una cuenta con seguridad y verificarla.
- [ ] Reconozco los riesgos de automatizar `CreateAccount`.
