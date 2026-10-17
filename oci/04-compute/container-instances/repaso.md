# Oracle OCI · Compute · Container Instances · Repaso

## Preguntas
1. ¿Qué administra OCI y qué administras tú en una container instance?
2. ¿Cuándo eliges Container Instances en lugar de Functions?
3. ¿Y en lugar de OKE?
4. ¿Qué hace la política de reinicio `NEVER` al terminar el proceso?
5. ¿Por qué nunca `latest`?
6. ¿Para qué sirve `opcRetryToken`?
7. ¿Dónde van los secretos?
8. ¿Qué significa un código de salida 137?
9. ¿Qué tipo de recurso usa el grupo dinámico?
10. ¿Qué pasa con los datos de un volumen `EMPTYDIR` al borrar la instancia?

## Respuestas
1. OCI: máquina, sistema y tiempo de ejecución. Tú: imagen, forma, red y configuración.
2. Cuando el trabajo dura más de unos minutos o necesita más memoria/CPU.
3. Cuando no necesitas réplicas, despliegues graduales ni malla de servicios.
4. Deja el contenedor detenido; si todos terminan, la instancia queda `INACTIVE`.
5. Porque no es inmutable: cada arranque puede descargar otra versión.
6. Para que reintentar la creación no cree instancias duplicadas.
7. En Vault, leídos con resource principal al arrancar.
8. El proceso fue terminado con `SIGKILL`, típicamente por falta de memoria.
9. `computecontainerinstance`.
10. Se pierden.

## Ejercicios
1. Escribe el `opcRetryToken` determinista para el lote diario de conciliación de Café Andino.
2. Calcula la forma mínima para dos contenedores de 1,5 GB y 0,5 OCPU cada uno, con margen del 25 %.
3. Diseña la limpieza automática de instancias `INACTIVE` con más de 24 horas.
