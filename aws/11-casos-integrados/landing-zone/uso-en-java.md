# AWS · Caso integrado · Landing zone · Uso desde Java

Se construye un **servicio de vending y auditoría** de cuentas: planifica una cuenta nueva (nombre, OU, correo, CIDR libre), la crea con Organizations y revisa cada noche que las cuentas cumplan la línea base. Las reglas son puras; Organizations, STS y los servicios de verificación quedan detrás de puertos.

| Pieza | Qué resuelve |
|---|---|
| `Cidr`, `AsignadorDeCidr` | Aritmética IPv4: bloques alineados, sin solapamientos ni reservados |
| `PlanificadorDeCuentas`, `GeneradorDeCuentas` | Validar la solicitud, elegir OU y red, producir el `tfvars` |
| `VerificadorDeLineaBase` | Hallazgos por cuenta; «no se pudo verificar» también cuenta |
| `OrganizacionSdk`, `PresupuestosSdk` | Listar cuentas con su ruta de OU, crear cuentas, leer presupuestos |
| `FabricaDeSondasSts`, `SondaSdk` | Asumir un rol de solo lectura en cada cuenta y comprobar trail, Config y EBS |
| `ServicioLandingZone` | Orquesta: preparar, crear, consultar estado, auditar |

## 1. Configuración
```yaml
# Spring Boot (application.yml)
spring:
  task:
    scheduling:
      pool:
        size: 2
app:
  landing:
    pool-cidr: 10.20.0.0/16
    reservados: 10.20.240.0/20,10.200.0.0/16     # on-premises y laboratorio
    cuenta-administracion: "111122223333"
    rol-auditor: modalima-auditor
    correo-dominio: modalima.example
```
```properties
# Quarkus (application.properties)
app.landing.pool-cidr=10.20.0.0/16
app.landing.reservados=10.20.240.0/20,10.200.0.0/16
app.landing.cuenta-administracion=111122223333
app.landing.rol-auditor=modalima-auditor
quarkus.organizations.sync-client.type=url-connection
```

## 2. Núcleo común

### 2.1 Modelo y puertos
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;

record Cuenta(String id, String nombre, String correo, String estado, String rutaOu, Map<String, String> etiquetas) {}

enum Gravedad { ALTA, MEDIA, BAJA }

record Hallazgo(String idCuenta, String nombre, String regla, Gravedad gravedad, String detalle) {}

record InformeLineaBase(Instant generado, int cuentasRevisadas, List<Hallazgo> hallazgos) {
    boolean limpio() {
        return hallazgos.isEmpty();
    }
}

record EstadoCreacion(String estado, String idCuenta, String motivo) {}

/** Comprobaciones de solo lectura dentro de UNA cuenta (se accede asumiendo un rol). */
interface SondaDeCuenta {
    boolean trailDeOrganizacion();

    boolean configGrabando();

    boolean ebsCifradoPorDefecto();

    void cerrar();
}

interface FabricaDeSondas {
    SondaDeCuenta para(String idCuenta);
}

interface Organizacion {
    List<Cuenta> cuentas();

    String crearCuenta(String nombre, String correo, Map<String, String> etiquetas);

    EstadoCreacion estadoCreacion(String idSolicitud);
}

interface Presupuestos {
    /** Nombres de los presupuestos definidos en la cuenta de administración. */
    Set<String> nombres();
}
```

### 2.2 Direcciones IP sin solapamientos
Un CIDR es un inicio y un prefijo. Dos redes se **solapan** si sus rangos se tocan; para poder conectarlas mañana (peering, Transit Gateway, VPN) no deben hacerlo nunca. El asignador recorre el pool en saltos del tamaño del bloque (**alineado**) y devuelve el primero libre.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.Collection;

record Cidr(long base, int prefijo) {
    static Cidr parse(String texto) {
        String[] partes = texto.trim().split("/");
        if (partes.length != 2) {
            throw new IllegalArgumentException("CIDR inválido: " + texto);
        }
        String[] octetos = partes[0].split("\\.");
        if (octetos.length != 4) {
            throw new IllegalArgumentException("CIDR inválido: " + texto);
        }
        long base = 0;
        for (String o : octetos) {
            int v = Integer.parseInt(o);
            if (v < 0 || v > 255) {
                throw new IllegalArgumentException("octeto fuera de rango en " + texto);
            }
            base = (base << 8) | v;
        }
        int prefijo = Integer.parseInt(partes[1]);
        if (prefijo < 8 || prefijo > 28) {
            throw new IllegalArgumentException("prefijo fuera de 8..28 en " + texto);
        }
        var c = new Cidr(base, prefijo);
        if (base % c.tamano() != 0) {
            throw new IllegalArgumentException("el CIDR no está alineado a su prefijo: " + texto);
        }
        return c;
    }

    long tamano() {
        return 1L << (32 - prefijo);
    }

    long inicio() {
        return base;
    }

    long fin() {
        return base + tamano() - 1;
    }

    boolean solapa(Cidr otro) {
        return inicio() <= otro.fin() && otro.inicio() <= fin();
    }

    boolean contiene(Cidr otro) {
        return inicio() <= otro.inicio() && otro.fin() <= fin();
    }

    String texto() {
        return ((base >> 24) & 255) + "." + ((base >> 16) & 255) + "." + ((base >> 8) & 255) + "." + (base & 255) + "/" + prefijo;
    }
}

final class AsignadorDeCidr {
    private AsignadorDeCidr() {
    }

    static Cidr siguiente(Cidr pool, int prefijo, Collection<Cidr> ocupados) {
        if (prefijo < pool.prefijo() || prefijo > 28) {
            throw new IllegalArgumentException("prefijo " + prefijo + " no cabe en el pool " + pool.texto());
        }
        long tam = 1L << (32 - prefijo);
        for (long b = pool.inicio(); b + tam - 1 <= pool.fin(); b += tam) {
            var candidato = new Cidr(b, prefijo);
            if (ocupados.stream().noneMatch(candidato::solapa)) {
                return candidato;
            }
        }
        throw new IllegalStateException("pool agotado: no hay un /" + prefijo + " libre en " + pool.texto());
    }
}
```

### 2.3 Planificar una cuenta y generar el `tfvars`
El plan **no crea nada**: valida, decide y devuelve lo que se haría (ideal para revisarlo en un pull request). La OU depende del entorno, y el nombre sale de `{carga}-{entorno}`.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.regex.Pattern;

record SolicitudCuenta(String carga, String entorno, String equipo, String centroDeCostos, int presupuestoMensual, int prefijoCidr) {}

record PlanDeCuenta(String nombre, String correo, String ou, Cidr cidr, Map<String, String> etiquetas, int presupuestoMensual) {}

final class PlanificadorDeCuentas {
    private static final Pattern CARGA = Pattern.compile("[a-z][a-z0-9]{2,19}");
    private static final Pattern EQUIPO = Pattern.compile("[a-z][a-z0-9-]{1,29}");
    private static final Pattern CENTRO = Pattern.compile("CC-\\d{4}");
    private static final Map<String, String> OU_POR_ENTORNO = Map.of("prod", "prod", "stg", "noprod", "dev", "noprod", "sbx", "sandbox");

    private final Cidr pool;
    private final List<Cidr> reservados;
    private final String dominioCorreo;

    PlanificadorDeCuentas(Cidr pool, List<Cidr> reservados, String dominioCorreo) {
        this.pool = pool;
        this.reservados = List.copyOf(reservados);
        this.dominioCorreo = dominioCorreo;
    }

    PlanDeCuenta planificar(SolicitudCuenta s, Collection<String> nombresExistentes, Collection<Cidr> cidrOcupados) {
        var errores = new ArrayList<String>();
        if (s.carga() == null || !CARGA.matcher(s.carga()).matches()) {
            errores.add("carga: minúsculas y dígitos, 3 a 20 caracteres");
        }
        if (s.entorno() == null || !OU_POR_ENTORNO.containsKey(s.entorno())) {
            errores.add("entorno: prod, stg, dev o sbx");
        }
        if (s.equipo() == null || !EQUIPO.matcher(s.equipo()).matches()) {
            errores.add("equipo inválido");
        }
        if (s.centroDeCostos() == null || !CENTRO.matcher(s.centroDeCostos()).matches()) {
            errores.add("centro de costos: formato CC-0000");
        }
        if (s.presupuestoMensual() < 50 || s.presupuestoMensual() > 20_000) {
            errores.add("presupuesto mensual entre 50 y 20000");
        }
        if (s.prefijoCidr() < 16 || s.prefijoCidr() > 24) {
            errores.add("prefijo de red entre /16 y /24");
        }
        if (!errores.isEmpty()) {
            throw new IllegalArgumentException(String.join("; ", errores));
        }
        String nombre = s.carga() + "-" + s.entorno();
        if (nombresExistentes.contains(nombre)) {
            throw new IllegalArgumentException("ya existe una cuenta llamada " + nombre);
        }
        var ocupados = new ArrayList<Cidr>(reservados);
        ocupados.addAll(cidrOcupados);
        var cidr = AsignadorDeCidr.siguiente(pool, s.prefijoCidr(), ocupados);
        var etiquetas = new LinkedHashMap<String, String>();
        etiquetas.put("centroDeCostos", s.centroDeCostos());
        etiquetas.put("cidr", cidr.texto());
        etiquetas.put("entorno", s.entorno());
        etiquetas.put("equipo", s.equipo());
        etiquetas.put("gestionadoPor", "terraform");
        return new PlanDeCuenta(nombre, "aws+" + nombre + "@" + dominioCorreo, OU_POR_ENTORNO.get(s.entorno()), cidr, etiquetas, s.presupuestoMensual());
    }
}

final class GeneradorDeCuentas {
    private GeneradorDeCuentas() {
    }

    /** Archivo `cuentas.auto.tfvars.json` determinista (ordenado por nombre) para el módulo de Terraform. */
    static String tfvars(String bucketLogs, List<PlanDeCuenta> planes) {
        var sb = new StringBuilder("{\n  \"bucket_logs\": \"").append(bucketLogs).append("\",\n  \"cuentas\": {\n");
        var ordenados = planes.stream().sorted(Comparator.comparing(PlanDeCuenta::nombre)).toList();
        for (int i = 0; i < ordenados.size(); i++) {
            var p = ordenados.get(i);
            sb.append("    \"").append(p.nombre()).append("\": {\n")
                    .append("      \"correo\": \"").append(p.correo()).append("\",\n")
                    .append("      \"ou\": \"").append(p.ou()).append("\",\n")
                    .append("      \"equipo\": \"").append(p.etiquetas().get("equipo")).append("\",\n")
                    .append("      \"centro_de_costos\": \"").append(p.etiquetas().get("centroDeCostos")).append("\",\n")
                    .append("      \"presupuesto_mensual\": ").append(p.presupuestoMensual()).append(",\n")
                    .append("      \"cidr\": \"").append(p.cidr().texto()).append("\"\n")
                    .append("    }").append(i < ordenados.size() - 1 ? "," : "").append('\n');
        }
        return sb.append("  }\n}\n").toString();
    }
}
```

### 2.4 Verificar la línea base
Reglas deterministas sobre lo que se sabe de cada cuenta, más las sondas de solo lectura. Si una comprobación **falla al ejecutarse** (no hay rol, permiso denegado, tiempo agotado), no se da por buena: se reporta como `NO_SE_PUDO_VERIFICAR`.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.util.function.Supplier;

final class VerificadorDeLineaBase {
    private final FabricaDeSondas fabrica;
    private final Presupuestos presupuestos;
    private final Set<String> exentas;
    private final Clock reloj;

    VerificadorDeLineaBase(FabricaDeSondas fabrica, Presupuestos presupuestos, Set<String> exentas, Clock reloj) {
        this.fabrica = fabrica;
        this.presupuestos = presupuestos;
        this.exentas = exentas;
        this.reloj = reloj;
    }

    InformeLineaBase verificar(List<Cuenta> cuentas) {
        var hallazgos = new ArrayList<Hallazgo>();
        Set<String> nombresPresupuesto = null;
        Hallazgo falloPresupuestos = null;
        try {
            nombresPresupuesto = presupuestos.nombres();
        } catch (RuntimeException e) {
            falloPresupuestos = new Hallazgo("*", "*", "NO_SE_PUDO_VERIFICAR", Gravedad.ALTA, "presupuestos: " + resumir(e));
        }
        if (falloPresupuestos != null) {
            hallazgos.add(falloPresupuestos);
        }
        int revisadas = 0;
        for (var c : cuentas) {
            if (!"ACTIVE".equals(c.estado()) || exentas.contains(c.id())) {
                continue;
            }
            revisadas++;
            reglasLocales(c, hallazgos);
            if (nombresPresupuesto != null && !nombresPresupuesto.contains("presupuesto-" + c.nombre())) {
                hallazgos.add(new Hallazgo(c.id(), c.nombre(), "SIN_PRESUPUESTO", Gravedad.MEDIA, "falta presupuesto-" + c.nombre()));
            }
            sondear(c, hallazgos);
        }
        hallazgos.sort(Comparator.comparing(Hallazgo::gravedad).thenComparing(Hallazgo::nombre).thenComparing(Hallazgo::regla));
        return new InformeLineaBase(reloj.instant(), revisadas, List.copyOf(hallazgos));
    }

    private static void reglasLocales(Cuenta c, List<Hallazgo> out) {
        for (String etiqueta : List.of("equipo", "centroDeCostos")) {
            if (c.etiquetas() == null || !c.etiquetas().containsKey(etiqueta)) {
                out.add(new Hallazgo(c.id(), c.nombre(), "ETIQUETA_FALTANTE", Gravedad.MEDIA, "falta la etiqueta " + etiqueta));
            }
        }
        boolean nombreProd = c.nombre().endsWith("-prod");
        boolean enProd = "Cargas/Prod".equals(c.rutaOu());
        if (nombreProd && !enProd) {
            out.add(new Hallazgo(c.id(), c.nombre(), "PROD_FUERA_DE_OU_PROD", Gravedad.ALTA, "está en «" + c.rutaOu() + "»"));
        }
        if (!nombreProd && enProd) {
            out.add(new Hallazgo(c.id(), c.nombre(), "NOPROD_EN_OU_PROD", Gravedad.MEDIA, "no es de producción pero está en Cargas/Prod"));
        }
        if (c.nombre().endsWith("-sbx") && !"Sandbox".equals(c.rutaOu())) {
            out.add(new Hallazgo(c.id(), c.nombre(), "SANDBOX_FUERA_DE_SANDBOX", Gravedad.MEDIA, "está en «" + c.rutaOu() + "»"));
        }
    }

    private void sondear(Cuenta c, List<Hallazgo> out) {
        SondaDeCuenta sonda;
        try {
            sonda = fabrica.para(c.id());
        } catch (RuntimeException e) {
            out.add(new Hallazgo(c.id(), c.nombre(), "NO_SE_PUDO_VERIFICAR", Gravedad.ALTA, "no se pudo asumir el rol auditor: " + resumir(e)));
            return;
        }
        try {
            comprobar(c, "SIN_TRAIL_DE_ORGANIZACION", Gravedad.ALTA, sonda::trailDeOrganizacion, out);
            comprobar(c, "CONFIG_NO_GRABA", Gravedad.ALTA, sonda::configGrabando, out);
            comprobar(c, "EBS_SIN_CIFRADO_POR_DEFECTO", Gravedad.MEDIA, sonda::ebsCifradoPorDefecto, out);
        } finally {
            sonda.cerrar();
        }
    }

    private static void comprobar(Cuenta c, String regla, Gravedad g, Supplier<Boolean> prueba, List<Hallazgo> out) {
        try {
            if (!prueba.get()) {
                out.add(new Hallazgo(c.id(), c.nombre(), regla, g, "no cumple"));
            }
        } catch (RuntimeException e) {
            out.add(new Hallazgo(c.id(), c.nombre(), "NO_SE_PUDO_VERIFICAR", Gravedad.ALTA, regla + ": " + resumir(e)));
        }
    }

    private static String resumir(RuntimeException e) {
        String m = e.getMessage() == null ? "" : e.getMessage();
        return e.getClass().getSimpleName() + (m.isEmpty() ? "" : ": " + m.substring(0, Math.min(120, m.length())));
    }
}
```

### 2.5 Adaptadores del SDK
`CreateAccount` devuelve una **solicitud**, no la cuenta: hay que consultar su estado. Para entrar en cada cuenta se asume un rol de solo lectura con credenciales de 15 minutos. Listar cuentas con su ruta de OU requiere varias llamadas; dentro de cada vuelta se reutilizan los padres y nombres de OU ya consultados para no agotar el límite de Organizations, pero **no entre vueltas**: una cuenta movida de OU es justo lo que se audita.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Duration;
import java.util.HashMap;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.budgets.BudgetsClient;
import software.amazon.awssdk.services.budgets.model.DescribeBudgetsRequest;
import software.amazon.awssdk.services.cloudtrail.CloudTrailClient;
import software.amazon.awssdk.services.cloudtrail.model.DescribeTrailsRequest;
import software.amazon.awssdk.services.config.ConfigClient;
import software.amazon.awssdk.services.config.model.ConfigurationRecorderStatus;
import software.amazon.awssdk.services.ec2.Ec2Client;
import software.amazon.awssdk.services.ec2.model.GetEbsEncryptionByDefaultRequest;
import software.amazon.awssdk.services.organizations.OrganizationsClient;
import software.amazon.awssdk.services.organizations.model.CreateAccountRequest;
import software.amazon.awssdk.services.organizations.model.DescribeCreateAccountStatusRequest;
import software.amazon.awssdk.services.organizations.model.DescribeOrganizationalUnitRequest;
import software.amazon.awssdk.services.organizations.model.ListAccountsRequest;
import software.amazon.awssdk.services.organizations.model.ListParentsRequest;
import software.amazon.awssdk.services.organizations.model.ListTagsForResourceRequest;
import software.amazon.awssdk.services.organizations.model.Parent;
import software.amazon.awssdk.services.organizations.model.ParentType;
import software.amazon.awssdk.services.organizations.model.Tag;
import software.amazon.awssdk.services.sts.StsClient;
import software.amazon.awssdk.services.sts.auth.StsAssumeRoleCredentialsProvider;
import software.amazon.awssdk.services.sts.model.AssumeRoleRequest;

final class OrganizacionSdk implements Organizacion {
    private final OrganizationsClient org;
    OrganizacionSdk(OrganizationsClient org) {
        this.org = org;
    }

    @Override
    public List<Cuenta> cuentas() {
        // Cachés solo durante ESTA vuelta: una cuenta puede cambiar de OU y justo eso es lo que se audita.
        var padres = new HashMap<String, Parent>();
        var nombresOu = new HashMap<String, String>();
        var lista = new ArrayList<Cuenta>();
        for (var pagina : org.listAccountsPaginator(ListAccountsRequest.builder().build())) {
            for (var a : pagina.accounts()) {
                lista.add(new Cuenta(a.id(), a.name(), a.email(), a.statusAsString(), ruta(a.id(), padres, nombresOu), etiquetas(a.id())));
            }
        }
        return lista;
    }

    @Override
    public String crearCuenta(String nombre, String correo, Map<String, String> etiquetas) {
        var tags = etiquetas.entrySet().stream().map(e -> Tag.builder().key(e.getKey()).value(e.getValue()).build()).toList();
        var r = org.createAccount(CreateAccountRequest.builder().accountName(nombre).email(correo).tags(tags).build());
        return r.createAccountStatus().id();
    }

    @Override
    public EstadoCreacion estadoCreacion(String idSolicitud) {
        var s = org.describeCreateAccountStatus(DescribeCreateAccountStatusRequest.builder().createAccountRequestId(idSolicitud).build()).createAccountStatus();
        return new EstadoCreacion(s.stateAsString(), s.accountId(), s.failureReasonAsString());
    }

    private String ruta(String hijoId, Map<String, Parent> padres, Map<String, String> nombresOu) {
        var partes = new ArrayList<String>();
        String actual = hijoId;
        for (int i = 0; i < 5; i++) { // la profundidad máxima de OU es 5
            Parent padre = padres.computeIfAbsent(actual, id -> org.listParents(ListParentsRequest.builder().childId(id).build()).parents().get(0));
            if (padre.type() == ParentType.ROOT) {
                break;
            }
            partes.add(0, nombresOu.computeIfAbsent(padre.id(),
                    id -> org.describeOrganizationalUnit(DescribeOrganizationalUnitRequest.builder().organizationalUnitId(id).build()).organizationalUnit().name()));
            actual = padre.id();
        }
        return String.join("/", partes);
    }

    private Map<String, String> etiquetas(String cuentaId) {
        var mapa = new HashMap<String, String>();
        for (var t : org.listTagsForResourcePaginator(ListTagsForResourceRequest.builder().resourceId(cuentaId).build()).tags()) {
            mapa.put(t.key(), t.value());
        }
        return mapa;
    }
}

final class PresupuestosSdk implements Presupuestos {
    private final BudgetsClient budgets;
    private final String cuentaAdministracion;

    PresupuestosSdk(BudgetsClient budgets, String cuentaAdministracion) {
        this.budgets = budgets;
        this.cuentaAdministracion = cuentaAdministracion;
    }

    @Override
    public Set<String> nombres() {
        var nombres = new java.util.HashSet<String>();
        for (var b : budgets.describeBudgetsPaginator(DescribeBudgetsRequest.builder().accountId(cuentaAdministracion).build()).budgets()) {
            nombres.add(b.budgetName());
        }
        return nombres;
    }
}

final class SondaSdk implements SondaDeCuenta {
    private final CloudTrailClient trail;
    private final ConfigClient config;
    private final Ec2Client ec2;

    SondaSdk(CloudTrailClient trail, ConfigClient config, Ec2Client ec2) {
        this.trail = trail;
        this.config = config;
        this.ec2 = ec2;
    }

    @Override
    public boolean trailDeOrganizacion() {
        return trail.describeTrails(DescribeTrailsRequest.builder().includeShadowTrails(true).build()).trailList().stream()
                .anyMatch(t -> Boolean.TRUE.equals(t.isOrganizationTrail()) && Boolean.TRUE.equals(t.isMultiRegionTrail())
                        && Boolean.TRUE.equals(t.logFileValidationEnabled()));
    }

    @Override
    public boolean configGrabando() {
        return config.describeConfigurationRecorderStatus().configurationRecordersStatus().stream().anyMatch(ConfigurationRecorderStatus::recording);
    }

    @Override
    public boolean ebsCifradoPorDefecto() {
        return Boolean.TRUE.equals(ec2.getEbsEncryptionByDefault(GetEbsEncryptionByDefaultRequest.builder().build()).ebsEncryptionByDefault());
    }

    @Override
    public void cerrar() {
        trail.close();
        config.close();
        ec2.close();
    }
}

final class FabricaDeSondasSts implements FabricaDeSondas {
    private final StsClient sts;
    private final String rol;
    private final Region region;

    FabricaDeSondasSts(StsClient sts, String rol, Region region) {
        this.sts = sts;
        this.rol = rol;
        this.region = region;
    }

    @Override
    public SondaDeCuenta para(String idCuenta) {
        AwsCredentialsProvider credenciales = StsAssumeRoleCredentialsProvider.builder()
                .stsClient(sts)
                .refreshRequest(AssumeRoleRequest.builder()
                        .roleArn("arn:aws:iam::" + idCuenta + ":role/" + rol)
                        .roleSessionName("verificador-landing-zone")
                        .durationSeconds((int) Duration.ofMinutes(15).toSeconds())
                        .build())
                .build();
        return new SondaSdk(
                CloudTrailClient.builder().region(region).credentialsProvider(credenciales).build(),
                ConfigClient.builder().region(region).credentialsProvider(credenciales).build(),
                Ec2Client.builder().region(region).credentialsProvider(credenciales).build());
    }
}
```

### 2.6 El servicio
Prepara (sin tocar nada), crea (solo cuando una persona aprobó el plan) y audita. El último informe se guarda en memoria para consultarlo sin repetir cientos de llamadas.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.concurrent.atomic.AtomicReference;

final class ServicioLandingZone {
    private final Organizacion organizacion;
    private final PlanificadorDeCuentas planificador;
    private final VerificadorDeLineaBase verificador;
    private final AtomicReference<InformeLineaBase> ultimo = new AtomicReference<>();

    ServicioLandingZone(Organizacion organizacion, PlanificadorDeCuentas planificador, VerificadorDeLineaBase verificador) {
        this.organizacion = organizacion;
        this.planificador = planificador;
        this.verificador = verificador;
    }

    PlanDeCuenta preparar(SolicitudCuenta solicitud) {
        var cuentas = organizacion.cuentas();
        var nombres = cuentas.stream().map(Cuenta::nombre).toList();
        var ocupados = new ArrayList<Cidr>();
        for (var c : cuentas) {
            String cidr = c.etiquetas() == null ? null : c.etiquetas().get("cidr");
            if (cidr != null) {
                ocupados.add(Cidr.parse(cidr));
            }
        }
        return planificador.planificar(solicitud, nombres, ocupados);
    }

    /** Devuelve el id de la solicitud de creación (asíncrona). */
    String crear(PlanDeCuenta plan) {
        return organizacion.crearCuenta(plan.nombre(), plan.correo(), plan.etiquetas());
    }

    EstadoCreacion estado(String idSolicitud) {
        return organizacion.estadoCreacion(idSolicitud);
    }

    InformeLineaBase auditar() {
        var informe = verificador.verificar(organizacion.cuentas());
        ultimo.set(informe);
        return informe;
    }

    java.util.Optional<InformeLineaBase> ultimoInforme() {
        return java.util.Optional.ofNullable(ultimo.get());
    }
}
```

## 3. Spring MVC (imperativo)
`POST /cuentas` es la operación peligrosa: protégela con un rol propio (por ejemplo `landing-zone-admin`) y exige un plan previo revisado.
```java
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.ResponseEntity;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Configuration
@EnableScheduling
class LandingConfig {
    @Bean(destroyMethod = "close")
    OrganizationsClient organizations() {
        return OrganizationsClient.builder().region(Region.AWS_GLOBAL).build();
    }

    @Bean(destroyMethod = "close")
    BudgetsClient budgets() {
        return BudgetsClient.builder().region(Region.AWS_GLOBAL).build();
    }

    @Bean(destroyMethod = "close")
    StsClient sts() {
        return StsClient.create();
    }

    @Bean
    ServicioLandingZone landing(OrganizationsClient org, BudgetsClient budgets, StsClient sts,
                                @Value("${app.landing.pool-cidr}") String pool, @Value("${app.landing.reservados}") String reservados,
                                @Value("${app.landing.cuenta-administracion}") String admin, @Value("${app.landing.rol-auditor}") String rol,
                                @Value("${app.landing.correo-dominio}") String dominio) {
        var res = java.util.Arrays.stream(reservados.split(",")).map(Cidr::parse).toList();
        var verificador = new VerificadorDeLineaBase(new FabricaDeSondasSts(sts, rol, Region.US_EAST_1),
                new PresupuestosSdk(budgets, admin), Set.of(admin), Clock.systemUTC());
        return new ServicioLandingZone(new OrganizacionSdk(org), new PlanificadorDeCuentas(Cidr.parse(pool), res, dominio), verificador);
    }
}

@RestController
@RequestMapping("/cuentas")
class CuentasController {
    private final ServicioLandingZone servicio;

    CuentasController(ServicioLandingZone servicio) {
        this.servicio = servicio;
    }

    @PostMapping("/plan")
    PlanDeCuenta plan(@RequestBody SolicitudCuenta solicitud) {
        return servicio.preparar(solicitud);
    }

    @PostMapping
    ResponseEntity<Map<String, String>> crear(@RequestBody SolicitudCuenta solicitud) {
        return ResponseEntity.accepted().body(Map.of("idSolicitud", servicio.crear(servicio.preparar(solicitud))));
    }

    @GetMapping("/solicitudes/{id}")
    EstadoCreacion estado(@PathVariable String id) {
        return servicio.estado(id);
    }

    @GetMapping("/auditoria")
    ResponseEntity<InformeLineaBase> auditoria() {
        return servicio.ultimoInforme().map(ResponseEntity::ok).orElse(ResponseEntity.noContent().build());
    }

    @ExceptionHandler(IllegalArgumentException.class)
    ResponseEntity<Map<String, String>> invalido(IllegalArgumentException e) {
        return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    }

    @ExceptionHandler(IllegalStateException.class)
    ResponseEntity<Map<String, String>> conflicto(IllegalStateException e) {
        return ResponseEntity.status(409).body(Map.of("error", e.getMessage()));
    }
}

@Component
class AuditoriaNocturna {
    private final ServicioLandingZone servicio;

    AuditoriaNocturna(ServicioLandingZone servicio) {
        this.servicio = servicio;
    }

    @Scheduled(cron = "0 0 3 * * *", zone = "America/Lima")
    void auditar() {
        servicio.auditar();
    }
}
```

## 4. Spring WebFlux (reactivo)
Organizations y STS son clientes síncronos: cada operación se mueve a `boundedElastic`. La auditoría nocturna se lanza con un `Flux.interval` de 24 h sin solapamiento.
```java
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.Disposable;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
@RequestMapping("/v2/cuentas")
class CuentasReactivoController {
    private final ServicioLandingZone servicio;

    CuentasReactivoController(ServicioLandingZone servicio) {
        this.servicio = servicio;
    }

    @PostMapping("/plan")
    Mono<ResponseEntity<Object>> plan(@RequestBody SolicitudCuenta solicitud) {
        return Mono.fromCallable(() -> servicio.preparar(solicitud))
                .subscribeOn(Schedulers.boundedElastic())
                .<ResponseEntity<Object>>map(ResponseEntity::ok)
                .onErrorResume(IllegalArgumentException.class, e -> Mono.just(ResponseEntity.badRequest().body(Map.of("error", e.getMessage()))));
    }

    @GetMapping("/solicitudes/{id}")
    Mono<EstadoCreacion> estado(@PathVariable String id) {
        return Mono.fromCallable(() -> servicio.estado(id)).subscribeOn(Schedulers.boundedElastic());
    }

    @GetMapping("/auditoria")
    Mono<ResponseEntity<InformeLineaBase>> auditoria() {
        return Mono.fromSupplier(() -> servicio.ultimoInforme().map(ResponseEntity::ok).orElse(ResponseEntity.noContent().build()));
    }
}

@Component
class AuditoriaReactiva {
    private final ServicioLandingZone servicio;
    private Disposable bucle;

    AuditoriaReactiva(ServicioLandingZone servicio) {
        this.servicio = servicio;
    }

    @PostConstruct
    void iniciar() {
        bucle = Flux.interval(java.time.Duration.ofSeconds(30), java.time.Duration.ofHours(24))
                .onBackpressureDrop()
                .concatMap(t -> Mono.fromCallable(servicio::auditar).subscribeOn(Schedulers.boundedElastic()).onErrorResume(e -> Mono.empty()), 1)
                .subscribe();
    }

    @PreDestroy
    void detener() {
        bucle.dispose();
    }
}
```

## 5. Quarkus (imperativo)
```java
import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
class LandingProductores {
    @jakarta.enterprise.inject.Produces
    @Singleton
    BudgetsClient budgets() {
        return BudgetsClient.builder().region(Region.AWS_GLOBAL).build();
    }

    void cerrarBudgets(@jakarta.enterprise.inject.Disposes BudgetsClient c) {
        c.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioLandingZone landing(OrganizationsClient org, BudgetsClient budgets, StsClient sts,
                                @ConfigProperty(name = "app.landing.pool-cidr") String pool, @ConfigProperty(name = "app.landing.reservados") String reservados,
                                @ConfigProperty(name = "app.landing.cuenta-administracion") String admin, @ConfigProperty(name = "app.landing.rol-auditor") String rol,
                                @ConfigProperty(name = "app.landing.correo-dominio", defaultValue = "modalima.example") String dominio) {
        var res = java.util.Arrays.stream(reservados.split(",")).map(Cidr::parse).toList();
        var verificador = new VerificadorDeLineaBase(new FabricaDeSondasSts(sts, rol, Region.US_EAST_1),
                new PresupuestosSdk(budgets, admin), Set.of(admin), Clock.systemUTC());
        return new ServicioLandingZone(new OrganizacionSdk(org), new PlanificadorDeCuentas(Cidr.parse(pool), res, dominio), verificador);
    }
}

@Path("/cuentas")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
class CuentasResource {
    @Inject
    ServicioLandingZone servicio;

    @POST
    @Path("/plan")
    public Response plan(SolicitudCuenta solicitud) {
        try {
            return Response.ok(servicio.preparar(solicitud)).build();
        } catch (IllegalArgumentException e) {
            return Response.status(400).entity(Map.of("error", e.getMessage())).build();
        }
    }

    @POST
    public Response crear(SolicitudCuenta solicitud) {
        try {
            return Response.accepted(Map.of("idSolicitud", servicio.crear(servicio.preparar(solicitud)))).build();
        } catch (IllegalArgumentException e) {
            return Response.status(400).entity(Map.of("error", e.getMessage())).build();
        }
    }

    @GET
    @Path("/solicitudes/{id}")
    public EstadoCreacion estado(@PathParam("id") String id) {
        return servicio.estado(id);
    }

    @GET
    @Path("/auditoria")
    public Response auditoria() {
        return servicio.ultimoInforme().map(i -> Response.ok(i).build()).orElse(Response.noContent().build());
    }
}

@ApplicationScoped
class AuditoriaQuarkus {
    @Inject
    ServicioLandingZone servicio;

    @Scheduled(cron = "0 0 3 * * ?", timeZone = "America/Lima", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    void auditar() {
        servicio.auditar();
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.quarkus.scheduler.Scheduled;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

@Path("/v2/cuentas")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
class CuentasMutinyResource {
    @Inject
    ServicioLandingZone servicio;

    @POST
    @Path("/plan")
    public Uni<Response> plan(SolicitudCuenta solicitud) {
        return Uni.createFrom().item(() -> servicio.preparar(solicitud))
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool())
                .map(p -> Response.ok(p).build())
                .onFailure(IllegalArgumentException.class).recoverWithItem(e -> Response.status(400).entity(Map.of("error", e.getMessage())).build());
    }

    @GET
    @Path("/solicitudes/{id}")
    public Uni<EstadoCreacion> estado(@PathParam("id") String id) {
        return Uni.createFrom().item(() -> servicio.estado(id)).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}

@ApplicationScoped
class AuditoriaMutiny {
    @Inject
    ServicioLandingZone servicio;

    @Scheduled(cron = "0 0 3 * * ?", timeZone = "America/Lima", concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
    Uni<Void> auditar() {
        return Uni.createFrom().item(servicio::auditar)
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool())
                .onFailure().recoverWithNull()
                .replaceWithVoid();
    }
}
```

## 7. Permisos
| Servicio | Acciones | Recurso |
|---|---|---|
| Vending | `organizations:ListAccounts`, `ListParents`, `DescribeOrganizationalUnit`, `ListTagsForResource` | `*` (la API no admite recursos más finos) |
| Vending | `organizations:CreateAccount`, `DescribeCreateAccountStatus` | `*`; **solo** el rol de vending, con aprobación humana |
| Verificador | `sts:AssumeRole` | `arn:aws:iam::*:role/modalima-auditor` |
| Verificador | `budgets:ViewBudget` | Presupuestos de la cuenta de administración |
| `modalima-auditor` (en cada cuenta) | `cloudtrail:DescribeTrails`, `config:DescribeConfigurationRecorderStatus`, `ec2:GetEbsEncryptionByDefault` | `*`, solo lectura; confía únicamente en el rol del verificador |

## 8. Qué NO hacer desde Java
- No crees cuentas sin un plan revisado y sin un rol propio con aprobación: es casi irreversible.
- No reintentes `CreateAccount` a ciegas: consulta el estado de la solicitud; un correo repetido falla con `EMAIL_ALREADY_EXISTS`.
- No asignes CIDR «a ojo» ni sin considerar los rangos reservados (on-premises, laboratorios).
- No des por buena una comprobación que no pudo ejecutarse.
- No guardes credenciales asumidas: déjalas al proveedor, que las renueva solo.
- No llames a Organizations en cada petición HTTP: tiene límites bajos; usa el último informe en memoria.
- No ejecutes estos clientes síncronos en el bucle de eventos de WebFlux/Vert.x.
