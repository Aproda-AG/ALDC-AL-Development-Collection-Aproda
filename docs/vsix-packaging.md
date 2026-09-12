# Construcción y prueba local del VSIX de ALDC

Esta guía documenta la extensión local de VS Code que se mantiene fuera del árbol
versionado de ALDC. Se revisó el 12 de septiembre de 2026 con sus archivos
`toolbox/al-coding-agent-collection/package.json` y `prepare-package.js`.

## Ubicación y relación con el repositorio

La extensión debe vivir dentro del checkout que se quiere empaquetar:

```text
<ALDC checkout>/
  packages/foundation/
  scripts/
  toolbox/al-coding-agent-collection/
    package.json
    prepare-package.js
    extension.js
    templates/              # generado, no fuente
```

`toolbox/` está ignorado por Git en ALDC. Por ello, cambiar de rama o crear un
checkout de prueba no lleva la extensión automáticamente. Copia o clona el árbol
local de la extensión bajo `toolbox/al-coding-agent-collection/` del checkout que
vayas a construir. El empaquetador calcula la raíz como dos niveles por encima de
su propio directorio; no funcionará igual si se ejecuta desde una carpeta externa.

Comprueba la relación antes de construir:

```powershell
$aldcRoot = 'C:\ALDC-Forge-Tests\ALDC-native29'
$extensionRoot = Join-Path $aldcRoot 'toolbox\al-coding-agent-collection'

git -C $aldcRoot rev-parse --show-toplevel
git -C $aldcRoot branch --show-current
git -C $aldcRoot rev-parse HEAD
git -C $extensionRoot rev-parse --show-toplevel
```

Para esta adaptación, la rama es `feat/canonical-bc29-al18`. Anota el SHA que
devuelve `rev-parse HEAD` junto al VSIX generado.

## Paso previo: crear el checkout de prueba

Parte de tu checkout habitual, pero no construyas el VSIX dentro de él. Crea una
copia independiente de la rama y conserva el checkout habitual tal como está.

```powershell
$sourceRepo = 'C:\Users\JavierArmestoGonzále\Documents\AL\ALDC'
$testRepo = 'C:\ALDC-Forge-Tests\ALDC-native29'
$branch = 'feat/canonical-bc29-al18'

git -C $sourceRepo fetch origin $branch
git clone --branch $branch --single-branch `
  https://github.com/javiarmesto/ALDC-AL-Development-Collection.git $testRepo

git -C $testRepo status --short
git -C $testRepo branch --show-current
git -C $testRepo rev-parse HEAD
```

El último comando debe mostrar el commit que vayas a probar. En el checkout nuevo
no aparecerá `toolbox/`, porque se excluye de Git. Copia la fuente de la extensión
desde tu checkout habitual. No copies `node_modules`, `templates` ni artefactos
VSIX: se regeneran en los pasos siguientes.

```powershell
$sourceExtension = Join-Path $sourceRepo 'toolbox\al-coding-agent-collection'
$testExtension = Join-Path $testRepo 'toolbox\al-coding-agent-collection'

robocopy $sourceExtension $testExtension /E /XD node_modules templates .git /XF *.vsix
if ($LASTEXITCODE -ge 8) { throw "No se pudo copiar la extensión (robocopy: $LASTEXITCODE)" }

Get-ChildItem $testExtension -File -Name
```

`robocopy` devuelve códigos de `0` a `7` incluso cuando ha copiado archivos; solo
`8` o más indica un error. Si el directorio `C:\ALDC-Forge-Tests\ALDC-native29`
ya existe, elige otro nombre o elimínalo únicamente si sabes que es una copia de
prueba prescindible.

## Contrato actual de `prepare-package.js`

El script elimina `templates/` y la reconstruye. Por eso no se edita ni se usa
como fuente de verdad el contenido de esa carpeta.

| Origen en ALDC | Destino dentro del VSIX |
| --- | --- |
| `packages/foundation/agents` | `templates/agents` |
| `packages/foundation/instructions` | `templates/instructions` |
| `packages/foundation/prompts` | `templates/prompts` |
| `packages/foundation/skills` | `templates/skills` |
| `docs/templates` | `templates/docs/templates` |
| `docs/schema` | `templates/docs/schema` |
| `tools/bcquality` | `templates/tools/bcquality` |
| `tools/aldc-validate/index.js` y `package.json` | `templates/tools/aldc-validate` |
| `scripts/install.js` | raíz de la extensión, `install.js` |
| `aldc.yaml` con `toolkitRoot: ".github"` | `templates/aldc-consumer.yaml` |

También intenta copiar varios archivos heredados (`al-development.md`,
`getting-started.md`, etc.). Si no existen, escribe un aviso y continúa. No deben
interpretarse como un fallo de la preparación actual.

El `package.json` de la extensión declara `vscode:prepublish` como
`node prepare-package.js`. Por tanto, `vsce package` ejecuta la preparación antes
de crear el VSIX. La extensión publica cuatro comandos: instalar, actualizar,
validar y mostrar la guía inicial; las `chatSkills` se leen de `templates/skills`.

## Construcción reproducible desde la rama

Trabaja desde un checkout separado para no mezclar la extensión publicada ni tu
instalación habitual con la prueba:

```powershell
$repo = 'C:\ALDC-Forge-Tests\ALDC-native29'
$extension = Join-Path $repo 'toolbox\al-coding-agent-collection'
$artifact = Join-Path $repo 'artifacts'

Set-Location $repo
git switch feat/canonical-bc29-al18
git pull --ff-only origin feat/canonical-bc29-al18
node scripts/sync-foundation.js
node scripts/sync-foundation.js --check

Set-Location $extension
npm ci
npm run prepare-package
npx @vscode/vsce package --out (Join-Path $artifact 'aldc-bc29-native-test.vsix')
```

`vsce package` solo genera un archivo VSIX; no lo publica. Instala `@vscode/vsce`
globalmente si prefieres el comando `vsce package`:

```powershell
npm install --global @vscode/vsce
```

No cambies la versión del manifiesto solo para una prueba local. Diferencia el
artefacto con el nombre del archivo y el SHA de la rama. Antes de usarlo, comprueba
que el archivo contiene las primitivas esperadas:

```powershell
$vsixZip = Join-Path $artifact 'aldc-bc29-native-test.zip'
Copy-Item -LiteralPath (Join-Path $artifact 'aldc-bc29-native-test.vsix') -Destination $vsixZip -Force
Expand-Archive -LiteralPath $vsixZip -DestinationPath (Join-Path $artifact 'vsix-inspect') -Force
Get-ChildItem $artifact\vsix-inspect\extension\templates\agents
Get-ChildItem $artifact\vsix-inspect\extension\templates\skills\skill-migrate\references
```

## Prueba aislada en VS Code

Usa directorios de usuario y extensiones distintos para que no interfiera con tu
VS Code de trabajo. Sustituye `code-insiders` por `code` si corresponde a la
versión que quieres comprobar.

```powershell
$vsix = 'C:\ALDC-Forge-Tests\ALDC-native29\artifacts\aldc-bc29-native-test.vsix'
$vscodeUser = 'C:\ALDC-Forge-Tests\vscode-user-vsix'
$vscodeExtensions = 'C:\ALDC-Forge-Tests\vscode-extensions-vsix'

code-insiders --user-data-dir $vscodeUser --extensions-dir $vscodeExtensions --install-extension $vsix --force
code-insiders --user-data-dir $vscodeUser --extensions-dir $vscodeExtensions C:\ALDC-Forge-Tests\Proyecto-Prueba
```

En esa ventana, ejecuta `AL Collection: Install Toolkit to Workspace`. Comprueba
que crea la estructura `.github` en el proyecto de prueba y que las skills de
`templates/skills` están presentes. Conserva el SHA, el nombre del VSIX, la salida
de la preparación y la versión de VS Code/Copilot/AL Language como evidencia.

## Perfil `bc29-native`: integración pendiente en la extensión

La rama implementa el perfil BC29 en `scripts/install.js` y
`scripts/native-profile.js`. El perfil proyecta agentes y prompts en tiempo de
instalación y requiere el contrato `docs/framework/native-al-tools.md`.

El empaquetador local conocido incorpora las primitivas compartidas mediante
`packages/foundation` y copia `install.js`, pero **no incorpora todavía**
`native-profile.js` ni el contrato nativo. Además, el comportamiento de los
comandos de VS Code depende de `extension.js`, que debe confirmar cómo instala
desde `templates/`.

Por ello, con el script documentado el VSIX permite probar las skills e
instrucciones actualizadas, pero no acredita que la orden de instalación de la
extensión pueda seleccionar `bc29-native`. Antes de presentar el perfil BC29 en
la extensión, revisa `extension.js` y aplica estas condiciones:

1. Empaquetar los agentes y prompts fuente que utiliza la proyección.
2. Empaquetar `native-profile.js` junto al código que lo carga, o integrar su
   función de proyección en la extensión de forma equivalente y comprobada.
3. Empaquetar `docs/framework/native-al-tools.md` en la ubicación que espera el
   instalador.
4. Añadir una selección explícita BC28 / BC29-native al comando de instalación,
   conservarla en el marcador `aldc-profile.json` y requerir reemplazo explícito
   al cambiar de perfil.
5. Construir un VSIX nuevo e instalarlo en la instancia aislada; probar una
   instalación BC28, BC29, cambio con `--force` o su equivalente, y retorno a BC28.

No copies agentes BC29 manualmente a `packages/foundation`: esa carpeta es un
espejo de las fuentes canónicas y no representa un perfil. Ejecuta siempre
`node scripts/sync-foundation.js` después de editar raíz y antes de empaquetar.

## Mantenimiento

Cuando cambie una primitiva canónica:

```powershell
Set-Location $repo
node scripts/sync-foundation.js
node scripts/sync-foundation.js --check
node scripts/test-native-profile.js

Set-Location $extension
npm run prepare-package
npx @vscode/vsce package --out (Join-Path $artifact 'aldc-local-test.vsix')
```

Si se cambia el empaquetador local o `extension.js`, actualiza esta guía con la
ruta de entrada, los archivos que deben viajar en el VSIX y la prueba que confirma
la selección de perfil.
