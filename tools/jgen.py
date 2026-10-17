"""Genera las secciones 3-6 de uso-en-java.md (Spring MVC, WebFlux, Quarkus, Mutiny) a partir de una descripción.
endpoints: lista de dicts {n: nombre, v: GET|POST|PUT, p: '/sub', args: [(tipo, nombre, 'q'|'b'|'p')], ret: 'Tipo', call: 'expr con s', cpu: bool}"""

def _imps(lines):
    return "\n".join(sorted(set(lines)))

def _args_spring(args):
    out = []
    for t, n, k in args:
        a = {'q': '@RequestParam ', 'b': '@RequestBody ', 'p': '@PathVariable '}[k]
        out.append(f"{a}{t} {n}")
    return ", ".join(out)

def _args_jaxrs(args):
    out = []
    for t, n, k in args:
        a = {'q': f'@QueryParam("{n}") ', 'b': '', 'p': f'@PathParam("{n}") '}[k]
        out.append(f"{a}{t} {n}")
    return ", ".join(out)

def secciones(ns, ruta, servicio, spring_imports, spring_beans, q_imports, q_fields, q_producer, endpoints, nota_webflux=""):
    verbs = {e['v'] for e in endpoints}
    # ---------- Spring MVC
    si = ["org.springframework.web.bind.annotation.RequestMapping", "org.springframework.web.bind.annotation.RestController",
          "org.springframework.context.annotation.Bean", "org.springframework.context.annotation.Configuration"]
    for v in verbs:
        si.append(f"org.springframework.web.bind.annotation.{v.title()}Mapping")
    kinds = {k for e in endpoints for _, _, k in e['args']}
    if 'q' in kinds: si.append("org.springframework.web.bind.annotation.RequestParam")
    if 'b' in kinds: si.append("org.springframework.web.bind.annotation.RequestBody")
    if 'p' in kinds: si.append("org.springframework.web.bind.annotation.PathVariable")
    imp = _imps([f"import {i};" for i in si] + spring_imports)
    mvc = [f"{imp}\n\n@Configuration\nclass {ns}Configuracion {{\n\n{spring_beans.rstrip()}\n}}\n",
           f"@RestController\n@RequestMapping(\"{ruta}\")\nclass {ns}Controlador {{\n\n    private final {servicio} s;\n\n    {ns}Controlador({servicio} s) {{\n        this.s = s;\n    }}\n"]
    for e in endpoints:
        mvc.append(f"    @{e['v'].title()}Mapping(\"{e['p']}\")\n    {e['ret']} {e['n']}({_args_spring(e['args'])}) {{\n        return {e['call']};\n    }}\n")
    mvc.append("}")
    # ---------- WebFlux
    wi = ["reactor.core.publisher.Mono", "reactor.core.scheduler.Schedulers",
          "org.springframework.web.bind.annotation.RequestMapping", "org.springframework.web.bind.annotation.RestController"]
    for v in verbs: wi.append(f"org.springframework.web.bind.annotation.{v.title()}Mapping")
    if 'q' in kinds: wi.append("org.springframework.web.bind.annotation.RequestParam")
    if 'b' in kinds: wi.append("org.springframework.web.bind.annotation.RequestBody")
    if 'p' in kinds: wi.append("org.springframework.web.bind.annotation.PathVariable")
    if any('List<' in e['ret'] for e in endpoints): wi.append("java.util.List")
    if any('Map<' in e['ret'] for e in endpoints): wi.append("java.util.Map")
    wf = [f"{_imps([f'import {i};' for i in wi] + [l for l in spring_imports if any(x in l for x in ('java.util', 'oci', 'com.oracle', 'com.google'))])}\n\n@RestController\n@RequestMapping(\"/reactivo{ruta}\")\nclass {ns}ReactivoControlador {{\n\n    private final {servicio} s;\n\n    {ns}ReactivoControlador({servicio} s) {{\n        this.s = s;\n    }}\n"]
    for e in endpoints:
        sub = "" if e.get('cpu') else ".subscribeOn(Schedulers.boundedElastic())"
        wf.append(f"    @{e['v'].title()}Mapping(\"{e['p']}\")\n    Mono<{e['ret']}> {e['n']}({_args_spring(e['args'])}) {{\n        return Mono.fromCallable(() -> {e['call']}){sub};\n    }}\n")
    wf.append("}")
    # ---------- Quarkus
    qi = ["jakarta.enterprise.context.ApplicationScoped", "jakarta.inject.Inject", "jakarta.inject.Singleton", "jakarta.ws.rs.Path",
          "jakarta.ws.rs.core.MediaType", "org.eclipse.microprofile.config.inject.ConfigProperty"]
    for v in verbs: qi.append(f"jakarta.ws.rs.{v}")
    if 'q' in kinds: qi.append("jakarta.ws.rs.QueryParam")
    if 'p' in kinds: qi.append("jakarta.ws.rs.PathParam")
    if 'b' in kinds: qi.append("jakarta.ws.rs.Consumes")
    qi_all = _imps([f"import {i};" for i in qi] + q_imports)
    fields = "\n\n".join(f"    @ConfigProperty(name = \"{k}\")\n    {t} {n};" for t, n, k in q_fields)
    qk = [f"// (clase reutilizada en los bloques siguientes)\n{qi_all}\n\n@ApplicationScoped\nclass {ns}Productores {{\n\n{fields}\n\n    @jakarta.enterprise.inject.Produces\n    @Singleton\n{q_producer.rstrip()}\n}}\n",
          f"@Path(\"{ruta}\")\n@jakarta.ws.rs.Produces(MediaType.APPLICATION_JSON)\nclass {ns}Recurso {{\n\n    @Inject\n    {servicio} s;\n"]
    for e in endpoints:
        cons = "    @Consumes(MediaType.APPLICATION_JSON)\n" if any(k == 'b' for _, _, k in e['args']) else ""
        qk.append(f"    @{e['v']}\n    @Path(\"{e['p']}\")\n{cons}    public {e['ret']} {e['n']}({_args_jaxrs(e['args'])}) {{\n        return {e['call']};\n    }}\n")
    qk.append("}")
    # ---------- Mutiny
    mi = ["io.smallrye.mutiny.Uni", "io.smallrye.mutiny.infrastructure.Infrastructure", "jakarta.inject.Inject", "jakarta.ws.rs.Path"]
    for v in verbs: mi.append(f"jakarta.ws.rs.{v}")
    if 'q' in kinds: mi.append("jakarta.ws.rs.QueryParam")
    if 'p' in kinds: mi.append("jakarta.ws.rs.PathParam")
    if any('List<' in e['ret'] for e in endpoints): mi.append("java.util.List")
    if any('Map<' in e['ret'] for e in endpoints): mi.append("java.util.Map")
    mu = [f"{_imps([f'import {i};' for i in mi] + [l for l in q_imports if any(x in l for x in ('java.util', 'oci', 'com.oracle', 'com.google'))])}\n\n@Path(\"/reactivo{ruta}\")\n@jakarta.ws.rs.Produces(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)\nclass {ns}RecursoReactivo {{\n\n    @Inject\n    {servicio} s;\n"]
    for e in endpoints:
        cons = "    @jakarta.ws.rs.Consumes(jakarta.ws.rs.core.MediaType.APPLICATION_JSON)\n" if any(k == 'b' for _, _, k in e['args']) else ""
        sub = "" if e.get('cpu') else ".runSubscriptionOn(Infrastructure.getDefaultWorkerPool())"
        mu.append(f"    @{e['v']}\n    @Path(\"{e['p']}\")\n{cons}    public Uni<{e['ret']}> {e['n']}({_args_jaxrs(e['args'])}) {{\n        return Uni.createFrom().item(() -> {e['call']}){sub};\n    }}\n")
    mu.append("}")
    nw = (nota_webflux + "\n") if nota_webflux else "El SDK síncrono bloquea: se aísla en `boundedElastic`; el trabajo de CPU puro no lo necesita.\n"
    return f"""## 3. Spring MVC (imperativo)
```java
{chr(10).join(mvc)}
```

## 4. Spring WebFlux (reactivo)
{nw}```java
{chr(10).join(wf)}
```

## 5. Quarkus (imperativo)
```java
{chr(10).join(qk)}
```

## 6. Quarkus reactivo (Mutiny)
```java
{chr(10).join(mu)}
```
"""
