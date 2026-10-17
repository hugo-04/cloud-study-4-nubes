# Oracle OCI · Compute · Instancias · Repaso

## Preguntas
1. ¿Qué es una forma flexible?
2. ¿Cuánto cuesta una instancia detenida?
3. ¿Para qué sirve cloud-init?
4. ¿Qué es un dominio de fallos?
5. ¿Cómo accedes sin IP pública?
6. ¿Qué es el servicio de metadatos?
7. ¿Por qué IMDSv2?
8. ¿Cuándo usar instance pool?
9. ¿Qué riesgo tienen las formas preemptible?
10. ¿Cómo evitas VM huérfanas?

## Respuestas
1. Una forma donde eliges OCPU y memoria.
2. No cobra cómputo; sí discos.
3. Automatizar la configuración al primer arranque.
4. Un agrupamiento de hardware con fallos independientes dentro de un AD.
5. Con Bastion o VPN.
6. Un endpoint local con datos de la instancia y credenciales de identidad.
7. Exige token de sesión y mitiga robo de credenciales por SSRF.
8. Para escalar horizontalmente detrás de un balanceador.
9. Oracle puede recuperarlas en cualquier momento.
10. Etiquetas obligatorias y revisión periódica.

## Ejercicios
1. Diseña la etiqueta `horario` para dev (L–V 08–19).
2. Escribe las reglas de NSG de una VM de aplicación.
3. Calcula el ahorro de apagar 20 VM fuera de horario.
