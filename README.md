<div align="center">

<img src="assets/icon/acervo-hc_512.png" alt="Acervo H&C" width="96" />

# Acervo H&C

**Hentai & Comics no mesmo acervo.**  
Leitor multiplataforma para **E-Hentai / ExHentai** e **Xlecx**, construído em Flutter com foco em leitura fluida, upscale sob demanda e português do Brasil nativo.

[![Release](https://img.shields.io/github/v/release/Darkiu1337/acervo-hc?style=for-the-badge&color=7c5cff&label=vers%C3%A3o)](https://github.com/Darkiu1337/acervo-hc/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/Darkiu1337/acervo-hc/total?style=for-the-badge&color=2ea043&label=downloads)](https://github.com/Darkiu1337/acervo-hc/releases)
[![Flutter](https://img.shields.io/badge/Flutter-3.44-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![License](https://img.shields.io/badge/Licen%C3%A7a-Apache%202.0-orange?style=for-the-badge)](LICENSE)

[Download](#-download) · [Recursos](#-recursos) · [Capturas](#-capturas) · [Compilar](#-compilar-localmente)

</div>

---

## ✨ Recursos

Nascido como fork do **JHenTai**, o Acervo H&C preserva todo o ecossistema original (busca, favoritos, downloads, arquivos, histórico e rankings) e acrescenta o que faz diferença na leitura diária:

| Módulo | Destaques |
| :--- | :--- |
| **📖 Leitor aprimorado** | Zoom contínuo preservado entre páginas, retorno ao topo, atalhos de teclado, `photo_view` ajustado (`Ctrl` + scroll ancorado no cursor) e envio para visualizador externo (nomacs, ImageGlass, XnView etc.) |
| **🪄 Upscale sob demanda** | Nitidez **2× por shader** (bicúbico + AMD FidelityFX CAS) e **Real-CUGAN neural** guiado pela página visível, pulando páginas P&B automaticamente com toggle rápido por galeria |
| **🌐 Fonte Xlecx** | Aba dedicada para `xlecx.one` com 5 listagens, busca, 13 categorias, 1.000+ tags, filtros por artista/paródia/grupo, favoritos locais e **login direto com usuário e senha** (cookies como alternativa) |
| **✅ Já lidos unificados** | Esconde galerias concluídas em **ambos os provedores** com deduplicação cross-provider multi-sinal (título normalizado + bilíngue, artista, páginas, trava contra sequências e hash perceptual 128-bit da capa) |
| **⚡ Navegação leve** | Abas ocultas com tickers pausados, parsing HTML e SQLite fora da thread da UI, scroll suave de mouse/trackpad, cards sem `saveLayer` por item e capas decodificadas no tamanho de miniatura |
| **🇧🇷 Português do Brasil** | Interface traduzida em **pt-BR** de ponta a ponta (selecionável em *Configurações → Idioma*), com suporte mantido nos outros 5 idiomas |

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
Funciona para links do E-Hentai, ExHentai e Xlecx (no macOS, invoque o binário dentro de `Acervo HC.app/Contents/MacOS/`):

```bash
acervo-hc.exe -g "https://e-hentai.org/g/1234567/abcdef1234/"
acervo-hc.exe --gallery="https://xlecx.one/65195-x.html"
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
| `lib/src/pages/read/` | Leitor: layouts, zoom contínuo, atalhos e progresso |
| `lib/src/pages/xlecx/` · `lib/src/network/xlecx_request.dart` | Aba, busca, filtros, detalhes e autenticação do Xlecx |
| `lib/src/service/already_read_service.dart` | Lista de já lidos e deduplicação cross-provider |
| `lib/src/utils/gallery_identity_matcher.dart` · `cover_hash_util.dart` | Matching multi-sinal e hash perceptual 128-bit de capas |
| `lib/src/service/upscale_service.dart` · `neural_upscale_service.dart` | Upscale 2× por shader e Real-CUGAN sob demanda |
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
