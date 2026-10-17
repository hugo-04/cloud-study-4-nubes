# Google Cloud · Ingress y API · Cloud Armor · Repaso

## Preguntas
1. ¿Dónde se adjunta una política?
2. ¿Cómo se evalúan las reglas?
3. ¿Qué es el modo vista previa?
4. ¿Qué son las reglas WAF preconfiguradas?
5. ¿Qué es una exclusión?
6. ¿Diferencia entre throttle y rate-based ban?
7. ¿Qué hace Adaptive Protection?
8. ¿Cómo evitas el bypass con Cloud Run?
9. ¿Dónde ves qué regla actuó?
10. ¿Autentica usuarios?

## Respuestas
1. Al backend service (o backend bucket con políticas de borde).
2. Por prioridad; la primera que coincide aplica.
3. Registrar sin aplicar.
4. Conjuntos de firmas basados en OWASP CRS.
5. Ignorar un campo en una firma concreta.
6. Throttle limita; ban bloquea un tiempo tras superar el umbral.
7. Detecta ataques L7 y sugiere reglas.
8. Ingress interno más balanceador.
9. En los registros del balanceador.
10. No.

## Ejercicios
1. Escribe las reglas de tasa de login, búsqueda y checkout.
2. Diseña la salida de vista previa a bloqueo.
3. Escribe una exclusión para el campo `comentario`.
