# Google Cloud · Terraform · Estado remoto · Repaso

## Preguntas
1. ¿Qué guarda el estado?
2. ¿Cómo bloquea el backend `gcs`?
3. ¿Por qué versionar el bucket?
4. ¿Qué roles necesita el pipeline?
5. ¿Por qué el estado es sensible?
6. ¿Cuándo usar `force-unlock`?
7. ¿Cómo se crea el bucket del estado?
8. ¿Cómo separas entornos?
9. ¿Cómo se autentica el pipeline?
10. ¿Cómo cifras con tu clave?

## Respuestas
1. La relación entre el código y los recursos reales, con atributos.
2. Con un archivo `.tflock` creado de forma atómica.
3. Para recuperar estados anteriores.
4. `roles/storage.objectUser` en su bucket.
5. Contiene secretos en texto claro.
6. Solo cuando confirmas que nadie está ejecutando.
7. Con un bootstrap aparte (estado local o manual).
8. Bucket por entorno y prefijo por componente.
9. Con Workload Identity Federation o suplantación.
10. Con CMEK en el bucket o `kms_encryption_key`.

## Ejercicios
1. Escribe el `backend.tf` de tienda en prod.
2. Diseña el ciclo de vida para guardar 30 versiones.
3. Escribe el procedimiento de `force-unlock`.
