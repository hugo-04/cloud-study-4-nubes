# Google Cloud · IAM · Workload Identity Federation · Repaso

## Preguntas
1. ¿Qué resuelve la federación?
2. ¿Qué contiene un proveedor OIDC?
3. ¿Por qué la condición es obligatoria en la práctica?
4. ¿Qué es un principalSet?
5. ¿Tiene secretos el archivo de configuración de credenciales?
6. ¿Qué hace STS?
7. ¿Cómo separas prod de no-prod?
8. ¿Cuándo NO usar federación?
9. ¿Qué error indica audiencia equivocada?
10. ¿Qué carga Java el archivo de configuración?

## Respuestas
1. Que sistemas externos obtengan tokens sin llaves.
2. Emisor, audiencias, mapeo de atributos y condición.
3. Porque el emisor puede ser compartido por muchos ajenos.
4. Un conjunto de identidades por atributo (por ejemplo, un repositorio).
5. No.
6. Intercambia el token externo por uno de Google.
7. Con pools o condiciones distintos por rama/entorno.
8. Dentro de Google Cloud o en GKE.
9. `invalid_grant` por audiencia.
10. `GoogleCredentials.fromStream` (tipo `external_account`).

## Ejercicios
1. Escribe la condición para `modalima/infra` en `main` solamente.
2. Diseña pools para prod y no-prod.
3. Migra un pipeline con llave JSON a federación.
