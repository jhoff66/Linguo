# Linguo

Tradutor de barra de menu para macOS, feito para conversar no WhatsApp (ou em qualquer app) com quem fala outra língua. Você escreve em português e manda no idioma da pessoa.

## Como usar

- **⌃3 (Control + 3)** no campo de mensagem: troca o que você escreveu pela tradução, ali mesmo. Depois é só dar Enter.
- **⌘3 (Command + 3)** abre o tradutor flutuante. Escreva em português e a tradução aparece ao vivo. Cole a mensagem da outra pessoa e ela vira português.
  - ↩ cola a tradução no app de onde você veio, ⌘↩ só copia, ⇧↩ nova linha, esc fecha.
- O idioma de destino fica no menu do ícone ou no próprio tradutor: espanhol (Espanha ou América Latina), inglês, francês, italiano e alemão.

## Sua chave da OpenAI

O Linguo usa a **sua** conta da OpenAI (modelo `gpt-6-luna`). Na primeira vez que abrir, ele pede a chave:

1. Crie uma em [platform.openai.com/api-keys](https://platform.openai.com/api-keys).
2. Cole na janela do Linguo. Ele testa a chave antes de salvar.

A chave fica só no seu Mac, em `~/Library/Application Support/Linguo/openai.key` (legível só pelo seu usuário). Para trocar, use **Trocar chave da OpenAI…** no menu.

Traduções já feitas ficam guardadas em `~/Library/Application Support/Linguo/cache.json` (até 1000), então frase repetida não gasta API.

## Permissão de Acessibilidade

Para colar sozinho (⌃3 e o ↩ do tradutor), o macOS pede permissão em **Ajustes do Sistema → Privacidade e Segurança → Acessibilidade**. Ative o Linguo. Sem ela, o tradutor ainda funciona copiando a tradução.

## Instalar

Baixe o `Linguo.zip` em [Releases](../../releases), descompacte e arraste o `Linguo.app` para Aplicativos. Na primeira vez, clique com o botão direito no app e escolha **Abrir** (ele não é notarizado pela Apple).

Ou compile (precisa das Command Line Tools do Xcode, macOS 14+):

```sh
./build.sh
cp -R Linguo.app /Applications/
```

## Observação

O ⌘3 é global enquanto o Linguo estiver aberto, então o WhatsApp perde o atalho de ir para a 3ª conversa.
