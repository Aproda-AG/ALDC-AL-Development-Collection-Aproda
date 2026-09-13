# Construcción y prueba local del VSIX de ALDC

Esta guía documenta la extensión de VS Code y su relación con el repositorio
canónico de ALDC. Se revisó el 13 de septiembre de 2026 después de validar un
VSIX con los perfiles `bc28` y `bc29-native`.

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

`toolbox/` está ignorado por Git en ALDC, pero la extensión es un repositorio Git
independiente con remoto
`https://github.com/javiarmesto/aldc-vscode-extension.git`. Por ello, una prueba
completa requiere dos checkouts coordinados: ALDC como contenedor y la extensión
dentro de `toolbox/al-coding-agent-collection/`.

El empaquetador busca ALDC dos niveles por encima. También admite
`ALDC_REPO_ROOT` como ruta explícita y, si se clona la extensión de forma
independiente, puede empaquetar las plantillas preparadas que están versionadas.

Comprueba la relación antes de construir:

```powershell
$aldcRoot = 'C:\ALDC-Forge-Tests\ALDC-native29'
$extensionRoot = Join-Path $aldcRoot 'toolbox\al-coding-agent-collection'

git -C $aldcRoot rev-parse --show-toplevel
git -C $aldcRoot branch --show-current
git -C $aldcRoot rev-parse HEAD
git -C $extensionRoot rev-parse --show-toplevel
git -C $extensionRoot branch --show-current
git -C $extensionRoot rev-parse HEAD
```

Para esta adaptación, ambos repositorios usan la rama
`feat/canonical-bc29-al18`. Anota los dos SHA junto al VSIX generado.

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

El último comando debe mostrar el commit de ALDC que vayas a probar. Después clona
la rama coordinada de la extensión dentro del directorio ignorado `toolbox/`:

```powershell
$testExtension = Join-Path $testRepo 'toolbox\al-coding-agent-collection'

New-Item -ItemType Directory -Path (Split-Path $testExtension) -Force | Out-Null
git clone --branch $branch --single-branch `
  https://github.com/javiarmesto/aldc-vscode-extension.git $testExtension

git -C $testExtension status --short
git -C $testExtension branch --show-current
git -C $testExtension rev-parse HEAD
```

Si necesitas probar cambios locales de la extensión que todavía no están en su
rama, puedes usar `robocopy` como alternativa, excluyendo `.git`, `node_modules`,
`templates` y `*.vsix`. No mezcles ese método con el clon anterior.

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
| `docs/framework` | `templates/docs/framework` |
| `tools/bcquality` | `templates/tools/bcquality` |
| `tools/aldc-validate/index.js` y `package.json` | `templates/tools/aldc-validate` |
| `scripts/install.js` | raíz de la extensión, `install.js` |
| `scripts/native-profile.js` | raíz de la extensión, `native-profile.js` |
| `.github/copilot-instructions.md` | `templates/.github/copilot-instructions.md` y entrada de la extensión |
| `aldc.yaml` con `toolkitRoot: ".github"` | `templates/aldc-consumer.yaml` |

Los documentos auxiliares se toman de sus rutas actuales bajo `docs/`; una
preparación correcta no debe producir avisos de archivos ausentes.

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
git switch feat/canonical-bc29-al18
git pull --ff-only origin feat/canonical-bc29-al18
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
Get-Item $artifact\vsix-inspect\extension\native-profile.js
Get-Item $artifact\vsix-inspect\extension\templates\docs\framework\native-al-tools.md
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

En esa ventana, ejecuta `AL Collection: Install Toolkit to Workspace`, elige
`BC 29 native (AL 18)` y comprueba:

1. `.github/aldc-profile.json` declara `bc29-native`.
2. `.github/docs/framework/native-al-tools.md` existe.
3. Los agentes y prompts usan las herramientas `ms-dynamics-smb.al/*` previstas.
4. Al cambiar a `bc28`, la extensión pide confirmación antes de reemplazar los
   archivos administrados.

Repite la instalación en otro proyecto seleccionando `BC 28 compatible`. Conserva
los dos SHA, el nombre del VSIX, la salida de preparación y las versiones de VS
Code, Copilot y AL Language como evidencia.

## Perfil `bc29-native`: integración implementada

La rama coordinada de la extensión incorpora `native-profile.js`, el contrato
nativo y la selección BC28/BC29 en el comando de instalación. La selección queda
registrada en `aldc-profile.json`; un cambio de perfil sobre una instalación
existente requiere confirmación explícita.

Se validaron el empaquetado anidado y el independiente, la instalación extraída
por CLI de ambos perfiles, la proyección de herramientas nativas y el bloqueo de
un cambio de perfil sin reemplazo explícito. Sigue pendiente la prueba manual del
flujo visual en una instancia aislada de VS Code antes de publicar.

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
