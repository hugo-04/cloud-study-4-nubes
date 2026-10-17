# AWS · EFS · Repaso

## Preguntas
1. ¿Qué es EFS y qué protocolo usa?
   - *Sistema de archivos de red administrado que usa NFS.*
2. ¿Cuándo EFS y cuándo S3?
   - *EFS si necesitas semántica POSIX compartida; S3 para objetos.*
3. ¿Qué es un mount target y cuántos hacen falta?
   - *La puerta del sistema de archivos en una subred; uno por zona de disponibilidad usada.*
4. ¿Para qué sirve un punto de acceso?
   - *Fija directorio raíz y usuario POSIX por aplicación: aislamiento y permisos correctos.*
5. ¿Qué puerto debe permitir el grupo de seguridad?
   - *TCP 2049.*
6. ¿Cuándo se decide el cifrado en reposo?
   - *Al crear el sistema de archivos.*
7. ¿Por qué una sonda de salud debe tener timeout?
   - *Un NFS caído bloquea las llamadas en lugar de fallar rápido.*
8. ¿Qué modo de throughput se recomienda normalmente?
   - *Elastic.*
9. ¿Cómo reduces el costo de archivos fríos?
   - *Ciclo de vida hacia IA/Archive.*
10. ¿Cómo evitas que dos procesos corrompan un archivo?
    - *Escritura atómica (temporal + move) y bloqueos o nombres únicos.*

## Ejercicios
1. Diseña dos puntos de acceso (uploads y modelos) con uid/gid y raíz distintos.
2. Escribe la regla de SG para que solo la app alcance el EFS.
3. Describe cómo montarías el EFS en una tarea de Fargate.
4. Diseña una sonda de montaje que no bloquee el hilo.

## Autoevaluación
- [ ] Sé elegir entre EFS, S3 y EBS.
- [ ] Sé montar EFS en ECS, EKS y Lambda.
- [ ] Entiendo permisos POSIX y puntos de acceso.
- [ ] Sé diagnosticar un montaje que no responde.
