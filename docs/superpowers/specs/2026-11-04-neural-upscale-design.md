# Melhoria neural de imagens no leitor — design

Data: 2026-11-04
Status: aprovado em 2026-11-05, com dois ajustes: Linux x64 na fase 1 e
embutir binário + modelos depois da validação.

## 1. Intenção

O leitor hoje deixa a página legível com um upscale 2× de filtro (Catmull-Rom +
CAS, ~50–120 ms por página). Isso resolve nitidez, mas não recupera detalhe:
galerias de baixa resolução continuam com traço mole, textura lavada e texto
pequeno difícil de ler, venham do E-Hentai, do Xlecx ou de arquivo local.

O objetivo é acrescentar um upscaler neural **sob demanda**, que processa a
página visível (e as próximas) em background, guarda o resultado em cache e o
mostra assim que fica pronto. O filtro atual continua como fallback imediato.
O recurso é agnóstico de fonte porque trabalha no bitmap já decodificado.

O que se espera de ganho real: traço mais definido, textura e degradês
reconstruídos de forma plausível, menos artefato de JPEG. O que **não** se
espera: recuperar informação que não existe. Texto minúsculo pode ficar mais
legível, mas o modelo pode alterar levemente a forma das letras; não é OCR.

## 2. O que existe hoje

- `lib/src/service/upscale_service.dart` — shader 2× (bicúbico Catmull-Rom) +
  CAS, cache LRU em memória (192 MB), fila serializada, limite de 4096 px.
- `lib/src/widget/upscaled_image.dart` — mostra a imagem original e troca pela
  2× quando o shader termina.
- `lib/src/widget/eh_image.dart` — `enableUpscale` envolve a imagem construída.
- `lib/src/pages/read/layout/base/base_layout.dart` — passa
  `enableUpscale: readSetting.enableUpscale.isTrue && !useSuperResolution`.
- `lib/src/setting/read_setting.dart` — `enableUpscale` (bool, padrão `true`).
- `lib/src/service/super_resolution_service.dart` — recurso herdado do JHenTai:
  baixa um zip com binário ncnn-vulkan + modelos e processa a **galeria
  baixada inteira**, offline, em **4× PNG**, com um processo por imagem. Só
  desktop. O resultado 4× é reduzido na tela, então o ganho percebido é baixo.
- `lib/src/setting/super_resolution_setting.dart` — modelos `ESRGAN`,
  `ESRGAN_ANIME`, `CUGAN`; pasta do modelo; `gpuId`.
- Zoom máximo do leitor: 2,5× (`BaseLayoutLogic.maxZoomScale`).

Bug encontrado no caminho antigo: para o CUGAN o comando passa
`-n realcugan`, mas `-n` é o nível de denoise (`-1/0/1/2/3`), não o nome do
modelo. O binário interpreta como `0` (conservative). O modelo é escolhido por
`-m <pasta>`. O novo caminho não deve repetir esse comando.

## 3. Objetivos, não-objetivos e anti-objetivos

### Objetivos

- Melhorar de verdade páginas de baixa resolução no zoom, no Windows e no
  Linux x64.
- Funcionar para qualquer fonte: E-Hentai, Xlecx, download local, arquivo.
- Não travar a leitura: a página atual aparece na hora; a versão neural entra
  quando fica pronta.
- Pré-carregar as páginas seguintes e cachear em disco; reler é instantâneo.
- Manter o filtro 2× atual como fallback e como opção rápida.
- Configuração simples: ligar/desligar, modelo, denoise, pré-carga, GPU.

### Não-objetivos (fase 1)

- Android/iOS. Windows e Linux x64 entram na fase 1; mobile fica para uma fase
  posterior.
- Processar tiles da região visível em tempo real (isso é a fase 3).
- Nuvem, upload de imagem, API externa.
- OCR ou reconstrução de texto.
- Substituir o recurso de super resolution em lote; ele continua existindo.

### Anti-objetivos

- Não aplicar CAS por cima do resultado neural (halos e over-sharpen).
- Não modificar a pasta da galeria baixada; o cache neural fica separado.
- Não baixar modelo sem o usuário saber.
- Não processar GIF/animação, imagem já grande ou página fora da tela sem
  prioridade.
- Não deixar o processo consumir GPU indefinidamente quando o app perde foco.

## 4. Restrições e medições

Máquina de referência: Ryzen 5 5600H (6C/12T), 15,4 GB RAM, NVIDIA GTX 1650
4 GB (Vulkan GPU 0) + AMD Radeon iGPU (Vulkan GPU 1), Windows.

Medições feitas em 2026-11-04, página sintética de 1280×1800 gerada a partir
da arte de demonstração do Real-ESRGAN (não é uma página real de mangá). Os
tempos incluem inicialização do processo, carga do modelo, inferência e
codificação do arquivo; não incluem decodificação no Flutter.

| Configuração | Saída | Tempo |
| --- | --- | --- |
| Real-CUGAN SE 2× `-n 0` | JPG | ~3,0 s |
| Real-CUGAN SE 2× `-n 1` | JPG | ~3,0 s |
| Real-CUGAN SE 2× `-n 0` | PNG | ~4,0 s |
| Real-CUGAN Pro 2× `-n 0` | JPG | ~3,0 s |
| Real-CUGAN Pro 2× `-n 0` | PNG | ~4,0 s |
| Real-CUGAN SE 3× `-n 0` | JPG | ~5,0 s |
| Real-CUGAN SE 2× `-n 0` | WebP | ~10,1 s |
| Real-ESRGAN animevideov3 2× | PNG | ~2,0 s |
| Real-ESRGAN x4plus-anime 2× | PNG | ~14,1 s |
| Real-ESRGAN x4plus 2× | PNG | ~68,5 s |

Observações:

- ~2,0 s é **overhead fixo** por processo: 320×450, 640×900 e 1280×1800 com o
  animevideov3 deram todos ~2,0 s. Um worker persistente eliminaria quase tudo
  isso.
- CUGAN 2× em 1280×1800 custa ~1 s de inferência além do overhead; com PNG,
  ~2 s. Com worker persistente, a expectativa é ~1–1,5 s por página.
- 3× custa ~2 s a mais; 4× é caro demais para uso sob demanda.
- WebP lossless é lento no encoder do binário; usar PNG no cache.
- `-g 0` é a GTX 1650; `-g 1` é a iGPU AMD. O padrão `gpuId = 0` já aponta
  para a dGPU nesta máquina, mas a UI deve mostrar o nome do dispositivo.
- A qualidade do animevideov3 ficou praticamente igual ao bicúbico; não serve
  para o objetivo. CUGAN SE e Pro realmente reconstroem traço. Pro ficou um
  pouco mais definido, com custo semelhante no teste.

Licenças: Real-CUGAN é MIT; Real-ESRGAN é BSD-3; ncnn é BSD-3. Incluir os
avisos na tela de licenças do app.

## 5. Caminhos considerados

### A. Neural sob demanda com o binário ncnn que o app já baixa (escolhido)

Reaproveita o `realcugan-ncnn-vulkan.exe` e os modelos que o
`SuperResolutionService` já sabe baixar. Muda o ponto de integração: em vez de
processar a galeria inteira em 4×, processa a página visível em 2×, em
background, com fila, cache em disco e fallback para o shader.

- Prós: menor esforço; qualidade comprovada; GPU Vulkan; mesmo caminho de
  download/extração; funciona para qualquer fonte.
- Contras: ~2 s de overhead por processo; página inteira, não tile; um processo
  por página; cancelar = matar processo.
- Custo estimado: médio.

### B. Worker persistente ou in-process

Manter o modelo carregado (ncnn/ONNX via FFI ou um helper próprio) e receber
pedidos de página/tile.

- Prós: elimina o overhead de ~2 s; ~1–1,5 s por página; permite cancelar,
  priorizar e, depois, processar só a região visível.
- Contras: build nativo, DLLs, FFI, empacotamento, isolamento de crash. É a
  fase 3, não o começo.
- Custo estimado: alto.

### C. Só trocar o shader por Anime4K/FSR (descartado como solução)

- Prós: instantâneo, sem dependência, ótimo para texto/linha.
- Contras: continua sem criar detalhe; é o mesmo tipo de ganho que o CAS atual,
  só que melhor. Não atende “melhorar de verdade”.
- Fica como complemento/fallback, não como solução.

**Decisão:** começar com A e evoluir para B se a latência incomodar. A
qualidade não muda entre A e B; só a velocidade e o controle.

### D. Modelos alternativos avaliados

| Modelo | Situação | Por que não é o padrão |
| --- | --- | --- |
| Real-CUGAN Pro | Já vem no mesmo zip (`models-pro`) | É a opção “mais nítido”; menos variantes de denoise que o SE. Fica como escolha do usuário. |
| AnimeJaNai v2 UltraCompact | Bom em texto, rápido | ONNX, precisa de runtime/conversão; relatos de imagem mais clara (color shift) e projeto otimizado para anime 1080p, não scan ruim. Candidato para a fase 3. |
| 2x-AnimeSharp V3/V4 | Ótimo em line art limpo e texto | Licença CC BY-NC-SA 4.0 (não comercial), ~64 MB, e piora ruído/JPEG. Evitar distribuir. |
| Real-ESRGAN Anime 6B | Mais nítido que o animevideov3 | Alucina mais, muda estilo e linhas; não é conservador para texto. |
| waifu2x CUnet | Clássico, compatível | Mais lento e mais mole que o CUGAN. |
| SPAN/Compact/AniScale | Modelos eficientes recentes | ONNX, sem ganho claro em mangá de baixa resolução; avaliar depois. |

**SE × Pro:** o SE é a edição padrão, com mais níveis de denoise (2×:
conservative, denoise1x/2x/3x, no-denoise) e resultado um pouco mais suave. O
Pro é a edição de linha realçada: traço mais definido e textura melhor, com
menos variantes (2×/3×: conservative, denoise3x, no-denoise). No teste desta
máquina o custo foi praticamente o mesmo e o Pro ficou um pouco mais definido.
Para scan ruim, o SE com denoise 1–2 dá mais controle; para arte limpa, o Pro
agrada mais. Por isso o padrão é SE e o Pro é opção.

## 6. Decisões

1. **Modelo padrão:** Real-CUGAN SE, 2× (`models-se/up2x-*`). Pro fica como
   opção “mais nítido”. Real-ESRGAN animevideov3 não entra: é conservador
   demais. x4plus não entra: lento demais nesta GPU.
2. **Denoise padrão:** `0` (conservative) para scans limpos; opção `1` para
   JPEG ruim; `-1` (no-denoise) para preservar grain. “Automático” por
   enquanto = `0`; ajuste manual disponível.
3. **Escala:** automática (2×/3×) ou manual (2×/3×/4×). O app usa a maior
   escala que couber em 6144 px por eixo; 4× só é oferecido no SE (o pacote Pro
   só tem 2×/3×). O manifesto precisa incluir `up2x-*`, `up3x-*` e `up4x-*`.
4. **Saída do cache:** PNG. JPEG perde fidelidade; WebP é lento no binário.
5. **Integração:** processo externo, um por vez, em fila com prioridade para a
   página visível. Pré-carga padrão: 2 páginas à frente.
6. **Cache:** disco + memória. Disco em pasta de cache do app, orçamento padrão
   de 2 GB com LRU; memória com teto de 192 MB, igual ao shader.
7. **Nitidez 2×:** agora é uma opção separada, desligada por padrão e só ativa
   com o neural desligado. Com o neural ativo, a página fica na resolução
   original até ele ficar pronto; o shader não roda e o CAS não é aplicado por
   cima do resultado neural.
8. **Quando pular:** imagem animada (`frameCount > 1`), largura ≥ 1800 px,
   saída > 6144 px, modelo indisponível, `useSuperResolution` ligado, ou modo
   neural desligado.
9. **Plataforma:** Windows x64 e Linux x64 na fase 1. O serviço/cache é
   independente de plataforma; só o runner escolhe o binário e o zip do modelo
   (`...-windows.zip` ou `...-ubuntu.zip`). Android/iOS ficam fora.
10. **Recurso antigo:** removido em 2026-11-05 (serviço, página, rota, toggle
    do leitor, ações e rótulos de download). A tabela/DAO antigos ficam no
    banco por compatibilidade, sem uso. O leitor usa só o neural.

## 7. Arquitetura proposta (fase 1)

### 7.1 Serviço

`lib/src/service/neural_upscale_service.dart` — singleton no estilo do
`UpscaleService`, não precisa ser bean de inicialização.

Responsabilidades:

- `Future<ui.Image?> upscale(NeuralRequest request)` com deduplicação por
  chave e fila serializada.
- `ui.Image? cached(String key)` para o widget mostrar na hora.
- Fila com prioridade: `current` antes de `preload`; pedidos de páginas que
  saíram da tela são cancelados/despriorizados.
- Runner do processo: escreve input PNG em pasta temporária, chama o binário,
  lê a saída, decodifica para `ui.Image`, apaga temporários.
- Cache de disco: `<cacheDir>/neural_upscale/<hash>.png`; índice em memória
  com tamanho e último acesso; limpeza LRU no startup e ao fechar a leitura.
  `PathService` hoje não expõe cache: acrescentar `cacheDir` com
  `getApplicationCacheDirectory()` e fallback `appSupportDir/cache`. Não usar
  `tempDir` (o Windows pode limpar) nem `getVisibleDir()` (Roaming).
- Cache de memória: LRU de `ui.Image` com teto de 192 MB. Evicção não chama
  `dispose` imediatamente (um widget pode estar pintando), igual ao shader.
- Telemetria local: `log.info('Neural upscale: ... in Xms (cache hit/miss)')`.
- Lock global de GPU (`GpuJobLock`) compartilhado com o
  `SuperResolutionService`: nunca rodar os dois ao mesmo tempo. Se o lote
  estiver ativo, o neural espera (ou pausa) e vice-versa.

`NeuralRequest`:

```dart
class NeuralRequest {
  final ui.Image source;      // imagem já decodificada (clone feita pelo serviço)
  final String cacheKey;      // URL/path/hash estável da fonte
  final bool priority;        // página atual
  final int frameCount;       // >1 = animação; não processa
  final int? sourceWidthHint; // para decidir 2x/3x e pular
  final String? sourcePath;   // opcional: arquivo local para evitar re-encode
}
```

### 7.2 Widget

`lib/src/widget/neural_upscaled_image.dart` — evolução do `UpscaledImage`:

- Mostra `source` imediatamente.
- Consulta `neuralUpscaleService.cached(key)`; se tiver, mostra direto.
- Se não, dispara o pedido e, enquanto isso, deixa o `UpscaledImage` atual
  (shader) cuidar da nitidez.
- Quando o resultado chega, troca para `RawImage(image: neural,
  filterQuality: FilterQuality.medium)`.
- Em `didUpdateWidget`, cancela/ignora resultado antigo por geração.
- `source.clone()` antes de `toByteData`, porque o cache de imagens pode
  descartar a original durante o processamento.

**Animação:** `EHImage` já instancia o codec dentro de
`_GateExtendedNetworkImageProvider` / `_GateExtendedFileImageProvider` e vê
`codec.frameCount`. Registrar o frameCount num side table por `cacheKey` (o
`EHImageAnimationGateRegistry` já é um precedente) e passá-lo ao serviço. Não
usar o heurístico `_canBeAnimated`, que trata toda imagem online como animada —
isso desligaria o neural justamente nas galerias online.

No `eh_image.dart`, `enableUpscale` passa a significar “usar o shader como
fallback”; um novo `enableNeuralUpscale` decide se o widget neural envolve o
resultado. Se o neural estiver ligado, o modelo pronto e `useSuperResolution`
desligado, o widget neural é usado; senão, o `UpscaledImage` atual.

### 7.3 Entrada da imagem

Duas rotas, escolhidas pelo serviço:

1. **Arquivo local/baixado:** se `sourcePath` existir e for um arquivo de
   imagem comum, passar o arquivo direto ao binário. Evita re-encode.
2. **Online/em memória:** `ui.Image.toByteData(format: png)` no clone,
   escrever no temporário e processar. É o caminho universal; custa
   ~100–300 ms a mais.

A fase 1 pode usar só a rota 2; a rota 1 entra como otimização se o custo
aparecer no perfil.

### 7.4 Runner do processo

```
<binário>                       # Windows: realcugan-ncnn-vulkan.exe
  -i <tmp>/in.png               # Linux:   realcugan-ncnn-vulkan
  -o <cache>/<hash>.png
  -s <2|3>
  -n <denoise>
  -m <modelDir>/models-se       # ou models-pro
  -g <gpuId>
  -f png
  -t 0
```

- Windows: trabalhar com o diretório do modelo como cwd, para achar as DLLs.
- Linux: o binário do zip `...-ubuntu.zip` é portátil e usa o Vulkan do
  sistema (`libvulkan.so.1`). Executar com permissão de execução; no AppImage,
  incluir o binário em `usr/bin` (ou pasta de dados) com o bit `+x`.
- Timeout de 60 s; em timeout/cancelamento, `process.kill()` e apagar saída
  parcial.
- Capturar stderr no log (inclui a lista de GPUs; no Linux, mostra o driver
  Vulkan/Mesa/NVIDIA).
- Sem shell. No Windows, se aparecer janela de console, usar `CreateProcess`
  com `CREATE_NO_WINDOW` (`package:win32`) ou um launcher mínimo. Testar antes
  de fechar a fase 1.
- Um processo por vez. Não usar `-j` concorrente.
- Se não houver Vulkan, o binário ainda roda com `-g -1` (CPU), mas é lento
  demais para leitura; nesse caso o serviço deve avisar e cair no shader.

### 7.5 Gerência do modelo

`lib/src/service/neural_model_manager.dart` (ou um helper compartilhado com o
`SuperResolutionService`):

- Pasta gerenciada: `pathService.getCacheDir()/neural_models/<versao>/`.
- Garante, por plataforma:
  - Windows: `realcugan-ncnn-vulkan.exe`, `vcomp140.dll`;
  - Linux: `realcugan-ncnn-vulkan` com bit de execução;
  - comuns: `models-se/up2x-*` (conservative, denoise1x/2x/3x, no-denoise),
    `models-se/up3x-*` (conservative, denoise3x, no-denoise) e, para a opção
    Pro, `models-pro/up2x-*` e `models-pro/up3x-*` (conservative, denoise3x,
    no-denoise). `models-nose` pode ser descartado.
- Reaproveitar uma instalação válida que já exista em
  `superResolutionSetting.modelDirectoryPath` (com o binário da plataforma e
  `models-se`), para não baixar de novo. Se não existir, baixar o zip oficial
  da plataforma (`realcugan-ncnn-vulkan-20220728-windows.zip` ou
  `...-ubuntu.zip`, ~46 MB cada) para a pasta gerenciada, extrair e manter só
  o que é usado.
- Verificação de integridade (tamanho/SHA-256) e versão pinada.
- Estado observável para a UI: `notDownloaded`, `downloading(progress)`,
  `ready`, `error`.
- Reaproveitar a extração existente (`extractZipArchive`) e o download
  (`ehRequest.download`) do `SuperResolutionService`; extrair um helper em vez
  de duplicar.
- Fase 1.5: embutir binário + modelos no build. Windows: copiar para o
  diretório do executável (CMake/pós-build). Linux: incluir no AppImage, com
  bit de execução. Modelos são os mesmos nas duas plataformas; só o binário
  muda. O pacote cresce ~15–40 MB, conforme os modelos escolhidos.

### 7.6 Configurações

Em `read_setting.dart` (sem novo bean de config):

- `enableNeuralUpscale` (bool, padrão `false` até o usuário baixar o modelo).
- `neuralUpscaleModel` (`se` | `pro`, padrão `se`).
- `neuralUpscaleScale` (`auto` | `2` | `3` | `4`, padrão `auto`; 4× só no SE).
- `neuralUpscaleDenoise` (`none` = `-1` | `0` | `1` | `2` | `3`, padrão `0`;
  no Pro só `-1`, `0` e `3`).
- `neuralUpscalePreload` (0–3, padrão 2).
- `neuralUpscaleSkipWidth` (padrão 1800).
- Reutilizar `superResolutionSetting.modelDirectoryPath` e `gpuId`? Não: o
  caminho do modelo neural é gerenciado e separado. Criar `neuralModelDir` no
  modelo manager; manter `gpuId` compartilhado, com a UI mostrando o nome.

UI em Configurações → Upscale (entrada própria; a seção saiu de Leitura):

- Switch “Melhoria neural (beta)”.
- Status do modelo + botão “Baixar modelo (~46 MB)” com progresso.
- Dropdown de modelo (SE recomendado / Pro).
- Dropdown de escala (Auto / 2× / 3× / 4×; 4× some no Pro).
- Dropdown de denoise (Desligado / 0 / 1 / 2 / 3; no Pro só Desligado/0/3).
- Dropdown de pré-carga (0/1/2/3).
- GPU (nome + índice; compartilhada com o lote antigo).
- Texto de ajuda curto com o custo (~1–4 s na primeira vez por página; depois
  é cache) e o aviso de que não recupera informação inexistente.
- No fim da mesma página, “Nitidez (2×)”: desligada por padrão e indisponível
  quando o neural está ativo. Só vale com o neural desligado.

### 7.7 Integração com o leitor

- `base_layout.dart` passa `enableNeuralUpscale` e `priority` (página atual)
  para `EHImage`.
- `EHImage` monta `NeuralUpscaledImage` quando ligado; senão, o
  `UpscaledImage` atual.
- `ReadPageLogic.onClose` chama `neuralUpscaleService.clearMemoryCache()` e
  cancela a fila da sessão. O cache de disco permanece.
- A pré-carga pode começar simples: cada página montada pede; a prioridade
  garante a visível primeiro. Se o layout montar muitas páginas fora da tela,
  passar `priority: false` e limitar a fila. A fase 1 não precisa de um novo
  mecanismo de “página atual” se o leitor já monta só a visível + vizinhas.
- Ao trocar de página, pedidos `priority` antigos viram `preload` ou são
  cancelados.

### 7.8 Chave e cache

Chave estável:

```
sha1('<sourceKey>|<model>|<denoise>|<scale>|<width>x<height>|v1')
```

- `sourceKey`: `GalleryImage.imageHash` quando existir; senão
  `path`/`url` + tamanho + mtime (local) ou URL + dimensões (online).
- O hash vira nome do arquivo `.png`.
- Metadados (dimensões, modelo, denoise, data) em um índice JSON leve ou no
  próprio nome; o índice serve para LRU e limpeza.
- Limpeza: ao iniciar o app e ao fechar a leitura, remover entradas acima de
  2 GB por último acesso. Nunca apagar arquivos fora da pasta de cache.

### 7.9 Ciclo de vida e limites

- Um processo por vez; fila priorizada; `kill` ao cancelar.
- Pausar quando o app não está em foco (opcional, `WidgetsBindingObserver`).
- Pausar em bateria (opcional; `battery_plus` já é dependência) — decisão do
  builder.
- Não processar se a página já está em cache de memória.
- Não processar se a saída passaria de 6144 px em qualquer eixo.
- Se o processo falhar 2× na sessão, desligar o neural até reiniciar e mostrar
  um aviso; o shader continua.

## 8. Fluxo de uma página

1. Usuário abre a página. `EHImage` mostra a imagem original na hora.
2. `NeuralUpscaledImage` consulta o cache de memória; se tiver, mostra.
3. Se não, dispara `NeuralRequest` com prioridade e deixa o shader 2× rodar.
4. Serviço: calcula a chave, consulta o cache de disco; se tiver, decodifica e
   devolve.
5. Se não, escreve o input, chama o binário, espera, decodifica a saída,
   grava no cache (o binário já grava) e devolve.
6. Widget troca a imagem; o shader não roda mais por cima.
7. Ao virar a página, a nova vira prioridade; a anterior pode ser cancelada.

## 9. Testes e validação

- Unitários: chave estável, evicção LRU, regra de 2×/3×/4×, pulos (animação,
  largura, 6144), prioridade da fila.
- Widget: fallback enquanto processa; troca quando chega; cancelamento por
  geração; cache hit não dispara processo.
- Manual, com galerias reais:
  - E-Hentai 1280 px, Xlecx ~800 px, arquivo local ~600 px.
  - Medir primeira exibição, cache hit, uso de GPU, memória, temperatura.
  - Comparar SE × Pro × denoise 0/1 em 2–3 páginas ruins e escolher o padrão.
- Harness de comparação (fora do app) já existe no histórico desta conversa:
  recorte 1:1, lado a lado, para ajustar modelo/denoise sem achismo.

## 10. Fases

1. **Fase 1 (este design):** serviço + cache + settings + download + fallback,
   Windows e Linux x64, binário externo, CUGAN SE 2×. Atrás de um switch beta.
2. **Fase 1.5:** embutir binário/modelos no build Windows e no AppImage;
   seletor de GPU com nome; pausa em foco/bateria; possível rota de arquivo
   local sem re-encode.
3. **Fase 2:** worker persistente (ncnn/FFI ou helper) para ~1–1,5 s/página e
   cancelamento melhor.
4. **Fase 3:** tiles/região visível por zoom (B), Android/iOS, e avaliação de
   modelos alternativos (AnimeJaNai v2 UC).

## 11. O que fica para o builder

- Onde exatamente plugar o widget no `EHImage` e como passar `priority` sem
  quebrar os layouts.
- Formato do índice de cache (JSON vs nomes de arquivo) e política de limpeza.
- Como expor o progresso do download sem criar um bean novo, seguindo o padrão
  GetX do projeto.
- Se o console do processo aparece no Windows e como escondê-lo.
- Como detectar e exibir o nome da GPU.
- Quais páginas o leitor monta fora da tela hoje; ajustar a fila a isso.

## 12. Decisões do usuário (2026-11-05)

1. **Latência:** binário externo na fase 1; worker persistente só se o custo
   incomodar.
2. **Modelo:** SE como padrão; Pro como opção “mais nítido”. Escala manual
   2×/3×/4×, com 4× só no SE; o app cai para a maior escala que couber.
3. **Distribuição:** baixar no primeiro uso na fase 1; embutir binário +
   modelos depois da validação, no Windows e no AppImage Linux.
4. **Cache em disco:** 2 GB, LRU.
5. **Escopo:** rodar sempre em página de baixa resolução, para a pré-carga
   deixar o zoom pronto.
6. **Recurso antigo:** remover o super resolution em lote.
7. **Plataformas:** Windows x64 e Linux x64 na fase 1; Android/iOS fora.

## 13. Revisão de 2026-11-05

- O super resolution em lote foi removido da interface e do leitor: serviço,
  página, rota, modelo/seleção de GPU, toggle por galeria, ações de
  download/detalhes e rótulos “AI(...)”. A tabela/DAO antigos permanecem no
  banco sem uso, para não exigir uma migração destrutiva.
- As configurações foram consolidadas numa entrada própria
  **Configurações → Upscale**, com o neural, o modelo/status/download e a GPU.
  A seção neural saiu de Leitura; a entrada antiga de Avançado foi removida.
- A GPU passou para `readSetting.neuralUpscaleGpuId`. A lista é obtida rodando
  o binário ncnn com um PNG 64×64 e `-v`, e parseando as linhas
  `[índice nome]`; o dropdown mostra “0 — NVIDIA GeForce GTX 1650”, etc.
- Escala manual 2×/3×/4×, com limite de 6144 px por eixo; 4× só no SE
  (`models-pro` não tem up4x). O app cai para a maior escala que couber.
- O cache de disco continua em 2 GB (FIFO por data de gravação; a memória é
  LRU por acesso). O modelo fica em `neural_models`, separado do cache.
- A nitidez 2× saiu de Leitura, foi para Upscale como “Nitidez (2×)”, ficou
  desligada por padrão e não roda com o neural ativo. Sem ela, a primeira
  exibição de cada página mostra a imagem original até o neural terminar.
