# Plano — melhoria neural de imagens no leitor

Base: `docs/superpowers/specs/2026-11-04-neural-upscale-design.md` (aprovado em
2026-11-05).

## Meta da fase 1

Página visível processada em background por Real-CUGAN SE 2×, com pré-carga,
cache em disco/memória e fallback para o shader 2× atual. Windows x64 e Linux
x64. Modelo baixado no primeiro uso; embutir depois.

## Ordem de implementação

### 1. Base de plataforma

1. `lib/src/service/path_service.dart`
   - acrescentar `Directory? cacheDir;`
   - inicializar com `getApplicationCacheDirectory()` e fallback
     `appSupportDir/cache`.
2. `lib/src/widget/eh_image.dart`
   - registrar `codec.frameCount` por `cacheKey` num side table (novo
     `EHImageFrameCountRegistry`, no espírito do
     `EHImageAnimationGateRegistry`).
   - expor `frameCountFor(String key)`.

Aceite: um teste simples confirma que uma imagem estática fica com
`frameCount == 1` e um GIF com `> 1`.

### 2. Gerência de modelo

Novo `lib/src/service/neural_model_manager.dart`:

- `NeuralModelPlatform` (windows/linux) com nomes de binário e URL do zip.
- `ensureReady()`: procura instalação válida (pasta gerenciada ou
  `superResolutionSetting.modelDirectoryPath`); senão baixa e extrai.
- `binPath`, `modelDir(se|pro)`, `isReady`.
- Estado observável: `notDownloaded`, `downloading`, `ready`, `error` +
  progresso.
- Reutilizar `extractZipArchive` e `ehRequest.download`.
- Garantir bit `+x` no binário Linux.

Aceite: com a pasta vazia, baixa; com a pasta preenchida, não baixa de novo.

### 3. Serviço neural

Novo `lib/src/service/neural_upscale_service.dart`:

- `NeuralRequest` (source, cacheKey, priority, frameCount, sourceWidthHint,
  sourcePath).
- `cached(key)`.
- Fila serializada com prioridade; `cancelSession()`.
- Cache de memória LRU (192 MB) e disco (`cacheDir/neural_upscale`), LRU 2 GB.
- Regras de pulo: frameCount > 1, largura ≥ 1800, saída > 4096,
  `useSuperResolution`, modelo indisponível.
- Escolha 2×/3× (3× se largura < 900).
- Chave SHA-1 estável.
- Runner: `toByteData(png)` → temp → processo → decodifica → cache.
- `GpuJobLock` global compartilhado com `SuperResolutionService`.
- Log de tempo e cache hit/miss.

Aceite: unit tests de chave, LRU, regra de escala e pulos; manual com uma
página 1280 e uma 800.

### 4. Widget e integração no leitor

1. Novo `lib/src/widget/neural_upscaled_image.dart`:
   - mostra `source`; consulta cache; dispara pedido; troca quando chega.
   - geração para ignorar resultado antigo.
   - `clone()` antes de `toByteData`.
2. `lib/src/widget/eh_image.dart`:
   - novo `enableNeuralUpscale`;
   - se ligado e modelo pronto: `NeuralUpscaledImage`; senão `UpscaledImage`
     atual.
   - passar `priority` e `frameCount`.
3. `lib/src/pages/read/layout/base/base_layout.dart`:
   - calcular `enableNeuralUpscale = readSetting.enableNeuralUpscale.isTrue &&
     !readPageState.useSuperResolution && neuralModelManager.isReady`.
   - passar `priority` para a página atual (usar o índice já disponível no
     layout; se não houver, começar com `true` para todas e ajustar depois).
4. `lib/src/pages/read/read_page_logic.dart`:
   - no `onClose`, `neuralUpscaleService.cancelSession()` e limpar cache de
     memória.

Aceite: página aparece na hora; vira neural depois; ao trocar de página, o
pedido antigo não sobrescreve a nova.

### 5. Configurações e UI

1. `lib/src/setting/read_setting.dart`:
   - `enableNeuralUpscale` (false), `neuralUpscaleModel` (`se`/`pro`),
     `neuralUpscaleDenoise` (`auto`/`none`/`0`/`1`/`2`/`3`),
     `neuralUpscalePreload` (2).
   - getters/setters e serialização no `applyBeanConfig`/`toConfigString`.
2. `lib/src/pages/setting/read/setting_read_page.dart`:
   - seção “Melhoria neural (beta)”:
     - switch;
     - status + botão de download com progresso;
     - modelo (SE/Pro);
     - denoise (filtrado por modelo);
     - pré-carga;
     - GPU (nome + índice);
     - texto de ajuda.
3. i18n: `lib/src/l18n/pt_BR.dart` e `en_US.dart` (e as demais se o build
   exigir).

Aceite: ligar sem modelo abre o download; depois de pronto, o leitor usa.

### 6. Empacotamento (fase 1.5)

- Windows: copiar `realcugan-ncnn-vulkan.exe`, `vcomp140.dll` e modelos para o
  diretório do executável no build (CMake/pós-build).
- Linux: incluir `realcugan-ncnn-vulkan` + modelos no AppImage, com `+x`.
- `NeuralModelManager` procura primeiro nos assets embutidos e só baixa se
  não achar.
- Licenças: adicionar Real-CUGAN (MIT) e ncnn (BSD-3) ao `LicenseRegistry`.

## Testes

- `flutter analyze`
- `flutter test` (novos testes em `test/`)
- Manual: E-H 1280, Xlecx ~800, local ~600; medir primeira exibição, cache hit,
  memória e uso de GPU.
- Comparação visual SE × Pro × denoise 0/1 em 2–3 páginas reais.

## Riscos e mitigação

- Console no Windows → testar; se aparecer, `CREATE_NO_WINDOW`.
- Vulkan ausente no Linux → detectar no stderr e cair no shader com aviso.
- Lote + neural disputando GPU → `GpuJobLock`.
- Cache crescendo → LRU 2 GB e limpeza no startup.
- Texto alterado pelo modelo → opção Pro/SE e denoise; aviso na UI.
