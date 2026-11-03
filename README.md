# Acervo H&C

Leitor de mangá para **E-Hentai / ExHentai** feito em Flutter, para Android, iOS, Windows, macOS e Linux. O nome é o programa: **H**entai **&** **C**omics no mesmo acervo.

Este app nasceu como fork do JHenTai e hoje tem identidade própria. O cliente original segue intacto; as mudanças estão no que importa para quem lê: leitor com zoom contínuo e upscale 2×, visualizador externo de imagens, duas fontes externas de galerias (**8muses** e **Xlecx**), a lista de **já lidos** e a tradução completa para **português do Brasil**.

## O que este app acrescenta

| Área | O que foi adicionado |
| --- | --- |
| **Leitor** | Zoom preservado entre páginas, retorno ao topo, atalhos de teclado, upscale 2× e visualizador externo |
| **8muses** | Segunda fonte de galerias, com busca, filtros de tag e artista, favoritos locais e prévia das páginas |
| **Xlecx** | Terceira fonte: cinco listagens, filtros de categoria e tags, busca e prévia das páginas |
| **Já lidos** | Lista local que esconde obras concluídas das listas de navegação |
| **Idioma** | Tradução pt-BR completa (824 chaves) e correções de i18n |
| **Builds** | Workflows de Windows e Linux (AppImage) no GitHub Actions |

O resto do app — busca, favoritos, downloads, arquivos, histórico e rankings — continua como no original.

## Leitor

- **Zoom contínuo entre páginas** — em página única, coluna dupla e listas, cada página já é montada na escala atual e alinhada ao topo, inclusive as pré-carregadas. Virar a página nunca mostra um quadro em 1.0× antes de ajustar.
- **Volta ao topo ao virar a página** (Configurações → Leitura), limitada ao tamanho real do conteúdo em vez do viewport.
- **Atalhos de teclado** — `Ctrl` + `←`/`→` deslocam na horizontal, `↑`/`↓` na vertical e `+`/`-` alteram o zoom no passo configurado (5/8/12/20%), todos com repetição de tecla.
- **`photo_view` próprio** (`packages/photo_view`) — escala inicial correta, zoom multiplicativo com `Ctrl` + roda do mouse ancorado no cursor, arraste mais sensível e duplo clique em passos de 1.5×.
- **Placeholders de carregamento** não sofrem zoom: ficam centralizados e no tamanho normal.
- **Upscale 2× da página atual** — Catmull-Rom bicúbico + shaders AMD FidelityFX CAS com cache LRU, para o texto dos balões continuar nítido em zoom alto (Configurações → Leitura).
- **Visualizador externo** — botão direito → *Abrir no visualizador externo* (nomacs, ImageGlass, XnView ou qualquer `.exe`). Galerias online são transmitidas página a página para `%TEMP%\acervo_hc_viewer\...`, com overlay de progresso e limpeza automática.

## Fonte 8muses

Uma segunda fonte, independente, para quadrinhos ocidentais que não podem ser publicados no E-Hentai. Não interfere em nenhum caminho do código do E-H e não exige login, cookie ou liberação do Cloudflare.

- Aba própria com **Populares**, **Recentes**, **Explorar tudo** e uma barra de busca embutida.
- **Busca por palavra-chave** com ordenação no servidor: melhor correspondência, mais recentes e mais vistos.
- **Filtro por tag** — as 120 tags do site, com contagem de galerias, em um painel com inclusão e exclusão. A primeira tag incluída vai para o servidor; as demais e a palavra-chave são cruzadas localmente, e o rodapé mostra o filtro ativo.
- **Filtro por artista** — artistas em destaque, com busca e contagem de galerias, no mesmo painel. A listagem do artista vira a base e as tags/palavra-chave são aplicadas por cima.
- **Buscas recentes** e **tags populares** sugeridas ao focar o campo, com remoção individual ou em bloco.
- **Favoritos locais** — o coração no card, o menu de contexto ou a página de detalhes salvam a galeria em uma lista local, sem login e sem gastar slot do E-H. A página de Favoritos ganha um seletor `E-Hentai` / `Favoritos locais`.
- **Detalhes completos** — capa, autor, número de páginas, descrição e as tags reais da galeria, clicáveis para ampliar o filtro atual. Dá para ler ou baixar direto da mesma página.
- **Prévia das páginas** — grade preguiçosa de miniaturas abaixo dos detalhes. Tocar em uma miniatura abre o leitor naquela página, com a posição salva destacada.
- **Mesmo leitor e mesmo downloader do E-H** — zoom, upscale 2×, teclado, tira de miniaturas, progresso de leitura, histórico e visualizador externo funcionam igual, porque a lista de páginas é resolvida de antemão.
- Área de transferência, `-g <url>` e o compartilhamento abrem a página de detalhes do 8muses diretamente.

### Limitações conhecidas

- Sem deduplicação com o E-Hentai: a mesma obra pode aparecer duas vezes.
- O site expõe no máximo 5 tags por galeria.
- Filtros combinados de tag e artista são locais, então interseções raras podem exigir *Carregar mais*.
- A cobertura de um artista é parcial, já que o site espelha `8muses.com` e `allporncomic.com`.

## Fonte Xlecx

Terceira fonte, para os quadrinhos de `xlecx.one` (um site DataLife Engine com mais de 2.400 páginas de listagem). Também é independente: sem login, sem cookie e sem passar pelo código do E-H.

- Aba própria com as **cinco listagens** do site: Recentes, Atualizados recentemente, Mais bem avaliados, Mais vistos e Mais comentados.
- **Busca por palavra-chave** com o esquema do próprio site (a paginação da busca só existe via POST, então a primeira página vai por GET e as seguintes por POST).
- **Filtro por categoria** — as 13 seções de imagem do site (Comics, Manga, Pictures, 3D comics, Anime/Cartoon/Games Parody, Furry, Incest, Dickgirl, Yaoi, Yuri). As seções de vídeo ficam de fora, porque o app só lê galerias de imagem.
- **Filtro por tag** — as 1.049 tags do diretório do site, com contagem, inclusão e exclusão, cruzadas no servidor (a URL `/f/n.m.tags=a,b/` aplica todas com AND).
- **Filtro por artista, paródia e grupo** — os chips da página de detalhes viram filtro na aba, como no 8muses.
- **Detalhes completos** — capa, artista, grupo, páginas, categorias, paródias e tags clicáveis, com prévia das páginas e leitura/download direto.
- **Mesmo leitor e mesmo downloader do E-H** — as URLs das páginas saem prontas do post do site, então zoom, upscale 2×, progresso de leitura, histórico e visualizador externo funcionam igual.
- Área de transferência, `-g <url>` e o compartilhamento abrem a página de detalhes do Xlecx diretamente.

### Limitações conhecidas

- No próprio site, a busca por palavra-chave ignora os filtros; a aba avisa isso no painel de filtros.
- Posts de vídeo aparecem no site mas são omitidos do app.
- Alguns posts são restritos a usuários registrados: a listagem os mostra, mas a página de detalhes avisa e oferece o atalho para abrir no navegador.
- Sem deduplicação com o E-Hentai nem com o 8muses.

## Já lidos

Lista manual que tira das listas de navegação as obras já terminadas, para elas não voltarem sempre. Funciona nas duas fontes.

- **Marcar lido** na página de detalhes do E-H, na página do 8muses ou no menu de contexto do card alterna a galeria na lista local (`GetStorage`, sem login e sem slot do E-H).
- As galerias marcadas somem do feed inicial, da busca, dos populares, dos watched e de todas as listagens do 8muses. Favoritos, histórico, rankings e a própria página de já lidos continuam mostrando. Quando uma página inteira de resultados ficaria vazia, o app pula para a próxima.
- A entrada **Já lidos** na barra lateral lista tudo com os cards normais, 100 por página; clique direito ou toque longo remove um item, e a lixeira da barra remove todos. A lista é independente de fonte: E-H e 8muses juntos.

## Tradução

- **pt-BR completo**: 824 chaves traduzidas, com terminologia consistente em todo o app. O idioma é escolhido em Configurações → Idioma.
- As strings novas do 8muses existem nos seis idiomas do projeto.
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
| `lib/src/pages/eight_muses/` | Aba, busca, filtros e detalhes do 8muses |
| `lib/src/network/eight_muses_request.dart` | Cliente HTTP do 8muses |
| `lib/src/pages/already_read/` | Lista de já lidos |
| `lib/src/service/upscale_service.dart` | Upscale 2× (shaders + cache) |
| `packages/photo_view/` | `photo_view` modificado para o leitor |
| `.github/workflows/build-*.yml` | Builds de Windows e Linux |

## Créditos e licença

Distribuído sob a **Apache License 2.0** — veja [LICENSE](LICENSE).

Fork de **JHenTai**, de [jiangtian616](https://github.com/jiangtian616/JHenTai) — a atribuição exigida pela licença. Layout e estilo inspirados em [FEhViewer](https://github.com/honjow/FEhViewer), [EhPanda](https://github.com/tatsuz0u/EhPanda) e [EHViewer](https://gitlab.com/NekoInverter/EhViewer); tradução de tags do [EhTagTranslation](https://github.com/EhTagTranslation/Database).
