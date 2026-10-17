# Google Cloud · Terraform · Autenticación y pipelines · Repaso

## Preguntas
1. ¿Qué evita WIF?
2. ¿Qué tiene un proveedor de WIF?
3. ¿Por qué dos SAs por entorno?
4. ¿Qué rol une el principalSet con la SA?
5. ¿Por qué guardar el plan?
6. ¿Qué es una política sobre el plan?
7. ¿Qué hacer en runners dentro de Google Cloud?
8. ¿Cómo prueba un desarrollador?
9. ¿Qué riesgo tiene `plan.json`?
10. ¿Qué política prohíbe llaves?

## Respuestas
1. Las llaves JSON de larga vida.
2. Emisor, audiencia, mapeo de atributos y condición CEL.
3. Para separar lectura (PR) y escritura (main).
4. `roles/iam.workloadIdentityUser`.
5. Para aplicar exactamente lo revisado.
6. Reglas automáticas que bloquean cambios peligrosos.
7. Usar la SA adjunta al runner.
8. Con ADC de usuario y suplantando la SA de plan.
9. Puede contener secretos.
10. `iam.disableServiceAccountKeyCreation`.

## Ejercicios
1. Escribe la condición CEL para apply en prod.
2. Diseña los roles de la SA de plan.
3. Define tres reglas para el `plan.json`.
