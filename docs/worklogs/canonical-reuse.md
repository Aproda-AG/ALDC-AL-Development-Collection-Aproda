# Continuación de ALDC canónico

Entrega activa: handoff 02, entrega 1 de empaquetado. Fecha: 2026-09-14.
Handoff 01 integrado: PR #97, merge `2f7f31a42ba8fe93eaeb8309ba582745a5ccb527`.
Su rama se retiró tras comprobar integración; main y sus checks quedaron correctos.
El usuario autorizó continuar handoff 02. Doctor y Spec corresponden a las siguientes
entregas y no se implementan en este incremento.

## Base y revisión

- Canónico: `javiarmesto/ALDC-AL-Development-Collection`.
- Main inicial: `c8cb3c078f10a993194c0807329faecadfc60466`.
- Head inicial #97: `3a35dc5c2940d14f3113bdf02f22db1e9f86d791`.
- Se comprobó que #97 estaba abierta, draft y era la única PR abierta del
  canónico. Sin revisiones ni hilos bloqueantes. Se leyeron cuerpo y comentarios,
  los 122 archivos de la lista completa (páginas de 100 y 22), diff de fuentes,
  instalador, proyector, generadores y workflows. No hay AGENTS.md en este árbol.
- Se conserva la misma rama, sin rebase ni restauración de snapshots.
- El commit de integración, checks finales y estado de la rama se consultan en
  [PR #97](https://github.com/javiarmesto/ALDC-AL-Development-Collection/pull/97).
  La integración queda condicionada a los checks del head corregido; la rama
  solo se retira tras comprobar que ese head es ancestro de main.

## Correcciones de esta revisión

1. `scripts/native-profile.js` rechazaba frontmatter CRLF. Se reprodujo el fallo
   con el Conductor y se corrigió normalizando solo para la proyección y
   restaurando el final de línea original. Se conserva el cuerpo completo.
2. El generador CLI dejaba `TodoWrite` sin traducir cuando no llevaba backticks.
   Se corrigió en el generador y se regeneró el comando de memoria.
3. Las instrucciones instaladas y la ayuda mezclaban recuentos antiguos; se
   ajustaron al inventario, al orden arquitectura → spec para MEDIUM/HIGH y al
   carácter opcional de BCQuality. Foundation se regeneró desde la fuente.
4. La revisión automática Copilot revisó 126/126 archivos. Se corrigieron sus
   hallazgos de payload npm, mínimo Node, ramas de despliegue del build nativo,
   operaciones ficticias de setup/contexto/perfilado y enlaces de reglas CLI.
   `test:package` valida el archivo npm local extraído con dependencias del
   lockfile, sin publicación; se añadió este gate al workflow de validación.
5. Las guías separan main canónico de la rama de la extensión y explican las
   sobrescrituras reales. No se presenta vuelta de perfil como restauración.

## Comprobaciones ejecutadas y límites

Linux, Node `v24.19.0`. `npm ci --no-audit --no-fund` terminó correctamente con el
lockfile existente; el intento offline previo falló por falta de caché js-yaml.
No se cambiaron versiones de dependencias. Se alineó `engines.node` a `>=20.0.0`
en package.json y lockfile, junto al README; Node 14 deja de ser un mínimo anunciado.

| Comprobación | Resultado local |
| --- | --- |
| `npm run validate` | 0 errores de colección, 77 avisos preexistentes; 214 comprobaciones de perfil y 210 de empaquetado CLI |
| `node scripts/check-conformance.js` | 57 comprobaciones superadas |
| `node scripts/sync-foundation.js --check` | 71 archivos consistentes |
| `node scripts/sync-claude-workspace.js --check` | 40 archivos consistentes |
| `node scripts/sync-copilot-cli.js --check` | 52 archivos consistentes, sin drift |
| `git diff --check` | Correcto |
| `npm run test:package` | Archivo npm local extraído y validado offline: 214 checks de perfil y 210 CLI; dependencias instaladas desde lockfile |

Las instalaciones se ejecutaron únicamente en fixtures temporales: BC28 por
omisión, BC29 nuevo, rechazo de mezcla sin force, actualización sin perfil,
retorno a BC28, destino alternativo e instalación desde fuentes CRLF. Se verificó
la conservación de memoria, manifest de App/Test, fuentes AL y settings de VS Code.

| Operación | Personalizaciones de toolkit/configuración |
| --- | --- |
| `install --yes` sin force, mismo perfil | Conserva archivos existentes porque los omite; no es una actualización completa |
| `install --force --yes` | Sobrescribe `aldc.yaml`, `aldc.code-workspace`, entrada Copilot e instrucciones; requiere copia/revisión previa |
| Cambio/retorno de perfil con force | Cambia contratos; conserva memoria y proyecto AL, pero no restaura personalizaciones sobrescritas |

CRLF se probó sobre Linux, no en una sesión Windows. No están disponibles Claude,
Copilot CLI ni VS Code ejecutable; el comando `code` es un wrapper que indica que
no está instalado. No se verificaron descubrimiento/carga real de roles, lectura
por el modelo, compilación App/Test ni runner BC. Architect y Conductor largos
siguen pendientes de carga completa por host; no se han recortado. Se comprobaron
permisos/referencias estáticamente, sin afirmar operación nativa observada.

La observación sobre `Write` → `edit` se evaluó contra la
[tabla oficial de alias](https://docs.github.com/en/copilot/reference/custom-agents-configuration#tool-aliases):
Write es alias de edit. Claude Write y Bash ya permiten sobrescribir archivos;
no existía una barrera de rutas que la conversión pudiera conservar. Se mantiene
la responsabilidad de Dredd/Triage de escribir solo sus informes y se documenta
que los permisos del host son necesarios: no se promete sandbox por rol. No se
rediseñan sus responsabilidades ni se introducen herramientas ficticias.

No se ejecutó `test-local-install.js`: depende del checkout de la extensión y
prepara su paquete. La PR externa
[aldc-vscode-extension #1](https://github.com/javiarmesto/aldc-vscode-extension/pull/1)
seguía abierta en `adb0f26a5008d127c14c05938fb8723a244900b2` al consultar; queda
fuera de esta autorización. No hay release, tag, publicación ni despliegue BC.

Automatizaciones: el workflow de documentación está activo y un merge a main
activa su publicación habitual en GitHub Pages. El linter versionado usa fix y
puede escribir en PRs no draft, pero su estado remoto consultado fue
`disabled_manually`; no se reactivó ni modificó esa configuración. Release solo
se dispara por tag o ejecución manual. Branch main figura sin protección y no
hay rulesets; el endpoint administrativo de protección devuelve 403, sin intentar
cambiar protecciones. Los validadores aplicables se respetan igualmente.

## Delta concreto para la siguiente entrega de empaquetado

Fuente de consulta: [EXTRACTION.md](https://github.com/javiarmesto/ALDC-Research-Lab/blob/0f49d44a99f626a5e8a88d316b7041bfbc6860fb/research/canonical-reuse-001/EXTRACTION.md)
y `donors.json` en el mismo SHA. Lab se consultó, no se modificó.

Ya existe: selección BC28/BC29 en Chat, contratos terminales, plugin Claude,
CLI separado con diez agentes/diez comandos, modelos por superficie, traducción
de reglas, referencias empaquetadas y los tres generadores con checks de drift.
No hace falta copiar otros generadores ni las primitivas de Graph para repetirlo.

1. **Procedencia e inicialización:** comparar `scripts/sync.mjs`,
   `provenance.json`, `scripts/init.mjs` y `hooks/session-context.mjs` de
   `plugins/claude-code/aldc-graph/` en Lab `b2ce9d9f137fc92574261317294ca2d585beb74b`.
   Añadir solo procedencia/hash y contexto inicial útil a los mecanismos actuales.
   Contrastar `build_copilot_commands.py` con el generador CLI existente sin
   introducir uno paralelo.
2. **Instalación segura y recuperación:** adaptar lo necesario del motor y tests
   `experiments/chat-install-001/` en `0c2a14731507c24782718cc739c74676b3528f17`.
   Faltan detección de colisiones/drift del consumidor y backup/restauración cuando
   se prometan. La escritura atómica por archivo no garantiza rollback global.
3. **Codex canónico:** adaptar `plugins/codex/aldc-graph/skills/aldc-graph/`
   (`install_runtime.py`, locks y bloque gestionado) del mismo donante `b2ce9d9`.
   Regenerar roles desde canónico y excluir overlay/runtime Graph. Recuperar
   `run_python.ps1` solo si este adaptador necesita Python, sin instalarlo ni
   cambiar PATH. #97 no añade compatibilidad Codex.
4. **Prueba por host:** verificar carga completa y procedencia de roles/comandos,
   actualización con memoria/personalizaciones y ausencia de duplicados en
   proyectos aislados. Revisar después la PR externa del VSIX si se autoriza;
   regenerar sus plantillas desde el main integrado. No publicar como parte de
   estas pruebas ni certificar hosts por contar archivos.

No copiar DAG, Evidence Store, Context Envelope, fingerprints por transición,
Run Health Graph ni runtime completo. Doctor y Spec Agent siguen fuera de #97.


## Handoff 02 — entrega 1 implementada

Base: main `2f7f31a42ba8fe93eaeb8309ba582745a5ccb527`, sin PR abiertas al comenzar.
Rama única: `feat/canonical-plugin-packaging`, [PR #100](https://github.com/javiarmesto/ALDC-AL-Development-Collection/pull/100). Se preserva el main integrado y no
se reabre #97. Lab y PR externa del VSIX se mantienen sin cambios.

- Motor común de planificación, recibos/hash, colisiones visibles y backup/rollback
  usado por el instalador Chat existente y la inicialización de los tres terminales.
  Los archivos gestionados intactos se actualizan. La memoria y las personalizaciones
  se conservan; force reemplaza con respaldo. No se instalan dependencias como
  efecto del inicializador. Verificación de drift y recuperación tienen comandos.
- Procedencia de fuentes y payload en los paquetes Claude, CLI y Codex, con SHA-256
  y normalización LF/CRLF limitada. Se amplía el generador CLI existente. Plantillas
  usadas por workflows incluidas; no se copia otro generador Python.
- Claude inicializa reglas y bloque propio en CLAUDE.md; SessionStart aporta contexto
  de ruta solo en proyectos AL y no escribe. No se copian hooks a otros hosts.
- Codex regenera diez perfiles TOML y un skill ALDC con referencias de roles,
  workflows, reglas y dominio. Bootstrap con AGENTS.override.md/AGENTS.md y memoria;
  conserva modelo, razonamiento, permisos, sandbox y MCP del padre. Sin overlay,
  runtime ni identidad Graph. Las referencias de dominio no se registran como
  skills duplicados. No se registra Marketplace ni se instala en esta sesión.

Comprobaciones locales: 214 checks de perfil, 226 de empaquetado CLI, 14 pruebas
conductuales de instalación/recuperación, 57 de conformance y 71 archivos Foundation.
Se probó fallo parcial con restauración de archivos y recibo, incluida interrupción
durante el propio rollback y recuperación posterior; rollback encadenado,
memoria editada, colisiones persistentes, backup corrupto, lock activo, symlink,
contenido manipulado y fuentes CRLF. TOML analizado con Python stdlib: diez perfiles
con cuerpo completo y un único SKILL.md descubrible. Validadores plugin/skill pasan.
El archivo npm se extrajo y pasó validate offline con sus propios contenidos.
Claude mirror y los generadores quedan sincronizados. CI y revisión remota se
consultan en la PR de esta rama antes de integrar.

Límites: sin ejecutables utilizables VS Code, Claude, Copilot CLI o Codex. Sin
carga real certificada ni compilación App/Test, ejecución funcional o despliegue BC.
Conductor/Architect completos permanecen por encima de 29k caracteres; no se
recortan para pasar una comprobación estática. Recuperación comprobada en Linux;
Windows y los hosts reales quedan pendientes. No se promete durabilidad ante
apagón ni protección contra edición concurrente adversaria.

Procedencia exacta y transformaciones: [plugin-packaging.md](../plugin-packaging.md).
Se leyeron el motor y ambas suites del donante Chat antes de adaptarlo. Las suites
Graph del donante se analizaron como evidencia, no se ejecutaron ni trasladaron.

**Delta de empaquetado restante:** comprobar descubrimiento/carga completa de
roles y reglas por host, recarga de caché sin duplicados y actualización/rollback
real en Windows. Resolver solo fallos observados en cada superficie. Coordinar el
VSIX externo para regenerar desde main cuando proceda. El siguiente incremento
implementable es Doctor canónico; después Spec Agent y sus adaptadores.
