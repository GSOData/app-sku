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


class UsuarioUnidade(models.Model):
    """
    Tabela intermediária para relacionamento Usuario-UnidadeNegocio.
    Permite adicionar campos extras como papel/função na unidade.
    """
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
        choices=[
            ('OPERADOR', 'Operador'),
            ('SUPERVISOR', 'Supervisor'),
            ('GERENTE', 'Gerente'),
        ],
        default='OPERADOR'
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
    
    Regras de status:
    - Vencido: data_validade < hoje
    - Crítico: (data_validade - hoje) <= dias_para_critico (padrão: 30 dias)
    - Pré-Bloqueio: entre dias_para_critico+1 e dias_para_pre_bloqueio (31-45 dias)
    - OK: acima de dias_para_pre_bloqueio
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
    dias_para_critico = models.PositiveIntegerField(
        'Dias para Crítico',
        default=30,
        validators=[MinValueValidator(1)],
        help_text='Quantidade de dias antes do vencimento para status CRÍTICO'
    )
    dias_para_pre_bloqueio = models.PositiveIntegerField(
        'Dias para Pré-Bloqueio',
        default=45,
        validators=[MinValueValidator(1)],
        help_text='Quantidade de dias antes do vencimento para status PRÉ-BLOQUEIO'
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
        if self.dias_para_pre_bloqueio <= self.dias_para_critico:
            raise ValidationError({
                'dias_para_pre_bloqueio': 
                'Dias para pré-bloqueio deve ser maior que dias para crítico.'
            })


class SKU(BaseModel):
    """
    Representa um produto (Stock Keeping Unit).
    Um SKU pertence a uma unidade de negócio e pode ter múltiplos lotes.
    """
    UNIDADE_MEDIDA_CHOICES = [
        ('UN', 'Unidade'),
        ('KG', 'Quilograma'),
        ('L', 'Litro'),
        ('CX', 'Caixa'),
        ('PC', 'Pacote'),
        ('FD', 'Fardo'),
        ('M', 'Metro'),
    ]

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
        max_length=5,
        choices=UNIDADE_MEDIDA_CHOICES,
        default='UN'
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
    def lote_mais_proximo(self):
        """
        Retorna o lote com data de validade mais próxima (FEFO).
        Considera apenas lotes ativos com estoque > 0.
        """
        return self.lotes.filter(
            ativo=True,
            qtd_estoque__gt=0
        ).order_by('data_validade').first()

    @property
    def quantidade_total_estoque(self) -> int:
        """
        Retorna a soma de todos os lotes ativos deste SKU.
        """
        from django.db.models import Sum
        total = self.lotes.filter(ativo=True).aggregate(
            total=Sum('qtd_estoque')
        )['total']
        return total or 0

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

    def get_status(self, config: 'ConfiguracaoAlerta' = None) -> dict:
        """
        Calcula o status do SKU baseado no lote mais próximo do vencimento.
        
        Returns:
            dict com 'status', 'cor', 'dias_restantes', 'lote'
        """
        lote = self.lote_mais_proximo
        
        if not lote:
            return {
                'status': 'SEM_ESTOQUE',
                'cor': 'cinza',
                'dias_restantes': None,
                'lote': None
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
        dias_critico = config.dias_para_critico if config else 30
        dias_pre_bloqueio = config.dias_para_pre_bloqueio if config else 45
        
        hoje = date.today()
        dias_restantes = (lote.data_validade - hoje).days
        
        if dias_restantes < 0:
            return {
                'status': 'VENCIDO',
                'cor': 'preto',
                'dias_restantes': dias_restantes,
                'lote': lote
            }
        elif dias_restantes <= dias_critico:
            return {
                'status': 'CRITICO',
                'cor': 'vermelho',
                'dias_restantes': dias_restantes,
                'lote': lote
            }
        elif dias_restantes <= dias_pre_bloqueio:
            return {
                'status': 'PRE_BLOQUEIO',
                'cor': 'amarelo',
                'dias_restantes': dias_restantes,
                'lote': lote
            }
        else:
            return {
                'status': 'OK',
                'cor': 'verde',
                'dias_restantes': dias_restantes,
                'lote': lote
            }


class LoteValidade(BaseModel):
    """
    Representa um lote de um SKU com controle de validade.
    Segue a lógica FEFO (First Expired, First Out).
    """
    sku = models.ForeignKey(
        SKU,
        on_delete=models.CASCADE,
        related_name='lotes',
        verbose_name='SKU'
    )
    numero_lote = models.CharField(
        'Número do Lote',
        max_length=50,
        db_index=True
    )
    data_validade = models.DateField(
        'Data de Validade',
        db_index=True
    )
    data_fabricacao = models.DateField(
        'Data de Fabricação',
        null=True,
        blank=True
    )
    qtd_estoque = models.PositiveIntegerField(
        'Quantidade em Estoque',
        default=0,
        validators=[MinValueValidator(0)]
    )
    localizacao = models.CharField(
        'Localização',
        max_length=50,
        blank=True,
        null=True,
        help_text='Posição física no estoque (ex: A1-P2-N3)'
    )
    custo_unitario = models.DecimalField(
        'Custo Unitário',
        max_digits=12,
        decimal_places=2,
        null=True,
        blank=True
    )
    fornecedor = models.CharField(
        'Fornecedor',
        max_length=150,
        blank=True,
        null=True
    )

    class Meta:
        verbose_name = 'Lote/Validade'
        verbose_name_plural = 'Lotes/Validades'
        ordering = ['data_validade']
        unique_together = ['sku', 'numero_lote']
        indexes = [
            models.Index(fields=['data_validade']),
            models.Index(fields=['sku', 'data_validade']),
            models.Index(fields=['numero_lote']),
        ]

    def __str__(self):
        return f'{self.sku.codigo_sku} - Lote {self.numero_lote} (Val: {self.data_validade})'

    @property
    def dias_ate_vencimento(self) -> int:
        """
        Retorna quantidade de dias até o vencimento.
        Valores negativos indicam produto vencido.
        """
        return (self.data_validade - date.today()).days

    @property
    def esta_vencido(self) -> bool:
        """Verifica se o lote está vencido."""
        return self.data_validade < date.today()


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
    lote = models.ForeignKey(
        LoteValidade,
        on_delete=models.PROTECT,
        related_name='movimentacoes',
        verbose_name='Lote',
        null=True,
        blank=True,
        help_text='Lote específico (obrigatório para saída)'
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
