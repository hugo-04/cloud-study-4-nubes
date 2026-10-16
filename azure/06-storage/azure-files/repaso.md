# Azure · Azure Files · Repaso

## Preguntas de repaso
1. ¿Qué es Azure Files y en qué se diferencia de Blob?
   - *Un sistema de archivos compartido (SMB/NFS) con carpetas reales; Blob es almacén de objetos por REST.*
2. ¿Qué protocolos soporta y cuándo cada uno?
   - *SMB (Windows/Linux, con identidad) y NFS 4.1 (Linux, premium, control por red).*
3. ¿Cuándo premium y cuándo estándar?
   - *Premium: baja latencia y rendimiento (SSD, aprovisionado). Estándar: uso general económico (HDD).*
4. ¿Qué define el rendimiento en premium?
   - *La capacidad aprovisionada (cuota): IOPS y ancho de banda crecen con ella.*
5. ¿Qué dos capas de permisos hay en SMB?
   - *RBAC a nivel de share y ACL tipo NTFS dentro del share.*
6. ¿Por qué falla el montaje desde mi oficina?
   - *El puerto 445 suele estar bloqueado: usa VPN/Private Endpoint o el SDK por HTTPS.*
7. ¿Qué protege contra un borrado accidental?
   - *Soft delete de shares, instantáneas, Azure Backup y bloqueos del recurso.*
8. ¿Cómo comparten pods de AKS una carpeta?
   - *PVC `ReadWriteMany` con el controlador CSI de Azure Files (SMB o NFS).*
9. ¿Qué pasa si desactivo el acceso por clave de la cuenta?
   - *Los montajes que usan la clave dejan de funcionar; necesitas identidad.*
10. ¿Por qué no usar `WatchService` sobre un share?
    - *No notifica cambios de otros clientes en SMB/NFS; usa sondeo.*
11. ¿Cómo evitas leer archivos incompletos y procesarlos dos veces?
    - *Escritura `.part` + renombrado atómico, espera de estabilidad y "reclamar" con `ATOMIC_MOVE`.*
12. ¿Qué es Azure File Sync?
    - *Sincroniza un share con servidores Windows locales, con caché y *cloud tiering*.*
13. ¿Qué rol necesita el SDK de Java por REST con identidad?
    - *Storage File Data Privileged Contributor/Reader y `ShareTokenIntent.BACKUP`.*

## Entrevista
- Diseña el almacenamiento compartido de 20 pods que procesan 200 000 archivos diarios.
- ¿SMB o NFS para una aplicación Linux en AKS? Justifica.
- ¿Files o Blob para almacenar fotos de productos servidas por web?
- ¿Cómo recuperas un archivo borrado hace tres días?

## Ejercicio práctico
1. Despliega el [Terraform](ejemplos/terraform/main.tf).
2. Sube un archivo por REST con la [CLI](ejemplos/cli/azure-files.sh) y haz una instantánea.
3. Borra el archivo y recupéralo desde la instantánea.
4. Aplica el [YAML de AKS](ejemplos/yaml/azure-files-aks.yaml) y escribe desde dos pods.
5. Ejecuta el procesador de carpeta de [uso en Java](uso-en-java.md) con dos réplicas y comprueba que no duplican.
