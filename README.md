<div align="center">

<img src="assets/icon/acervo-hc_512.png" alt="Acervo H&C" width="96" />

# Acervo H&C

**Hentai & Comics no mesmo acervo.**  
Leitor multiplataforma para **E-Hentai / ExHentai**, **Xlecx** e **nhentai**, construído em Flutter com foco em leitura fluida, upscale neural sob demanda e português do Brasil nativo.

[![Release](https://img.shields.io/github/v/release/Darkiu1337/acervo-hc?style=for-the-badge&color=7c5cff&label=vers%C3%A3o)](https://github.com/Darkiu1337/acervo-hc/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/Darkiu1337/acervo-hc/total?style=for-the-badge&color=2ea043&label=downloads)](https://github.com/Darkiu1337/acervo-hc/releases)
[![Flutter](https://img.shields.io/badge/Flutter-3.44-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![License](https://img.shields.io/badge/Licen%C3%A7a-Apache%202.0-orange?style=for-the-badge)](LICENSE)

[Download](#-download) · [Recursos](#-recursos) · [Upscale](#-comparação-de-upscale) · [Capturas](#-capturas) · [Compilar](#-compilar-localmente)

</div>

---

## ✨ Recursos

Nascido como fork do **JHenTai**, o Acervo H&C preserva todo o ecossistema original (busca, favoritos, downloads, arquivos, histórico e rankings) e acrescenta o que faz diferença na leitura diária:

| Módulo | Destaques |
| :--- | :--- |
| **📖 Leitor aprimorado** | **Divisão de páginas largas** (*Split Wide Pages*), zoom contínuo preservado entre páginas, preservação exata da página ao trocar de layout, retorno ao topo, atalhos de teclado, `photo_view` ajustado (`Ctrl` + scroll ancorado no cursor), preview de arquivos `.zip`/`.cbz` e envio para visualizador externo |
| **🪄 Upscale sob demanda** | Nitidez **2× por shader** (bicúbico + AMD FidelityFX CAS) e **6 modelos neurais locais via Vulkan** — **Real-CUGAN SE** *(padrão)*, **Real-CUGAN Pro**, **ModernSpanimation V2 (SPAN 2×)**, **AnimeJaNai V3 Sharp (2×)**, **HFA2k Multi-JPG (2×)** e **Real-ESRGAN AnimeVideo v3** — com pré-carregamento assíncrono e toggle rápido por galeria |
| **🌐 Fontes Xlecx e nhentai** | Abas dedicadas para **`xlecx.one`** (5 listagens, 13 categorias, 1.000+ tags, filtros e login) e **`nhentai`** via API v2 direta (ordenação por *Recentes / Popular Hoje / Semana / Geral*, chips de idioma, salto direto por `#código`, busca no E-Hentai e downloads), ambas abrindo no leitor unificado |
| **✅ Já lidos unificados (3 vias)** | Esconde galerias concluídas em **E-Hentai/ExHentai, Xlecx e nhentai** com deduplicação cross-provider multi-sinal (título principal + alternativo bilíngue, artista/grupo, número de páginas, trava contra sequências e hash perceptual 128-bit da capa) |
| **🔎 Filtros & Acompanhados** | Filtro local em **Popular** e **Ranklist** (categorias, idioma e inclusão/exclusão por `-termo`), seleção múltipla de tags nos detalhes, herança de progresso em versões atualizadas e rastreamento de progresso/marcadores na aba **Acompanhados** |
| **⚡ Navegação leve & 🇧🇷 pt-BR** | Abas ocultas com tickers pausados, parsing HTML e SQLite fora da thread da UI, scroll suave de mouse/trackpad, capas decodificadas no tamanho de miniatura e interface traduzida em **pt-BR** de ponta a ponta (com suporte mantido nos outros 5 idiomas) |

---

## 🪄 Comparação de Upscale

Exemplo real de página de baixa resolução lida no Acervo H&C usando o modelo padrão **Real-CUGAN SE** (clique nas imagens para ampliar em tamanho original):

<div align="center">

| Sem upscale (original) | Com upscale (Real-CUGAN SE) |
| :---: | :---: |
| <img src="screenshot/upscale_off.png" width="440" alt="Página original sem upscale" /> | <img src="screenshot/upscale_real_cugan_se.png" width="440" alt="Página com upscale Real-CUGAN SE" /> |

</div>

---

## 🖼️ Capturas

<div align="center">

| Desktop | Página única | Duas colunas |
| :---: | :---: | :---: |
| <img src="screenshot/desktop1.png" width="400" alt="Layout desktop" /> | <img src="screenshot/read.jpg" width="170" alt="Leitura em página única" /> | <img src="screenshot/read_double_column.png" width="170" alt="Leitura em duas colunas" /> |

</div>

---

## 📦 Download

Baixe a versão mais recente em [**Releases**](https://github.com/Darkiu1337/acervo-hc/releases/latest):

- **Windows** — baixe `AcervoHC_<versão>_Windows_reader.zip`, extraia e execute `acervo-hc.exe`.
- **Linux** — baixe `AcervoHC_<versão>_Linux_x64.AppImage`, rode `chmod +x` e execute *(requer `webkit2gtk-4.1`)*.
- **Android / iOS / macOS** — compile localmente seguindo as instruções abaixo.

> [!NOTE]
> O identificador do aplicativo é `app.acervo.hc`, então ele roda **em paralelo ao JHenTai**, com dados e configurações independentes.  
> No Windows, caso o Defender bloqueie o executável sem assinatura, autorize-o normalmente; se precisar de proxy, configure em *Configurações → Rede*.

---

## ⌨️ Atalhos, CLI e detalhes técnicos

<details>
<summary><strong>Atalhos do leitor & linha de comando (desktop)</strong></summary>

#### Leitor
- `←` / `→` — desloca a imagem com zoom na horizontal ou troca de página em `1.0×`
- `Ctrl` / `Alt` + `←` / `→` — troca de página mesmo com zoom ativo
- `↑` / `↓` — desloca verticalmente com zoom
- `+` / `-` — ajusta o zoom no passo configurado (`5%`, `8%`, `12%`, `20%`)
- `Ctrl` + roda do mouse — zoom ancorado na posição do cursor
- Clique direito no card / detalhes — *Abrir no visualizador externo* ou *Marcar como já lido*

#### Abrir galerias via terminal
Funciona para links do E-Hentai, ExHentai, Xlecx e nhentai (no macOS, invoque o binário dentro de `Acervo HC.app/Contents/MacOS/`):

```bash
acervo-hc.exe -g "https://e-hentai.org/g/1234567/abcdef1234/"
acervo-hc.exe --gallery="https://xlecx.one/65195-x.html"
acervo-hc.exe --gallery="https://nhentai.net/g/699178/"
```

</details>

<details>
<summary><strong>Notas sobre o Xlecx</strong></summary>

- A busca por palavra-chave do site ignora filtros de categoria/tag (comportamento do próprio `xlecx.one`).
- Posts de vídeo são omitidos automaticamente, já que o app trabalha apenas com galerias de imagem.
- Posts restritos a usuários registrados são liberados entrando com **usuário/e-mail e senha** pelo ícone de conta na aba Xlecx — apenas os cookies de sessão ficam salvos no dispositivo (nunca a senha). Contas criadas via Google podem usar a aba **Cookies**.

</details>

<details>
<summary><strong>Estrutura principal do projeto</strong></summary>

| Caminho | Responsabilidade |
| :--- | :--- |
| `lib/src/pages/read/` | Leitor: layouts, divisão de páginas largas, zoom contínuo, atalhos e progresso |
| `lib/src/pages/xlecx/` · `lib/src/network/xlecx_request.dart` | Aba, busca, filtros, detalhes e autenticação do Xlecx |
| `lib/src/pages/nhentai/` · `lib/src/network/nhentai_request.dart` | Aba dedicada do nhentai (API v2), ordenação popular, código direto e detalhes |
| `lib/src/service/already_read_service.dart` | Lista de já lidos e deduplicação cross-provider 3-vias |
| `lib/src/utils/gallery_identity_matcher.dart` · `cover_hash_util.dart` | Matching multi-sinal e hash perceptual 128-bit de capas |
| `lib/src/service/upscale_service.dart` · `neural_upscale_service.dart` | Upscale 2× por shader e 6 modelos neurais sob demanda via Vulkan |
| `packages/photo_view/` | Fork local do `photo_view` ajustado para o leitor |
| `.github/workflows/` | Builds automáticos (Windows, Linux AppImage e Release) |

</details>

---

## 🛠️ Compilar localmente

Requisitos: **Flutter `3.44.8`** e o toolchain da plataforma alvo.

```bash
flutter pub get

flutter build windows --release   # Windows
flutter build linux --release     # Linux
flutter build apk --release       # Android
flutter build macos --release     # macOS
flutter build ios --release       # iOS
```

---

## 📄 Licença e créditos

Distribuído sob a **Apache License 2.0** — veja [LICENSE](LICENSE).

Baseado em [JHenTai](https://github.com/jiangtian616/JHenTai) por **jiangtian616**, com inspirações visuais de [FEhViewer](https://github.com/honjow/FEhViewer), [EhPanda](https://github.com/tatsuz0u/EhPanda) e [EHViewer](https://gitlab.com/NekoInverter/EhViewer), e banco de tradução de tags do [EhTagTranslation](https://github.com/EhTagTranslation/Database).
