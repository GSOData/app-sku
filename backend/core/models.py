"""
Models do sistema SKU+ para gestão de validade e estoque de produtos.

Estrutura:
- Usuario: Usuário customizado com controle de acesso por unidade
- UnidadeNegocio: Unidades de negócio da empresa
- SKU: Produtos cadastrados
- LoteValidade: Lotes de cada SKU com controle de validade (FEFO)
- ConfiguracaoAlerta: Configurações de alertas por unidade
- MovimentacaoEstoque: Controle de itens em trânsito
"""

from django.db import models
from django.contrib.auth.models import AbstractUser
from django.core.validators import MinValueValidator
from django.utils import timezone
from datetime import date


class BaseModel(models.Model):
    """
    Model base com campos de auditoria para todos os models.
    """
    created_at = models.DateTimeField(
        'Criado em',
        auto_now_add=True
    )
    updated_at = models.DateTimeField(
        'Atualizado em',
        auto_now=True
    )
    ativo = models.BooleanField(
        'Ativo',
        default=True
    )

    class Meta:
        abstract = True


class UnidadeNegocio(BaseModel):
    """
    Representa uma unidade de negócio/filial da empresa.
    O codigo_unb é único por empresa.
    """
    codigo_unb = models.CharField(
        'Código UNB',
        max_length=20,
        unique=True,
        db_index=True
    )
    nome = models.CharField(
        'Nome da Unidade',
        max_length=150
    )
    endereco = models.TextField(
        'Endereço',
        blank=True,
        null=True
    )

    class Meta:
        verbose_name = 'Unidade de Negócio'
        verbose_name_plural = 'Unidades de Negócio'
        ordering = ['nome']

    def __str__(self):
        return f'{self.codigo_unb} - {self.nome}'


class Usuario(AbstractUser):
    """
    Usuário customizado com relacionamento M2M com UnidadeNegocio
    para controle de permissões por unidade.
    """
    unidades = models.ManyToManyField(
        UnidadeNegocio,
        through='UsuarioUnidade',
        related_name='usuarios',
        verbose_name='Unidades de Acesso',
        blank=True
    )
    telefone = models.CharField(
        'Telefone',
        max_length=20,
        blank=True,
        null=True
    )
    cargo = models.CharField(
        'Cargo',
        max_length=100,
        blank=True,
        null=True
    )

    class Meta:
        verbose_name = 'Usuário'
        verbose_name_plural = 'Usuários'
        ordering = ['first_name', 'last_name']

    def __str__(self):
        return self.get_full_name() or self.username

    def tem_acesso_unidade(self, unidade_id: int) -> bool:
        """
        Verifica se o usuário tem acesso a uma unidade específica.
        Superusuários têm acesso a todas as unidades.
        """
        if self.is_superuser:
            return True
        return self.unidades.filter(id=unidade_id, ativo=True).exists()

    def get_unidades_ids(self) -> list:
        """
        Retorna lista de IDs das unidades que o usuário tem acesso.
        """
        if self.is_superuser:
            return list(UnidadeNegocio.objects.filter(ativo=True).values_list('id', flat=True))
        return list(self.unidades.filter(ativo=True).values_list('id', flat=True))

    def get_papel_unidade(self, unidade_id: int) -> str | None:
        """
        Retorna o papel do usuário em uma unidade específica.
        Superusuários são tratados como DIRETORIA.
        """
        if self.is_superuser:
            return 'DIRETORIA'
        from core.models import UsuarioUnidade
        vinculo = UsuarioUnidade.objects.filter(
            usuario=self,
            unidade_id=unidade_id
        ).first()
        return vinculo.papel if vinculo else None

    def is_vendedor(self, unidade_id: int) -> bool:
        """Verifica se o usuário é VENDEDOR na unidade."""
        return self.get_papel_unidade(unidade_id) == 'VENDEDOR'

    def is_gerente(self, unidade_id: int) -> bool:
        """Verifica se o usuário é GERENTE na unidade."""
        return self.get_papel_unidade(unidade_id) == 'GERENTE'

    def is_diretoria(self) -> bool:
        """
        Verifica se o usuário é DIRETORIA em qualquer unidade.
        DIRETORIA tem acesso consolidado a todas as unidades.
        """
        if self.is_superuser:
            return True
        from core.models import UsuarioUnidade
        return UsuarioUnidade.objects.filter(
            usuario=self,
            papel='DIRETORIA'
        ).exists()

    def is_admin(self) -> bool:
        """
        Verifica se o usuário é ADMIN em qualquer unidade.
        ADMIN tem acesso total ao sistema, incluindo operações destrutivas.
        """
        if self.is_superuser:
            return True
        from core.models import UsuarioUnidade
        return UsuarioUnidade.objects.filter(
            usuario=self,
            papel='ADMIN'
        ).exists()

    def get_max_papel(self) -> str:
        """
        Retorna o papel de maior privilégio do usuário.
        Ordem: ADMIN > DIRETORIA > GERENTE > VENDEDOR
        """
        if self.is_superuser:
            return 'ADMIN'
        from core.models import UsuarioUnidade
        papeis = list(UsuarioUnidade.objects.filter(
            usuario=self
        ).values_list('papel', flat=True))
        
        if 'ADMIN' in papeis:
            return 'ADMIN'
        if 'DIRETORIA' in papeis:
            return 'DIRETORIA'
        if 'GERENTE' in papeis:
            return 'GERENTE'
        if 'VENDEDOR' in papeis:
            return 'VENDEDOR'
        return 'VENDEDOR'  # Default


class UsuarioUnidade(models.Model):
    """
    Tabela intermediária para relacionamento Usuario-UnidadeNegocio.
    Permite adicionar campos extras como papel/função na unidade.
    """
    PAPEL_CHOICES = [
        ('VENDEDOR', 'Vendedor'),      # Somente leitura
        ('GERENTE', 'Gerente'),        # CRUD completo na unidade
        ('DIRETORIA', 'Diretoria'),    # Dashboards e relatórios consolidados
        ('ADMIN', 'Administrador'),    # Acesso total ao sistema
    ]
    
    usuario = models.ForeignKey(
        Usuario,
        on_delete=models.CASCADE,
        verbose_name='Usuário'
    )
    unidade = models.ForeignKey(
        UnidadeNegocio,
        on_delete=models.CASCADE,
        verbose_name='Unidade de Negócio'
    )
    papel = models.CharField(
        'Papel na Unidade',
        max_length=50,
        choices=PAPEL_CHOICES,
        default='VENDEDOR'
    )
    data_vinculo = models.DateField(
        'Data de Vínculo',
        auto_now_add=True
    )

    class Meta:
        verbose_name = 'Vínculo Usuário-Unidade'
        verbose_name_plural = 'Vínculos Usuário-Unidade'
        unique_together = ['usuario', 'unidade']

    def __str__(self):
        return f'{self.usuario} - {self.unidade} ({self.papel})'


class ConfiguracaoAlerta(BaseModel):
    """
    Configurações de alertas de validade.
    Pode ser global (unidade=null) ou específica por unidade.
    """
    unidade = models.OneToOneField(
        UnidadeNegocio,
        on_delete=models.CASCADE,
        related_name='configuracao_alerta',
        verbose_name='Unidade de Negócio',
        null=True,
        blank=True,
        help_text='Se vazio, será configuração global padrão'
    )
    dias_pre_bloqueio = models.PositiveIntegerField(
        'Dias para Pré-Bloqueio',
        default=60,
        validators=[MinValueValidator(1)],
        help_text='Quantidade de dias antes do vencimento para status PRÉ-BLOQUEIO (padrão: 60)'
    )
    dias_bloqueado = models.PositiveIntegerField(
        'Dias para Bloqueado',
        default=30,
        validators=[MinValueValidator(1)],
        help_text='Quantidade de dias antes do vencimento para status BLOQUEADO (padrão: 30)'
    )
    dias_extremamente_critico = models.PositiveIntegerField(
        'Dias para Extremamente Crítico',
        default=7,
        validators=[MinValueValidator(1)],
        help_text='Quantidade de dias antes do vencimento para status EXTREMAMENTE CRÍTICO (padrão: 7)'
    )

    class Meta:
        verbose_name = 'Configuração de Alerta'
        verbose_name_plural = 'Configurações de Alerta'

    def __str__(self):
        if self.unidade:
            return f'Config. Alerta - {self.unidade.codigo_unb}'
        return 'Config. Alerta - Global'

    def clean(self):
        from django.core.exceptions import ValidationError
        errors = {}
        if self.dias_pre_bloqueio <= self.dias_bloqueado:
            errors['dias_pre_bloqueio'] = 'Dias para pré-bloqueio deve ser maior que dias para bloqueado.'
        if self.dias_bloqueado <= self.dias_extremamente_critico:
            errors['dias_bloqueado'] = 'Dias para bloqueado deve ser maior que dias para extremamente crítico.'
        if errors:
            raise ValidationError(errors)


class SKU(BaseModel):
    """
    Representa um produto (Stock Keeping Unit).
    Um SKU pertence a uma unidade de negócio e pode ter múltiplos lotes.
    """

    def produto_image_path(instance, filename):
        """Gera path para upload: media/produtos/<codigo_sku>/<filename>"""
        import os
        ext = filename.split('.')[-1]
        new_filename = f'{instance.codigo_sku}.{ext}'
        return os.path.join('produtos', instance.unidade_negocio.codigo_unb, new_filename)

    codigo_sku = models.CharField(
        'Código SKU',
        max_length=50,
        db_index=True
    )
    nome_produto = models.CharField(
        'Nome do Produto',
        max_length=255,
        db_index=True
    )
    unidade_negocio = models.ForeignKey(
        UnidadeNegocio,
        on_delete=models.PROTECT,
        related_name='skus',
        verbose_name='Unidade de Negócio'
    )
    categoria = models.CharField(
        'Categoria',
        max_length=100,
        blank=True,
        null=True,
        db_index=True
    )
    unidade_medida = models.CharField(
        'Unidade de Medida',
        max_length=20,
        default='UN',
        help_text='Unidade flexível (UN, CX, FD, DZ, PCT, etc.)'
    )
    fator_conversao = models.PositiveIntegerField(
        'Fator de Conversão',
        default=1,
        validators=[MinValueValidator(1)],
        help_text='Quantidade de unidades por caixa/fardo'
    )
    descricao = models.TextField(
        'Descrição',
        blank=True,
        null=True
    )
    imagem = models.ImageField(
        'Imagem do Produto',
        upload_to='produtos/',
        blank=True,
        null=True,
        help_text='Foto do produto para exibição no app'
    )

    qtd_total_020502 = models.IntegerField(
        'Estoque Total (020502)',
        default=0,
        help_text='Estoque físico real total convertido em unidades base'
    )
    qtd_buffer_020304 = models.IntegerField(
        'Buffer em Pedidos (020304)',
        default=0,
        help_text='Estoque retido em pedidos de saída'
    )
    qtd_disponivel_venda = models.IntegerField(
        'Disponível para Venda',
        default=0,
        help_text='Calculado: total - buffer'
    )
    validade_inicio_range = models.DateField(
        'Início do Range de Validade',
        null=True,
        blank=True,
        help_text='Data de validade do produto mais antigo disponível (FEFO reverso)'
    )
    validade_fim_range = models.DateField(
        'Fim do Range de Validade',
        null=True,
        blank=True,
        help_text='Data de validade mais longa do estoque disponível'
    )

    class Meta:
        verbose_name = 'SKU'
        verbose_name_plural = 'SKUs'
        ordering = ['nome_produto']
        unique_together = ['codigo_sku', 'unidade_negocio']
        indexes = [
            models.Index(fields=['codigo_sku', 'unidade_negocio']),
            models.Index(fields=['nome_produto']),
        ]

    def __str__(self):
        return f'{self.codigo_sku} - {self.nome_produto}'

    @property
    def quantidade_em_transito(self) -> int:
        """
        Retorna a quantidade de itens em trânsito (entrada).
        """
        from django.db.models import Sum
        total = self.movimentacoes.filter(
            ativo=True,
            tipo='ENTRADA',
            status='EM_TRANSITO'
        ).aggregate(total=Sum('quantidade'))['total']
        return total or 0

    @property
    def valor_total_estoque(self) -> float:
        """
        Calcula o valor com base na quantidade real. Custos devem ser avaliados de outra forma futuramente.
        """
        return 0.0

    def get_status(self, config: 'ConfiguracaoAlerta' = None) -> dict:
        """
        Calcula o status do SKU baseado no field `validade_inicio_range`.
        """
        # ==============================================================================
        # CORREÇÃO: ITENS SEM VALIDADE MAS COM ESTOQUE (Ex: Destilados novos)
        # ==============================================================================
        if not self.validade_inicio_range:
            if self.qtd_disponivel_venda > 0:
                return {
                    'status': 'OK',
                    'cor': 'verde',
                    'dias_restantes': None,
                }
            else:
                return {
                    'status': 'SEM_ESTOQUE',
                    'cor': 'cinza',
                    'dias_restantes': None,
                }

        # Busca configuração específica da unidade ou global
        if config is None:
            config = getattr(
                self.unidade_negocio, 
                'configuracao_alerta', 
                None
            )
            if config is None:
                config = ConfiguracaoAlerta.objects.filter(
                    unidade__isnull=True, 
                    ativo=True
                ).first()
        
        # Valores padrão se não houver configuração
        dias_pre_bloqueio = config.dias_pre_bloqueio if config else 60
        dias_bloqueado = config.dias_bloqueado if config else 30
        dias_extremamente_critico = config.dias_extremamente_critico if config else 7
        
        hoje = date.today()
        dias_restantes = (self.validade_inicio_range - hoje).days
        
        if dias_restantes < 0:
            return {
                'status': 'VENCIDO',
                'cor': 'preto',
                'dias_restantes': dias_restantes,
            }
        elif dias_restantes <= dias_extremamente_critico:
            return {
                'status': 'EXTREMAMENTE_CRITICO',
                'cor': 'vermelho',
                'dias_restantes': dias_restantes,
            }
        elif dias_restantes <= dias_bloqueado:
            return {
                'status': 'BLOQUEADO',
                'cor': 'laranja',
                'dias_restantes': dias_restantes,
            }
        elif dias_restantes <= dias_pre_bloqueio:
            return {
                'status': 'PRE_BLOQUEIO',
                'cor': 'amarelo',
                'dias_restantes': dias_restantes,
            }
        else:
            return {
                'status': 'OK',
                'cor': 'verde',
                'dias_restantes': dias_restantes,
            }


class MovimentacaoEstoque(BaseModel):
    """
    Controle de movimentações de estoque, incluindo itens em trânsito.
    """
    TIPO_CHOICES = [
        ('ENTRADA', 'Entrada'),
        ('SAIDA', 'Saída'),
        ('TRANSFERENCIA', 'Transferência'),
        ('AJUSTE', 'Ajuste'),
    ]
    
    STATUS_CHOICES = [
        ('EM_TRANSITO', 'Em Trânsito'),
        ('RECEBIDO', 'Recebido'),
        ('CANCELADO', 'Cancelado'),
    ]

    sku = models.ForeignKey(
        SKU,
        on_delete=models.PROTECT,
        related_name='movimentacoes',
        verbose_name='SKU'
    )
    tipo = models.CharField(
        'Tipo',
        max_length=15,
        choices=TIPO_CHOICES
    )
    status = models.CharField(
        'Status',
        max_length=15,
        choices=STATUS_CHOICES,
        default='EM_TRANSITO'
    )
    quantidade = models.PositiveIntegerField(
        'Quantidade',
        validators=[MinValueValidator(1)]
    )
    unidade_origem = models.ForeignKey(
        UnidadeNegocio,
        on_delete=models.PROTECT,
        related_name='movimentacoes_saida',
        verbose_name='Unidade Origem',
        null=True,
        blank=True
    )
    unidade_destino = models.ForeignKey(
        UnidadeNegocio,
        on_delete=models.PROTECT,
        related_name='movimentacoes_entrada',
        verbose_name='Unidade Destino',
        null=True,
        blank=True
    )
    data_prevista = models.DateField(
        'Data Prevista',
        null=True,
        blank=True
    )
    data_efetiva = models.DateField(
        'Data Efetiva',
        null=True,
        blank=True
    )
    observacao = models.TextField(
        'Observação',
        blank=True,
        null=True
    )
    usuario = models.ForeignKey(
        Usuario,
        on_delete=models.PROTECT,
        related_name='movimentacoes',
        verbose_name='Usuário',
        null=True,
        blank=True
    )

    class Meta:
        verbose_name = 'Movimentação de Estoque'
        verbose_name_plural = 'Movimentações de Estoque'
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.tipo} - {self.sku.codigo_sku} ({self.quantidade})'


class HistoricoUpload(BaseModel):
    """
    Histórico de uploads de arquivos (Grade 020502 ou Contagens).
    Registra cada processamento de arquivo para auditoria.
    """
    TIPO_ARQUIVO_CHOICES = [
        ('GRADE', 'Grade 020502'),
        ('CONTAGEM', 'Contagem'),
        ('FEFO', 'Estoque FEFO (3 Arquivos)'),
    ]
    
    STATUS_CHOICES = [
        ('SUCESSO', 'Sucesso'),
        ('ERRO', 'Erro'),
    ]
    
    tipo_arquivo = models.CharField(
        'Tipo de Arquivo',
        max_length=20,
        choices=TIPO_ARQUIVO_CHOICES
    )
    usuario = models.ForeignKey(
        Usuario,
        on_delete=models.SET_NULL,
        related_name='uploads',
        verbose_name='Usuário',
        null=True
    )
    unidade_negocio = models.ForeignKey(
        UnidadeNegocio,
        on_delete=models.CASCADE,
        related_name='historico_uploads',
        verbose_name='Unidade de Negócio'
    )
    status = models.CharField(
        'Status',
        max_length=20,
        choices=STATUS_CHOICES,
        default='SUCESSO'
    )
    linhas_processadas = models.PositiveIntegerField(
        'Linhas Processadas',
        default=0
    )
    nome_arquivo = models.CharField(
        'Nome do Arquivo',
        max_length=255,
        blank=True,
        null=True
    )
    mensagem_erro = models.TextField(
        'Mensagem de Erro',
        blank=True,
        null=True
    )

    class Meta:
        verbose_name = 'Histórico de Upload'
        verbose_name_plural = 'Históricos de Upload'
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.tipo_arquivo} - {self.unidade_negocio.codigo_unb} ({self.created_at.strftime("%d/%m/%Y %H:%M")})'


class LogConsulta(BaseModel):
    """
    Log de consultas realizadas para auditoria.
    """
    usuario = models.ForeignKey(
        Usuario,
        on_delete=models.SET_NULL,
        related_name='consultas',
        verbose_name='Usuário',
        null=True
    )
    tipo_consulta = models.CharField(
        'Tipo de Consulta',
        max_length=50,
        choices=[
            ('VALIDADE', 'Consulta de Validade'),
            ('CRITICIDADE', 'Relatório de Criticidade'),
            ('ESTOQUE', 'Consulta de Estoque'),
        ]
    )
    parametros = models.JSONField(
        'Parâmetros',
        default=dict,
        blank=True
    )
    ip_address = models.GenericIPAddressField(
        'Endereço IP',
        null=True,
        blank=True
    )

    class Meta:
        verbose_name = 'Log de Consulta'
        verbose_name_plural = 'Logs de Consulta'
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.usuario} - {self.tipo_consulta} ({self.created_at})'