# Ajuda do Bucketeer

O Bucketeer é uma aplicação para Mac para armazenamento de objetos: Amazon S3, fornecedores compatíveis com S3 e Azure Blob Storage. Este guia aborda todas as funcionalidades, desde a primeira conta até aos discos no Finder e às tarefas de sincronização.

## Adicionar uma conta

- Clique em **+** no cabeçalho da barra lateral.
- Escolha um fornecedor: AWS S3, Azure Blob Storage, Civo, Cloudflare R2, Backblaze B2, Wasabi, DigitalOcean Spaces, Storj ou Custom (MinIO e qualquer outro endpoint compatível com S3).
- Introduza um nome, a região ou o endpoint e as suas credenciais (chave de acesso e segredo; no Azure, a chave da conta de armazenamento).
- Se a sua chave só tiver acesso a um bucket (comum no Civo), introduza o nome em **Bucket**; a conta passa a mostrar apenas esse bucket. As chaves do Civo só funcionam na região em que foram criadas.
- Clique em **Testar ligação** e depois em **Guardar**.

As suas credenciais são guardadas no porta-chaves do macOS neste Mac. O Bucketeer não tem servidor nem conta de utilizador; comunica diretamente com os endpoints que configurar.

## Editar uma conta

O segredo fica oculto quando edita uma conta. Clique em **Revelar credenciais guardadas** e confirme com Touch ID ou com a palavra-passe do Mac para o ver. Se guardar sem alterar o segredo, o segredo guardado mantém-se.

## Navegar em buckets e objetos

- Clique numa conta na barra lateral para ver os respetivos buckets.
- Faça duplo clique num bucket ou numa pasta para o abrir. Use a barra de navegação ou a seta para cima para voltar atrás.
- Selecione um ficheiro para ver os detalhes e uma pré-visualização Quick Look no painel da direita.
- Use o campo de pesquisa para filtrar a pasta atual.

## Carregar e descarregar

- **Carregar**: clique no botão de carregamento ou prima **⌘U**. Também pode arrastar ficheiros do Finder para a lista de objetos ou para um bucket.
- **Descarregar**: clique com o botão direito num ficheiro e escolha **Descarregar…**.
- Os ficheiros grandes são transferidos em partes paralelas. Um carregamento interrompido continua a partir do ponto onde parou.
- Todas as transferências aparecem em **Transferências** na barra lateral, com o progresso e um botão para cancelar.
- Em **Definições → Transferências** pode limitar a largura de banda total.

## Abrir ficheiros noutras apps

- Faça duplo clique num ficheiro, ou clique com o botão direito e escolha **Abrir**, para o abrir na app predefinida. **Abrir com** mostra outras apps que o conseguem abrir; **Outra…** permite escolher qualquer app.
- O Bucketeer descarrega o ficheiro para uma pasta temporária e acompanha-o. Pouco depois de cada gravação, o ficheiro é carregado de novo pela fila de transferências normal, por isso a encriptação do lado do cliente também se aplica.
- Se o objeto foi alterado ou apagado no servidor depois de o abrir, o Bucketeer não o substitui. A sua versão é carregada ao lado como "nome (conflict data).ext" e o Bucketeer mostra uma mensagem.
- A cópia temporária é apagada assim que o servidor tem a sua última gravação. Se uma gravação não pôde ser carregada (por exemplo, sem ligação), o Bucketeer mantém o ficheiro neste Mac e propõe **Carregar novamente**, **Guardar uma cópia…** ou **Descartar alteração**, também no arranque seguinte, por exemplo após uma falha.

## Gerir objetos

- **Nova pasta**: botão da barra de ferramentas ou **⇧⌘N**.
- **Mudar o nome…**: clique com o botão direito num objeto. Mudar o nome é uma cópia do lado do servidor seguida de uma eliminação. Mudar o nome ou eliminar uma pasta aplica-se a todo o conteúdo, e uma mudança de nome nunca substitui um nome existente.
- **Eliminar**: selecione um ou mais objetos, clique no botão do lixo e confirme.
- **Copiar ligação direta**: copia uma ligação `bucketeer://` para o objeto, que o abre no Bucketeer a partir de qualquer lugar do seu Mac.

## Ligações de partilha

Clique com o botão direito num ficheiro e escolha **Obter ligação de partilha…**. Escolha durante quanto tempo a ligação é válida e depois copie-a ou partilhe-a. A ligação é assinada no seu Mac com as suas credenciais; qualquer pessoa que a tenha pode descarregar o ficheiro até que expire.

## Versões

Clique com o botão direito num ficheiro e escolha **Mostrar versões…** para ver o histórico de versões. Pode restaurar uma versão anterior como a nova cópia mais recente ou eliminar uma única versão. O bucket tem de ter o controlo de versões ativado no fornecedor.

## Metadados e etiquetas

Clique com o botão direito num ficheiro e escolha **Metadados e etiquetas…** para editar cabeçalhos HTTP (tipo de conteúdo, controlo de cache e outros), metadados de utilizador e etiquetas, e para ver a classe de armazenamento. Alguns fornecedores não suportam todos os campos; o Bucketeer indica quando é esse o caso.

**Definições → Regras** contém as regras de etiquetagem automática: acrescentam etiquetas e metadados aos novos carregamentos que correspondam a um padrão de nome de ficheiro ou a um tipo MIME.

## Painel do bucket

Clique em **Painel** na barra de ferramentas de um bucket aberto. Mostra o número de objetos, o tamanho total, os maiores objetos, uma estimativa aproximada do custo mensal e as regras de ciclo de vida, a configuração CORS e a política do bucket (só de leitura).

## Lixo

Quando elimina objetos, o Bucketeer pode guardar uma cópia local neste Mac (**Definições → Transferências → Lixo**). Abra o lixo com **Janela → Lixo** (**⇧⌘⌫**) e clique em **Restaurar** para voltar a carregar uma cópia em cache para o local original. O objeto no fornecedor é eliminado de imediato; só a cópia local pode ser restaurada. As entradas são removidas automaticamente após o período de retenção que definir.

## Registo de atividade

**Janela → Registo de atividade** (**⌥⌘0**) lista carregamentos, descarregamentos, eliminações, sincronizações, ligações de partilha e alterações de contas. Pode filtrar, pesquisar e exportar a lista como CSV. As entradas ficam guardadas neste Mac durante 180 dias.

## Encriptação do lado do cliente

Em **Definições → Encriptação** pode criar uma chave para um bucket. A partir daí, cada carregamento para esse bucket é encriptado no seu Mac (AES-256-GCM) antes de sair, e os descarregamentos são desencriptados durante a transferência. A chave é guardada no porta-chaves do macOS apenas neste Mac.

Importante: se perder a chave, ninguém consegue desencriptar esses objetos, nem nós. Nesta versão do Bucketeer, os buckets encriptados não podem ser montados no Finder.

## Spotlight

**Definições → Transferências → Spotlight** está desativado por predefinição. Quando o ativa, os nomes dos objetos que percorre passam a poder ser pesquisados no Spotlight. O conteúdo dos ficheiros nunca é indexado e o índice fica neste Mac.

## Atalhos e Siri

O Bucketeer acrescenta ações à aplicação Atalhos: listar buckets, carregar um ficheiro, criar uma ligação de partilha e executar uma tarefa de sincronização. Use-as nos seus próprios atalhos ou peça à Siri.

## Funcionalidades Pro

Estas funcionalidades precisam do Bucketeer Pro:

- **Montar como disco**: clique com o botão direito num bucket e escolha **Montar como disco** para o usar no Finder como um disco. Os discos montados aparecem em **Discos montados** na barra lateral; clique com o botão direito para **Desmontar**. Os buckets com encriptação do lado do cliente não podem ser montados. As alterações feitas no servidor aparecem no Finder quando atualiza o bucket no Bucketeer. Se um ficheiro que está a editar no Finder foi entretanto alterado no servidor, a sua versão é guardada ao lado como cópia em conflito.
- **Tarefas de sincronização**: na secção **Sincronização**, crie uma tarefa que copia, move ou espelha entre dois buckets, entre contas e fornecedores, ou entre uma pasta local e um bucket. Execute-a manualmente, ao iniciar, a cada N minutos ou quando a pasta local mudar. Ao mover de uma pasta local, cada ficheiro de origem vai para o Lixo depois de copiado, para que uma alteração de última hora nunca se perca.
- **Pastas monitorizadas**: **Nova pasta monitorizada…** carrega para um bucket cada ficheiro novo de uma pasta local.
- **Copiar para outra conta…**: copia objetos para outra conta ou outro fornecedor. Quando ambos os lados o permitem, a cópia é feita do lado do servidor e os dados não passam pelo seu Mac.
- **Modo da barra de menus**: **Definições → Geral** mantém o Bucketeer em execução na barra de menus, para que os discos e as tarefas de sincronização continuem ativos quando a janela principal está fechada.

Tudo o resto está disponível no nível gratuito.

## Bucketeer Pro, período experimental e compra

O Bucketeer Pro é uma compra única dentro da aplicação, feita através da App Store, sem subscrição. Abra **Definições → Pro** ou qualquer funcionalidade Pro para ver o preço na sua moeda e comprar.

Pode experimentar o Bucketeer Pro gratuitamente durante 14 dias. Antes de começar, a página de compra mostra a duração do período experimental, o que acontece depois e o preço do Pro Vitalício; depois clique em **Iniciar período experimental**. Quando o período experimental termina, o Bucketeer continua na versão gratuita e nada é cobrado. O período experimental pode ser iniciado uma vez por ID Apple, e restaurar compras também recupera um período experimental em curso noutro Mac.

- **Restaurar compra** reativa o Pro noutro Mac ou depois de reinstalar.
- **Resgatar código** abre a folha da Apple para códigos de oferta.

## Atalhos de teclado

- **⌘U**: Carregar ficheiros
- **⇧⌘N**: Nova pasta
- **⌥⌘0**: Registo de atividade
- **⇧⌘⌫**: Lixo
- **⌘?**: Ajuda do Bucketeer
- **⌘,**: Definições

## Privacidade

O Bucketeer não recolhe dados de análise e não contém rastreamento. As suas contas, chaves e registos ficam neste Mac. O tráfego de rede vai apenas para os fornecedores de armazenamento que configurar e para a Apple, no caso de compras. Detalhes: **Ajuda → Política de Privacidade…**

## Precisa de ajuda?

- Comunicar um problema: **Ajuda → Comunicar um problema…** ou <https://support.apps.digitalfreedom.co.za/>
- Site: <https://digitalfreedom.co.za>
