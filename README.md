# Acervo H&C

Leitor de mangá para **E-Hentai / ExHentai** feito em Flutter, para Android, iOS, Windows, macOS e Linux. O nome é o programa: **H**entai **&** **C**omics no mesmo acervo.

Este app nasceu como fork do JHenTai e hoje tem identidade própria. O cliente original segue intacto; as mudanças estão no que importa para quem lê: leitor com zoom contínuo e upscale 2×, visualizador externo de imagens, uma fonte externa de galerias (**Xlecx**), a lista de **já lidos** e a tradução completa para **português do Brasil**.

## O que este app acrescenta

| Área | O que foi adicionado |
| --- | --- |
| **Leitor** | Zoom preservado entre páginas, retorno ao topo, atalhos de teclado, upscale (nitidez 2× e melhoria neural) e visualizador externo |
| **Xlecx** | Fonte externa: cinco listagens, filtros de categoria e tags, busca e prévia das páginas |
| **Já lidos** | Lista local que esconde obras concluídas das listas de navegação |
| **Idioma** | Tradução pt-BR completa (822 chaves) e correções de i18n |
| **Builds** | Workflows de Windows e Linux (AppImage) no GitHub Actions |

O resto do app — busca, favoritos, downloads, arquivos, histórico e rankings — continua como no original.

## Leitor

- **Zoom contínuo entre páginas** — em página única, coluna dupla e listas, cada página já é montada na escala atual e alinhada ao topo, inclusive as pré-carregadas. Virar a página nunca mostra um quadro em 1.0× antes de ajustar.
- **Volta ao topo ao virar a página** (Configurações → Leitura), limitada ao tamanho real do conteúdo em vez do viewport.
- **Atalhos de teclado** — `←`/`→` deslocam a imagem ampliada na horizontal (e trocam de página quando ela não está ampliada); `Ctrl`/`Alt` + `←`/`→` trocam de página, `↑`/`↓` deslocam na vertical com zoom e `+`/`-` alteram o zoom no passo configurado (5/8/12/20%), todos com repetição de tecla.
- **`photo_view` próprio** (`packages/photo_view`) — escala inicial correta, zoom multiplicativo com `Ctrl` + roda do mouse ancorado no cursor, arraste mais sensível e duplo clique em passos de 1.5×.
- **Placeholders de carregamento** não sofrem zoom: ficam centralizados e no tamanho normal.
- **Upscale da página atual** — nitidez 2× (Catmull-Rom bicúbico + shaders AMD FidelityFX CAS) ou melhoria neural Real-CUGAN sob demanda, para o texto dos balões continuar nítido em zoom alto. Páginas em preto e branco pulam a melhoria neural automaticamente, e o modo da galeria (automática, ligada ou desligada) tem um toggle rápido no menu do leitor. O cache em disco vai até 4 GB e é apagado quando o app fecha (`Configurações → Upscale`, também acessível pelo item **Upscale** no painel da leitura).
- **Visualizador externo** — botão direito → *Abrir no visualizador externo* (nomacs, ImageGlass, XnView ou qualquer `.exe`). Galerias online são transmitidas página a página para `%TEMP%\acervo_hc_viewer\...`, com overlay de progresso e limpeza automática.

## Fonte Xlecx

Segunda fonte, para os quadrinhos de `xlecx.one` (um site DataLife Engine com mais de 2.400 páginas de listagem). Também é independente: sem login, sem cookie e sem passar pelo código do E-H.

- Aba própria com as **cinco listagens** do site: Recentes, Atualizados recentemente, Mais bem avaliados, Mais vistos e Mais comentados.
- **Busca por palavra-chave** com o esquema do próprio site (a paginação da busca só existe via POST, então a primeira página vai por GET e as seguintes por POST).
- **Filtro por categoria** — as 13 seções de imagem do site (Comics, Manga, Pictures, 3D comics, Anime/Cartoon/Games Parody, Furry, Incest, Dickgirl, Yaoi, Yuri). As seções de vídeo ficam de fora, porque o app só lê galerias de imagem.
- **Filtro por tag** — as 1.049 tags do diretório do site, com contagem, inclusão e exclusão, cruzadas no servidor (a URL `/f/n.m.tags=a,b/` aplica todas com AND).
- **Filtro por artista, paródia e grupo** — os chips da página de detalhes viram filtro na aba.
- **Favoritos locais** — o coração no card, o menu de contexto ou a página de detalhes salvam a galeria em uma lista local, sem login e sem gastar slot do E-H. A página de Favoritos ganha um seletor `E-Hentai` / `Favoritos locais`.
- **Detalhes completos** — capa, artista, grupo, páginas, categorias, paródias e tags clicáveis, com prévia das páginas e leitura/download direto.
- **Conta do site (cookies)** — algumas galerias são restritas a usuários registrados. O ícone de conta na aba abre um campo por cookie (`PHPSESSID`, `dle_user_id`, `dle_password`, como no login do E-Hentai), com verificação de acesso na hora. Os cookies ficam só no dispositivo e valem enquanto o site não expirar a sessão.
- **Mesmo leitor e mesmo downloader do E-H** — as URLs das páginas saem prontas do post do site, então zoom, upscale 2×, progresso de leitura, histórico e visualizador externo funcionam igual.
- Área de transferência, `-g <url>` e o compartilhamento abrem a página de detalhes do Xlecx diretamente.

### Limitações conhecidas

- No próprio site, a busca por palavra-chave ignora os filtros; a aba avisa isso no painel de filtros.
- Posts de vídeo aparecem no site mas são omitidos do app.
- Alguns posts são restritos a usuários registrados: a listagem os mostra, mas a página de detalhes avisa e oferece o atalho para abrir no navegador ou configurar o cookie da conta.
- Sem deduplicação com o E-Hentai.

## Já lidos

Lista manual que tira das listas de navegação as obras já terminadas, para elas não voltarem sempre. Funciona nas duas fontes.

- **Marcar lido** na página de detalhes do E-H, na página do Xlecx ou no menu de contexto do card alterna a galeria na lista local (`GetStorage`, sem login e sem slot do E-H).
- As galerias marcadas somem do feed inicial, da busca, dos populares, dos watched e de todas as listagens do Xlecx. Favoritos, histórico, rankings e a própria página de já lidos continuam mostrando. Quando uma página inteira de resultados ficaria vazia, o app pula para a próxima.
- A entrada **Já lidos** na barra lateral lista tudo com os cards normais, 100 por página; clique direito ou toque longo remove um item, e a lixeira da barra remove todos. A lista é independente de fonte: E-H e Xlecx juntos.

## Tradução

- **pt-BR completo**: 822 chaves traduzidas, com terminologia consistente em todo o app. O idioma é escolhido em Configurações → Idioma.
- As strings novas do Xlecx existem nos seis idiomas do projeto.
- Correções de i18n que vinham de antes: a chave duplicada `quickSearch` foi separada em `quickSearchConfig`, e chaves que apareciam cruas na interface foram adicionadas a todos os locales.

## Download e instalação

### Windows

1. Baixe o `AcervoHC_<versão>_Windows_reader.zip` na aba [Releases](../../releases).
2. Extraia e execute `acervo-hc.exe`.

Builds de desenvolvimento saem do workflow **Build Windows (reader)**, na aba Actions, no artefato `AcervoHC-Windows-reader`.

O identificador do app é `app.acervo.hc`: ele instala em paralelo ao JHenTai, com dados próprios — configurações e downloads antigos não são importados.

O identificador do app é `app.acervo.hc`: ele instala em paralelo ao JHenTai, com dados próprios — configurações e downloads antigos não são importados.

Se o app não abrir no Windows 11, tente o modo de compatibilidade. Se o Windows Defender bloquear, autorize o executável. Para usar proxy, configure o endereço em Configurações → Rede.

### Linux

O workflow **Build Linux (AppImage)** publica o artefato `AcervoHC-Linux-AppImage`. Baixe, dê permissão de execução (`chmod +x`) e rode. É necessário ter `webkit2gtk-4.1` instalado.

### Android, iOS e macOS

Este fork não publica builds para essas plataformas — compile localmente, como descrito abaixo.

## Compilando

Requisitos: Flutter `3.44.8` e o toolchain da plataforma desejada.

```bash
flutter pub get

# Windows
flutter build windows --release

# Android (a assinatura é responsabilidade sua)
flutter build apk --release

# Linux / macOS / iOS
flutter build linux --release
flutter build macos --release
flutter build ios --release
```

O projeto também abre normalmente no Android Studio, IntelliJ ou VS Code.

## Capturas de tela

| Desktop | Leitura | Duas colunas |
| --- | --- | --- |
| <img width="380" src="screenshot/desktop1.png" alt="Layout desktop"/> | <img width="170" src="screenshot/read.jpg" alt="Leitura de página única"/> | <img width="170" src="screenshot/read_double_column.png" alt="Leitura em duas colunas"/> |

## Linha de comando (desktop)

No Windows, macOS e Linux dá para abrir uma galeria direto pela linha de comando, o que permite usar o app como leitor externo de outras ferramentas:

```bash
acervo-hc.exe -g "https://e-hentai.org/g/1234567/abcdef1234/"
acervo-hc.exe --gallery="https://exhentai.org/g/1234567/abcdef1234/"

# página de imagem única também funciona
acervo-hc.exe -g "https://e-hentai.org/s/abcdef1234/123456-0"
```

- `-g` / `--gallery <url>` abre a galeria (ou a página de imagem) na inicialização; outros argumentos são ignorados. Sem URL válida, o app inicia normalmente.
- Com bloqueio por senha ou biometria, a galeria abre depois do desbloqueio.
- No macOS, execute o binário dentro do bundle: `"/Applications/Acervo HC.app/Contents/MacOS/Acervo HC" -g <url>` (abrir pelo Finder não passa argumentos).

## Estrutura

| Caminho | Conteúdo |
| --- | --- |
| `lib/src/pages/read/` | Leitor: layout, zoom, atalhos e progresso |
| `lib/src/pages/xlecx/` | Aba, busca, filtros e detalhes do Xlecx |
| `lib/src/network/xlecx_request.dart` | Cliente HTTP do Xlecx |
| `lib/src/pages/already_read/` | Lista de já lidos |
| `lib/src/service/upscale_service.dart` | Upscale 2× (shaders + cache) |
| `packages/photo_view/` | `photo_view` modificado para o leitor |
| `.github/workflows/build-*.yml` | Builds de Windows e Linux |

## Créditos e licença

Distribuído sob a **Apache License 2.0** — veja [LICENSE](LICENSE).

Fork de **JHenTai**, de [jiangtian616](https://github.com/jiangtian616/JHenTai) — a atribuição exigida pela licença. Layout e estilo inspirados em [FEhViewer](https://github.com/honjow/FEhViewer), [EhPanda](https://github.com/tatsuz0u/EhPanda) e [EHViewer](https://gitlab.com/NekoInverter/EhViewer); tradução de tags do [EhTagTranslation](https://github.com/EhTagTranslation/Database).
