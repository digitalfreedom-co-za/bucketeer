# Ajuda do Bucketeer

O Bucketeer é um app para Mac de armazenamento de objetos: Amazon S3, provedores compatíveis com S3 e Azure Blob Storage. Este guia cobre todos os recursos, da primeira conta às unidades no Finder e às tarefas de sincronização.

## Adicionar uma conta

- Clique em **+** no cabeçalho da barra lateral.
- Escolha um provedor: AWS S3, Azure Blob Storage, Civo, Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj ou Personalizado (MinIO e qualquer outro endpoint compatível com S3).
- Digite um nome, a região ou o endpoint e suas credenciais (chave de acesso e segredo; no Azure, a chave da conta de armazenamento).
- Clique em **Testar conexão** e depois em **Salvar**.

Suas credenciais ficam armazenadas nas Chaves do macOS neste Mac. O Bucketeer não tem servidor nem conta de usuário; ele se comunica diretamente com os endpoints que você configurar.

## Editar uma conta

O segredo fica oculto quando você edita uma conta. Clique em **Mostrar credenciais salvas** e confirme com o Touch ID ou a senha do Mac para vê-lo. Se você salvar sem mexer no segredo, o segredo armazenado não muda.

## Navegar por buckets e objetos

- Clique em uma conta na barra lateral para listar os buckets dela.
- Clique duas vezes em um bucket ou pasta para abri-lo. Use a barra de caminho ou a seta para cima para voltar.
- Selecione um arquivo para ver os detalhes e uma pré-visualização do Quick Look no painel da direita.
- Use o campo de busca para filtrar a pasta atual.

## Fazer upload e download

- **Upload**: clique no botão de upload ou pressione **⌘U**. Você também pode arrastar arquivos do Finder para a lista de objetos ou para um bucket.
- **Download**: clique com o botão direito em um arquivo e escolha **Baixar…**.
- Arquivos grandes são transferidos em partes paralelas. Um upload interrompido continua de onde parou.
- Todas as transferências aparecem em **Transferências** na barra lateral, com o progresso e um botão para cancelar.
- Em **Ajustes → Transferências** você pode limitar a largura de banda total.

## Abrir arquivos em outros apps

- Clique duas vezes em um arquivo, ou clique com o botão direito e escolha **Abrir**, para abri-lo no app padrão. **Abrir com** lista outros apps que podem abri-lo; **Outro…** permite escolher qualquer app.
- O Bucketeer baixa o arquivo para uma pasta temporária e o acompanha. Pouco depois de cada salvamento, o arquivo é enviado de volta pela fila de transferências normal, então a criptografia do lado do cliente também vale.
- Se o objeto foi alterado ou apagado no servidor depois que você o abriu, o Bucketeer não o sobrescreve. Sua versão é enviada ao lado como "nome (conflict data).ext" e o Bucketeer mostra um aviso.
- A cópia temporária é apagada assim que o servidor tem o seu último salvamento. Se um salvamento não pôde ser enviado (por exemplo, sem conexão), o Bucketeer mantém o arquivo neste Mac e oferece **Enviar novamente**, **Salvar uma cópia…** ou **Descartar alteração**, também na próxima abertura, por exemplo após uma falha.

## Gerenciar objetos

- **Nova pasta**: botão da barra de ferramentas ou **⇧⌘N**.
- **Renomear…**: clique com o botão direito em um objeto. Renomear é uma cópia no servidor seguida de uma exclusão.
- **Excluir**: selecione um ou mais objetos, clique no botão da lixeira e confirme.
- **Copiar deep link**: copia um link `bucketeer://` para o objeto, que o abre no Bucketeer de qualquer lugar do seu Mac.

## Links de compartilhamento

Clique com o botão direito em um arquivo e escolha **Obter link de compartilhamento…**. Escolha por quanto tempo o link fica válido e depois copie ou compartilhe. O link é assinado no seu Mac com suas credenciais; qualquer pessoa que o tenha pode baixar o arquivo até ele expirar.

## Versões

Clique com o botão direito em um arquivo e escolha **Mostrar versões…** para ver o histórico de versões. Você pode restaurar uma versão anterior como a nova cópia mais recente ou excluir uma única versão. O bucket precisa ter o controle de versões ativado no provedor.

## Metadados e tags

Clique com o botão direito em um arquivo e escolha **Metadados e tags…** para editar cabeçalhos HTTP (tipo de conteúdo, controle de cache e outros), metadados de usuário e tags, e para ver a classe de armazenamento. Alguns provedores não suportam todos os campos; o Bucketeer avisa quando for o caso.

**Ajustes → Regras** contém as regras de marcação automática: elas adicionam tags e metadados aos novos uploads que correspondam a um padrão de nome de arquivo ou a um tipo MIME.

## Painel do bucket

Clique em **Painel** na barra de ferramentas de um bucket aberto. Ele mostra o número de objetos, o tamanho total, os maiores objetos, uma estimativa aproximada do custo mensal e as regras de ciclo de vida, a configuração de CORS e a política do bucket (somente leitura).

## Lixeira

Quando você exclui objetos, o Bucketeer pode manter uma cópia local neste Mac (**Ajustes → Transferências → Lixeira**). Abra a lixeira em **Janela → Lixeira** (**⇧⌘⌫**) e clique em **Restaurar** para enviar de volta uma cópia em cache ao local original. O objeto no provedor é excluído na hora; só a cópia local pode ser restaurada. As entradas são removidas automaticamente após o período de retenção que você definir.

## Registro de atividade

**Janela → Registro de atividade** (**⌥⌘0**) lista uploads, downloads, exclusões, sincronizações, links de compartilhamento e alterações de contas. Você pode filtrar, buscar e exportar a lista como CSV. As entradas ficam neste Mac por 180 dias.

## Criptografia no lado do cliente

Em **Ajustes → Criptografia** você pode criar uma chave para um bucket. A partir daí, cada upload para esse bucket é criptografado no seu Mac (AES-256-GCM) antes de sair, e os downloads são descriptografados durante a transferência. A chave fica armazenada nas Chaves do macOS somente neste Mac.

Importante: se você perder a chave, ninguém consegue descriptografar esses objetos, nem nós. Nesta versão do Bucketeer, buckets criptografados não podem ser montados no Finder.

## Spotlight

**Ajustes → Transferências → Spotlight** vem desativado por padrão. Quando você o ativa, os nomes dos objetos que você navega passam a poder ser buscados no Spotlight. O conteúdo dos arquivos nunca é indexado, e o índice fica neste Mac.

## Atalhos e Siri

O Bucketeer adiciona ações ao app Atalhos: listar buckets, fazer upload de um arquivo, criar um link de compartilhamento e executar uma tarefa de sincronização. Use-as nos seus próprios atalhos ou peça à Siri.

## Recursos Pro

Estes recursos precisam do Bucketeer Pro:

- **Montar como unidade**: clique com o botão direito em um bucket e escolha **Montar como unidade** para usá-lo no Finder como um disco. Requer macOS 14.1 ou posterior. As unidades montadas aparecem em **Unidades montadas** na barra lateral; clique com o botão direito para **Desmontar**. Buckets com criptografia no lado do cliente não podem ser montados. As alterações feitas no servidor aparecem no Finder quando você atualiza o bucket no Bucketeer. Se um arquivo que você edita no Finder foi alterado no servidor nesse meio tempo, sua versão é salva ao lado como cópia em conflito.
- **Tarefas de sincronização**: na seção **Sincronização**, crie uma tarefa que copia, move ou espelha entre dois buckets, entre contas e provedores, ou entre uma pasta local e um bucket. Execute-a manualmente, ao abrir o app, a cada N minutos ou quando a pasta local mudar.
- **Pastas monitoradas**: **Nova pasta monitorada…** faz upload para um bucket de cada arquivo novo em uma pasta local.
- **Copiar para outra conta…**: copia objetos para outra conta ou outro provedor. Quando os dois lados permitem, a cópia é feita no servidor e os dados não passam pelo seu Mac.
- **Modo barra de menus**: **Ajustes → Geral** mantém o Bucketeer em execução na barra de menus para que as unidades e as tarefas de sincronização continuem ativas quando a janela principal estiver fechada.

Todo o resto está disponível no nível gratuito.

## Bucketeer Pro, avaliação e compra

O Bucketeer Pro é uma compra única dentro do app, feita pela App Store, sem assinatura. Abra **Ajustes → Pro** ou qualquer recurso Pro para ver o preço na sua moeda e comprar.

Você pode testar o Bucketeer Pro gratuitamente por 14 dias. Antes de começar, a página de compra mostra a duração da avaliação, o que acontece depois e o preço do Pro Vitalício; depois clique em **Iniciar avaliação**. Quando a avaliação termina, o Bucketeer continua na versão gratuita e nada é cobrado. A avaliação pode ser iniciada uma vez por ID Apple, e restaurar compras também traz de volta uma avaliação em andamento em outro Mac.

- **Restaurar compra** traz o Pro de volta em outro Mac ou depois de reinstalar.
- **Resgatar código** (macOS 15 ou posterior) abre a janela da Apple para códigos de oferta.

## Atalhos de teclado

- **⌘U**: Fazer upload de arquivos
- **⇧⌘N**: Nova pasta
- **⌥⌘0**: Registro de atividade
- **⇧⌘⌫**: Lixeira
- **⌘?**: Ajuda do Bucketeer
- **⌘,**: Ajustes

## Privacidade

O Bucketeer não coleta dados de análise e não contém rastreamento. Suas contas, chaves e registros ficam neste Mac. O tráfego de rede vai apenas para os provedores de armazenamento que você configurar e para a Apple, no caso de compras. Detalhes: **Ajuda → Política de privacidade…**

## Precisa de ajuda?

- Relatar um problema: **Ajuda → Relatar um problema…** ou <https://support.apps.digitalfreedom.co.za/>
- Site: <https://digitalfreedom.co.za>
