# Azure · Cost Management · Repaso

## Preguntas de repaso
1. ¿Qué hace Cost Management y qué NO hace?
   - *Mide, analiza, avisa y exporta el gasto. No frena el consumo por sí mismo.*
2. ¿Con qué retraso llegan los datos de costo?
   - *Suelen estar disponibles en 8–24 horas; las suscripciones nuevas pueden tardar hasta 48 horas.*
3. ¿Qué diferencia hay entre costo real y amortizado?
   - *Real es lo facturable; amortizado reparte las compras de reservas y planes de ahorro en el tiempo. Los presupuestos usan el real.*
4. ¿En qué alcances se pueden crear presupuestos?
   - *Grupo de administración, suscripción y grupo de recursos (más los de facturación de EA/MCA).*
5. ¿Cuántos umbrales y destinatarios admite un presupuesto?
   - *Hasta 5 umbrales (de 0,01 % a 1000 %) y hasta 5 correos.*
6. ¿Qué es un umbral pronosticado?
   - *Un aviso cuando el gasto *proyectado* del periodo supera el porcentaje, aunque todavía no se haya gastado.*
7. ¿Cada cuánto se evalúa un presupuesto?
   - *Cada 24 horas; el correo suele salir dentro de la hora siguiente.*
8. ¿En qué alcances funcionan los grupos de acciones de un presupuesto?
   - *Solo en suscripción y en grupo de recursos.*
9. ¿Por qué `az consumption budget create` puede ser una trampa?
   - *Crea el presupuesto sin notificaciones: no define umbrales ni correos.*
10. ¿Cómo se frena el gasto de un entorno?
    - *Con un grupo de acciones que dispara tu automatización (apagar lo etiquetado), con acciones reversibles; o con políticas que impiden crear lo caro.*
11. ¿Cómo funciona la detección de anomalías?
    - *Compara el gasto diario con un pronóstico basado en 60 días de historial; se ejecuta 36 horas después de acabar el día; es por suscripción.*
12. ¿Qué límites tienen las alertas de anomalías?
    - *Solo suscripción, hasta cinco por suscripción, solo nube pública; el creador debe mantener el rol Reader.*
13. ¿Qué se puede exportar y adónde?
    - *Costo y uso (real, amortizado, FOCUS), hoja de precios y datos de reservas, a una cuenta de almacenamiento, en CSV o Parquet.*
14. ¿Por qué hay que leer el `manifest.json` de una exportación?
    - *Porque los archivos se particionan siempre (menos de 1 GB sin comprimir) y el manifiesto lista todas las partes.*
15. ¿Qué necesita una exportación hacia una cuenta con firewall?
    - *Servicios de confianza de Azure permitidos, misma tenant, la identidad del export con Storage Blob Data Contributor y API 2023-08-01 o posterior.*
16. ¿Qué hace la herencia de etiquetas?
    - *Aplica las etiquetas de la suscripción y del grupo de recursos a los registros de uso de los recursos hijos (no a los recursos).*
17. ¿Para qué sirven las reglas de asignación de costos?
    - *Para repartir el costo de servicios compartidos entre los equipos que los usan.*
18. ¿Qué tres palancas de ahorro revisarías primero?
    - *Dimensionar bien, apagar lo que no se usa (y borrar huérfanos) y compromisos (reservas/planes de ahorro) para cargas estables.*
19. ¿Qué roles hacen falta para crear presupuestos y para solo verlos?
    - *Crear: Contributor / Cost Management Contributor; ver: Reader / Cost Management Reader.*
20. ¿Cómo consultas el costo de un mes desde Java?
    - *Con la API de consultas (`CostManagementManager.queries().usage(...)`), agrupando por etiqueta o dimensión, y cacheando el resultado.*

## Mini-ejercicios
1. Diseña los umbrales de un presupuesto mensual de 5 000 USD para producción y los de uno de 800 USD para Sandbox. ¿Cuáles avisan y cuáles actúan?
2. Escribe los pasos para que una Function apague las máquinas de Sandbox al 100 %. ¿Qué identidad usa y qué permisos mínimos tiene?
3. Un equipo dice "mi presupuesto no avisó". Escribe 6 comprobaciones en orden.
4. Define las tres etiquetas obligatorias y sus valores permitidos; ¿qué política las impone y en qué orden de efectos?
5. Diseña una exportación diaria para BI: formato, destino, red, identidad y cómo la lee el proceso de carga.

## Frases para recordar
- **Un presupuesto avisa; el freno lo construyes tú.**
- **Datos con 8–24 horas de retraso: no es tiempo real.**
- **Pronóstico para enterarte a mitad de mes; anomalías para ver la forma del gasto.**
- **Sin etiquetas no hay reparto: imponlas con política y limita sus valores.**
- **Exportación: lee el manifiesto y cuida la red y los permisos del destino.**
