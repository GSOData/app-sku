"""
Views do sistema SKU+ para a API REST.

Implementa:
- Autenticação JWT
- CRUD com filtros avançados
- Endpoints customizados para as telas do App
- Controle de acesso por unidade
"""

from rest_framework import viewsets, status, filters
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework_simplejwt.tokens import RefreshToken
from django.contrib.auth import authenticate
from django.db.models import Q, Sum, Prefetch
from django_filters.rest_framework import DjangoFilterBackend
from datetime import date

from .permissions import (
    IsVendedor,
    IsGerente,
    IsDiretoria,
    IsAdmin,
    IsGerenteOuDiretoria,
    IsControle,
    CanManageSettings,
    CanReadSKU,
    CanManageUpload,
    ObjectBelongsToUserUnit,
)

from .models import (
    UnidadeNegocio,
    Usuario,
    UsuarioUnidade,
    ConfiguracaoAlerta,
    SKU,
    MovimentacaoEstoque,
    LogConsulta,
    HistoricoUpload,
    ModuloMenu,
    PermissaoMenu,
    LancamentoCriticoManual, # <-- ADICIONADO NOVO MODELO
)
from .serializers import (
    UnidadeNegocioSerializer,
    UnidadeNegocioResumoSerializer,
    UsuarioSerializer,
    UsuarioCreateSerializer,
    LoginSerializer,
    LoginResponseSerializer,
    ConfiguracaoAlertaSerializer,
    SKUSerializer,
    SKUListSerializer,
    SKUEstoqueSerializer,
    SKUCriticidadeSerializer,
    MovimentacaoEstoqueSerializer,
    LogConsultaSerializer,
    NotificacaoAlertaSerializer,
    HistoricoUploadSerializer,
    HistoricoUploadUltimoSerializer,
    MenuDinamicoSerializer,
    LancamentoCriticoManualSerializer, # <-- ADICIONADO NOVO SERIALIZER
    STATUS_CORES,
    STATUS_LABELS,
)

from .pagination import (
    SKUPagination,
    CriticidadePagination,
    HistoricoUploadPagination,
)


# =============================================================================
# MIXINS E UTILITÁRIOS
# =============================================================================
class UnidadeAccessMixin:
    """
    Mixin para filtrar querysets por unidades que o usuário tem acesso.
    Implementa o padrão "Unidade Ativa" (Multi-tenant).
    """
    
    def get_user_unidades(self):
        """Retorna IDs das unidades que o usuário pode acessar."""
        user = self.request.user
        if user.is_superuser:
            return UnidadeNegocio.objects.filter(ativo=True).values_list('id', flat=True)
        return user.get_unidades_ids()
    
    def get_unidade_ativa(self):
        """
        Retorna o ID da unidade ativa baseado no parâmetro `unidade_id`.
        Valida se o usuário tem acesso à unidade solicitada.
        Retorna None se não tiver acesso ou se não foi fornecido.
        """
        unidade_id = self.request.query_params.get('unidade_id')
        if not unidade_id:
            return None
        
        try:
            unidade_id = int(unidade_id)
        except (ValueError, TypeError):
            return None
        
        # Superusuário tem acesso a todas as unidades
        if self.request.user.is_superuser:
            if UnidadeNegocio.objects.filter(id=unidade_id, ativo=True).exists():
                return unidade_id
            return None
        
        # Usuário comum: verifica se tem acesso
        unidades_permitidas = list(self.get_user_unidades())
        if unidade_id in unidades_permitidas:
            return unidade_id
        
        return None
    
    def is_vendedor_na_unidade_ativa(self):
        """
        Verifica se o usuário é VENDEDOR na unidade ativa.
        Superusuários nunca são considerados vendedores.
        """
        user = self.request.user
        if user.is_superuser:
            return False
        
        unidade_id = self.get_unidade_ativa()
        if unidade_id is None:
            return False
        
        return user.is_vendedor(unidade_id)
    
    def filter_by_unidade(self, queryset, unidade_field='unidade_negocio'):
        """Filtra queryset pelas unidades do usuário."""
        unidades_ids = self.get_user_unidades()
        filter_kwargs = {f'{unidade_field}__id__in': unidades_ids}
        return queryset.filter(**filter_kwargs)
    
    def filter_by_unidade_ativa(self, queryset, unidade_field='unidade_negocio'):
        """
        Filtra queryset pela unidade ativa.
        Se não houver unidade ativa válida, retorna queryset vazio.
        """
        unidade_id = self.get_unidade_ativa()
        if unidade_id is None:
            return queryset.none()
        
        filter_kwargs = {f'{unidade_field}_id': unidade_id}
        return queryset.filter(**filter_kwargs)


def get_client_ip(request):
    """Extrai IP do cliente da requisição."""
    x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
    if x_forwarded_for:
        return x_forwarded_for.split(',')[0]
    return request.META.get('REMOTE_ADDR')


def log_consulta(usuario, tipo, parametros, request):
    """Registra log de consulta para auditoria."""
    LogConsulta.objects.create(
        usuario=usuario,
        tipo_consulta=tipo,
        parametros=parametros,
        ip_address=get_client_ip(request)
    )


# =============================================================================
# AUTENTICAÇÃO
# =============================================================================
class LoginView(APIView):
    """
    POST /api/auth/login/
    
    Autentica usuário e retorna tokens JWT.
    """
    permission_classes = [AllowAny]
    
    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        
        username = serializer.validated_data['username']
        password = serializer.validated_data['password']
        
        user = authenticate(username=username, password=password)
        
        if user is None:
            return Response(
                {'detail': 'Credenciais inválidas.'},
                status=status.HTTP_401_UNAUTHORIZED
            )
        
        if not user.is_active:
            return Response(
                {'detail': 'Usuário inativo.'},
                status=status.HTTP_401_UNAUTHORIZED
            )
        
        # Gera tokens JWT
        refresh = RefreshToken.for_user(user)
        
        response_data = {
            'access': str(refresh.access_token),
            'refresh': str(refresh),
            'usuario': UsuarioSerializer(user).data
        }
        
        return Response(response_data, status=status.HTTP_200_OK)


class LogoutView(APIView):
    """
    POST /api/auth/logout/
    
    Invalida o refresh token (blacklist).
    """
    permission_classes = [IsAuthenticated]
    
    def post(self, request):
        try:
            refresh_token = request.data.get('refresh')
            if refresh_token:
                token = RefreshToken(refresh_token)
                token.blacklist()
            return Response(
                {'detail': 'Logout realizado com sucesso.'},
                status=status.HTTP_200_OK
            )
        except Exception:
            return Response(
                {'detail': 'Token inválido.'},
                status=status.HTTP_400_BAD_REQUEST
            )


class MeView(APIView):
    """
    GET /api/auth/me/
    
    Retorna dados do usuário autenticado.
    """
    permission_classes = [IsAuthenticated]
    
    def get(self, request):
        serializer = UsuarioSerializer(request.user)
        return Response(serializer.data)


# =============================================================================
# UNIDADE DE NEGÓCIO
# =============================================================================
class UnidadeNegocioViewSet(viewsets.ModelViewSet):
    """
    ViewSet para UnidadeNegocio.
    
    Usuários só veem unidades que têm acesso.
    Superusuários veem todas.
    """
    serializer_class = UnidadeNegocioSerializer
    permission_classes = [IsAuthenticated]
    filter_backends = [DjangoFilterBackend, filters.SearchFilter, filters.OrderingFilter]
    search_fields = ['codigo_unb', 'nome']
    ordering_fields = ['nome', 'codigo_unb', 'created_at']
    ordering = ['nome']
    
    def get_queryset(self):
        user = self.request.user
        queryset = UnidadeNegocio.objects.filter(ativo=True)
        
        if not user.is_superuser:
            unidades_ids = user.get_unidades_ids()
            queryset = queryset.filter(id__in=unidades_ids)
        
        return queryset
    
    @action(detail=False, methods=['get'])
    def resumo(self, request):
        """
        GET /api/unidades/resumo/
        
        Lista resumida para dropdowns.
        """
        queryset = self.get_queryset()
        serializer = UnidadeNegocioResumoSerializer(queryset, many=True)
        return Response(serializer.data)


# =============================================================================
# SKU - CONSULTA DE VALIDADE E BUSCA RÁPIDA
# =============================================================================
class SKUViewSet(UnidadeAccessMixin, viewsets.ModelViewSet):
    """
    ViewSet para SKU com busca avançada.
    """
    permission_classes = [IsAuthenticated, CanReadSKU]
    pagination_class = SKUPagination
    filter_backends = [DjangoFilterBackend, filters.OrderingFilter]
    filterset_fields = ['unidade_negocio', 'categoria', 'ativo']
    ordering_fields = ['nome_produto', 'codigo_sku', 'created_at']
    ordering = ['nome_produto']
    
    def get_serializer_class(self):
        if self.action == 'list':
            return SKUListSerializer
        return SKUSerializer
    
    def get_queryset(self):
        queryset = SKU.objects.filter(ativo=True).select_related(
            'unidade_negocio'
        )
        
        queryset = self.filter_by_unidade_ativa(queryset)
        
        search = self.request.query_params.get('search', None)
        if search:
            queryset = queryset.filter(
                Q(codigo_sku__icontains=search) |
                Q(nome_produto__icontains=search)
            )
        
        return queryset.distinct()
    
    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        
        log_consulta(
            usuario=request.user,
            tipo='VALIDADE',
            parametros={'sku_id': instance.id, 'codigo_sku': instance.codigo_sku},
            request=request
        )
        
        serializer = self.get_serializer(instance)
        return Response(serializer.data)
    
    @action(detail=False, methods=['get'])
    def consulta_validade(self, request):
        search = request.query_params.get('search', None)
        
        if not self.get_unidade_ativa():
            return Response(
                {'detail': 'Parâmetro "unidade_id" é obrigatório e deve ser uma unidade válida.'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        if not search:
            return Response(
                {'detail': 'Parâmetro "search" é obrigatório.'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        queryset = self.get_queryset()
        
        log_consulta(
            usuario=request.user,
            tipo='VALIDADE',
            parametros={'search': search, 'unidade_id': self.get_unidade_ativa()},
            request=request
        )
        
        serializer = SKUSerializer(
            queryset,
            many=True,
            context={'request': request}
        )
        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    def buscar_por_codigo(self, request):
        """
        GET /api/skus/buscar_por_codigo/?codigo=xxx&unidade_id=1
        Endpoint rápido para preencher o formulário do Controle.
        """
        codigo = request.query_params.get('codigo')
        unidade_id = self.get_unidade_ativa()

        if not codigo or not unidade_id:
            return Response({'error': 'Parâmetros "codigo" e "unidade_id" são obrigatórios.'}, status=status.HTTP_400_BAD_REQUEST)

        sku = SKU.objects.filter(codigo_sku=codigo, unidade_negocio_id=unidade_id, ativo=True).first()
        if not sku:
            return Response({'error': 'Produto não encontrado no estoque desta unidade.'}, status=status.HTTP_404_NOT_FOUND)

        return Response({
            'id': sku.id,
            'nome_produto': sku.nome_produto,
            'categoria': sku.categoria,
            'qtd_estoque_atual': sku.qtd_disponivel_venda
        })

    @action(detail=False, methods=['post'], permission_classes=[IsAuthenticated, IsAdmin])
    def limpar_banco(self, request):
        confirmacao = request.data.get('confirmacao', '')
        if confirmacao != 'CONFIRMAR EXCLUSAO':
            return Response(
                {
                    'detail': 'Confirmação inválida. Envie {"confirmacao": "CONFIRMAR EXCLUSAO"} no body.',
                    'error': 'confirmation_required'
                },
                status=status.HTTP_400_BAD_REQUEST
            )
        
        total_skus = SKU.objects.count()
        SKU.objects.all().delete()
        
        log_consulta(
            usuario=request.user,
            tipo='ADMIN_LIMPAR_BANCO',
            parametros={
                'skus_deletados': total_skus,
                'ip': request.META.get('REMOTE_ADDR'),
            },
            request=request
        )
        
        return Response({
            'success': True,
            'message': 'Banco de dados limpo com sucesso.',
            'skus_deletados': total_skus,
        })


# =============================================================================
# LANÇAMENTOS MANUAIS (CONTROLE)
# =============================================================================
class LancamentoCriticoManualViewSet(UnidadeAccessMixin, viewsets.ModelViewSet):
    """
    ViewSet para a equipe de Controle lançar manualmente itens críticos.
    """
    serializer_class = LancamentoCriticoManualSerializer
    permission_classes = [IsAuthenticated, IsControle]

    def get_queryset(self):
        queryset = LancamentoCriticoManual.objects.filter(ativo=True)
        return self.filter_by_unidade_ativa(queryset).select_related('sku')

    def perform_create(self, serializer):
        serializer.save(usuario_lancamento=self.request.user)


# =============================================================================
# RELATÓRIO DE CRITICIDADE (LIDO EXCLUSIVAMENTE DOS LANÇAMENTOS MANUAIS)
# =============================================================================
class RelatorioCriticidadeView(UnidadeAccessMixin, APIView):
    """
    GET /api/relatorio-criticidade/?unidade_id=1
    
    Retorna JSON formatado lendo APENAS a tabela `LancamentoCriticoManual`.
    Calcula o status de forma dinâmica baseando-se na data_validade do calendário.
    """
    permission_classes = [IsAuthenticated]
    
    def get(self, request):
        unidade_id = self.get_unidade_ativa()
        if not unidade_id:
            return Response(
                {'detail': 'Parâmetro unidade_id é obrigatório e deve ser uma unidade válida que você tenha acesso.'},
                status=status.HTTP_400_BAD_REQUEST
            )

        user = request.user
        is_vendedor = False
        if not user.is_superuser:
            is_vendedor = user.is_vendedor(unidade_id)

        # 1. BUSCA AS CONFIGURAÇÕES DE DIAS DA FILIAL (Para saber as réguas de corte)
        try:
            unidade = UnidadeNegocio.objects.get(id=unidade_id, ativo=True)
            config = getattr(unidade, 'configuracao_alerta', None)
        except UnidadeNegocio.DoesNotExist:
            config = None

        if not config:
            config = ConfiguracaoAlerta.objects.filter(unidade__isnull=True, ativo=True).first()
        
        # Réguas de corte configuradas pelo Controle
        dias_bloqueado = config.dias_bloqueado if config else 30

        # Busca lançamentos do Controle para esta unidade
        lancamentos = LancamentoCriticoManual.objects.filter(
            unidade_negocio_id=unidade_id,
            ativo=True
        ).select_related('sku')

        bloqueados_list = []
        risco_vencimento_list = []
        pre_bloqueio_list = []

        hoje = date.today()

        # 2. AQUI ACONTECE A MÁGICA MATEMÁTICA DAS DATAS
        for item in lancamentos:
            # Calcula a diferença exata de dias entre a validade e o dia de hoje
            dias_restantes = (item.data_validade - hoje).days
            
            # Classificação dinâmica baseada no passar dos dias
            if dias_restantes <= 0:
                status_texto = 'Bloqueado'
                status_color = '#000000'  # Preto (Vencido)
                categoria_destino = 'BLOQUEADO'
            elif dias_restantes <= dias_bloqueado:
                status_texto = 'Risco de Vencimento'
                status_color = '#F44336'  # Vermelho (Crítico)
                categoria_destino = 'RISCO_VENCIMENTO'
            else:
                status_texto = 'Pré-Bloqueio'
                status_color = '#FFC107'  # Amarelo (Alerta)
                categoria_destino = 'PRE_BLOQUEIO'

            # Monta a estrutura que o Flutter já espera receber
            sku_data = {
                'id': item.sku.id,
                'lancamento_manual_id': item.id,  # Permite que o Flutter delete o lançamento direto por arrasto
                'codigo_sku': item.sku.codigo_sku,
                'nome_produto': item.sku.nome_produto,
                'categoria': item.sku.categoria,
                'qtd_disponivel_venda': f"{item.quantidade_critica} cx",  # Exibe apenas a quantidade retida
                'status_texto': status_texto,
                'status_color': status_color,
                'status_dias_restantes': dias_restantes if dias_restantes > 0 else None
            }

            # Envia o item para a pasta correta baseando-se no cálculo dinâmico acima
            if categoria_destino == 'BLOQUEADO':
                # Vendedor NUNCA vê os bloqueados (pretos)
                if not is_vendedor:
                    bloqueados_list.append(sku_data)
            elif categoria_destino == 'RISCO_VENCIMENTO':
                risco_vencimento_list.append(sku_data)
            elif categoria_destino == 'PRE_BLOQUEIO':
                pre_bloqueio_list.append(sku_data)

        # Log para auditoria
        log_consulta(
            usuario=request.user,
            tipo='CRITICIDADE_MANUAL',
            parametros={'unidade_id': unidade_id},
            request=request
        )

        return Response({
            'resumo': {
                'total_bloqueados': len(bloqueados_list),
                'total_pre_bloqueio': len(pre_bloqueio_list),
            },
            'bloqueados': bloqueados_list,
            'risco_vencimento': risco_vencimento_list,
            'pre_bloqueio': pre_bloqueio_list,
        })


# =============================================================================
# ESTOQUE INICIAL
# =============================================================================
class EstoqueViewSet(UnidadeAccessMixin, viewsets.ReadOnlyModelViewSet):
    """
    ViewSet para Estoque Inicial (somente leitura).
    """
    serializer_class = SKUEstoqueSerializer
    permission_classes = [IsAuthenticated]
    filter_backends = [DjangoFilterBackend, filters.OrderingFilter]
    filterset_fields = ['unidade_negocio', 'categoria']
    ordering_fields = ['nome_produto', 'codigo_sku']
    ordering = ['nome_produto']
    
    def get_queryset(self):
        queryset = SKU.objects.filter(ativo=True).select_related(
            'unidade_negocio'
        ).prefetch_related(
            Prefetch(
                'movimentacoes',
                queryset=MovimentacaoEstoque.objects.filter(
                    ativo=True,
                    tipo='ENTRADA',
                    status='EM_TRANSITO'
                )
            )
        )
        
        queryset = self.filter_by_unidade_ativa(queryset)
        
        search = self.request.query_params.get('search', None)
        if search:
            queryset = queryset.filter(
                Q(codigo_sku__icontains=search) |
                Q(nome_produto__icontains=search)
            )
        
        return queryset.distinct()
    
    def list(self, request, *args, **kwargs):
        response = super().list(request, *args, **kwargs)
        
        log_consulta(
            usuario=request.user,
            tipo='ESTOQUE',
            parametros={
                'search': request.query_params.get('search'),
                'unidade_id': request.query_params.get('unidade_id'),
            },
            request=request
        )
        
        return response
    
    @action(detail=False, methods=['get'])
    def resumo_geral(self, request):
        queryset = self.get_queryset()
        
        total_skus = queryset.count()
        total_estoque = 0
        total_transito = 0
        skus_sem_estoque = 0
        
        for sku in queryset:
            qtd_estoque = sku.quantidade_total_estoque
            qtd_transito = sku.quantidade_em_transito
            
            total_estoque += qtd_estoque
            total_transito += qtd_transito
            
            if qtd_estoque == 0:
                skus_sem_estoque += 1
        
        return Response({
            'total_skus': total_skus,
            'total_estoque': total_estoque,
            'total_transito': total_transito,
            'total_geral': total_estoque + total_transito,
            'skus_sem_estoque': skus_sem_estoque,
        })


# =============================================================================
# CONFIGURAÇÃO DE ALERTA
# =============================================================================
class ConfiguracaoAlertaViewSet(viewsets.ModelViewSet):
    """
    ViewSet para ConfiguracaoAlerta.
    """
    queryset = ConfiguracaoAlerta.objects.filter(ativo=True)
    serializer_class = ConfiguracaoAlertaSerializer
    permission_classes = [IsAuthenticated, CanManageSettings]
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ['unidade']


# =============================================================================
# MOVIMENTAÇÃO DE ESTOQUE
# =============================================================================
class MovimentacaoEstoqueViewSet(UnidadeAccessMixin, viewsets.ModelViewSet):
    """
    ViewSet para MovimentacaoEstoque.
    """
    serializer_class = MovimentacaoEstoqueSerializer
    permission_classes = [IsAuthenticated, CanReadSKU]
    filter_backends = [DjangoFilterBackend, filters.OrderingFilter]
    filterset_fields = ['tipo', 'status', 'sku']
    ordering_fields = ['created_at', 'data_prevista']
    ordering = ['-created_at']
    
    def get_queryset(self):
        queryset = MovimentacaoEstoque.objects.filter(ativo=True).select_related(
            'sku',
            'unidade_origem',
            'unidade_destino',
            'usuario'
        )
        
        unidades_ids = self.get_user_unidades()
        queryset = queryset.filter(
            Q(unidade_origem_id__in=unidades_ids) |
            Q(unidade_destino_id__in=unidades_ids) |
            Q(sku__unidade_negocio_id__in=unidades_ids)
        )
        
        return queryset.distinct()
    
    def perform_create(self, serializer):
        serializer.save(usuario=self.request.user)


# =============================================================================
# GESTÃO DE USUÁRIOS
# =============================================================================
class UsuarioViewSet(viewsets.ModelViewSet):
    """
    ViewSet para gestão de Usuários.
    """
    serializer_class = UsuarioSerializer
    permission_classes = [IsAuthenticated, IsGerenteOuDiretoria]
    filter_backends = [DjangoFilterBackend, filters.SearchFilter, filters.OrderingFilter]
    search_fields = ['first_name', 'last_name', 'email', 'username']
    ordering_fields = ['first_name', 'last_name', 'email', 'created_at']
    ordering = ['first_name', 'last_name']
    
    def get_queryset(self):
        user = self.request.user
        
        if user.is_superuser or user.is_diretoria():
            queryset = Usuario.objects.filter(is_active=True)
        else:
            unidades_ids = user.get_unidades_ids()
            queryset = Usuario.objects.filter(
                is_active=True,
                unidades__id__in=unidades_ids
            ).distinct()
        
        unidade_id = self.request.query_params.get('unidade_id')
        if unidade_id:
            queryset = queryset.filter(unidades__id=unidade_id)
        
        return queryset.prefetch_related('unidades')
    
    def get_serializer_class(self):
        if self.action == 'create':
            return UsuarioCreateSerializer
        return UsuarioSerializer
    
    @action(detail=True, methods=['post'])
    def vincular_unidade(self, request, pk=None):
        usuario = self.get_object()
        unidade_id = request.data.get('unidade_id')
        papel = request.data.get('papel', 'VENDEDOR')
        
        if not unidade_id:
            return Response({'error': 'unidade_id é obrigatório'}, status=status.HTTP_400_BAD_REQUEST)
        
        if papel not in ['VENDEDOR', 'GERENTE', 'DIRETORIA', 'CONTROLE']:
            return Response(
                {'error': 'Papel inválido. Use: VENDEDOR, GERENTE, DIRETORIA ou CONTROLE'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        if papel == 'DIRETORIA' and not request.user.is_diretoria():
            return Response(
                {'error': 'Apenas diretoria pode criar usuários DIRETORIA'},
                status=status.HTTP_403_FORBIDDEN
            )
        
        try:
            unidade = UnidadeNegocio.objects.get(id=unidade_id, ativo=True)
            
            if not request.user.is_superuser and not request.user.is_diretoria():
                if not request.user.tem_acesso_unidade(unidade.id):
                    return Response(
                        {'error': 'Você não tem acesso a esta unidade'},
                        status=status.HTTP_403_FORBIDDEN
                    )
            
            vinculo, created = UsuarioUnidade.objects.update_or_create(
                usuario=usuario,
                unidade=unidade,
                defaults={'papel': papel}
            )
            
            return Response({
                'success': True,
                'message': f'Usuário vinculado como {papel}',
                'created': created
            })
            
        except UnidadeNegocio.DoesNotExist:
            return Response({'error': 'Unidade não encontrada'}, status=status.HTTP_404_NOT_FOUND)
    
    @action(detail=True, methods=['post'])
    def desvincular_unidade(self, request, pk=None):
        usuario = self.get_object()
        unidade_id = request.data.get('unidade_id')
        
        if not unidade_id:
            return Response({'error': 'unidade_id é obrigatório'}, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            vinculo = UsuarioUnidade.objects.get(
                usuario=usuario,
                unidade_id=unidade_id
            )
            
            if not request.user.is_superuser and not request.user.is_diretoria():
                if not request.user.tem_acesso_unidade(int(unidade_id)):
                    return Response(
                        {'error': 'Você não tem acesso a esta unidade'},
                        status=status.HTTP_403_FORBIDDEN
                    )
            
            vinculo.delete()
            return Response({'success': True, 'message': 'Vínculo removido com sucesso'})
            
        except UsuarioUnidade.DoesNotExist:
            return Response({'error': 'Vínculo não encontrado'}, status=status.HTTP_404_NOT_FOUND)


# =============================================================================
# LOG DE CONSULTAS (somente leitura)
# =============================================================================
class LogConsultaViewSet(viewsets.ReadOnlyModelViewSet):
    """
    ViewSet para LogConsulta (somente leitura).
    """
    queryset = LogConsulta.objects.all().select_related('usuario')
    serializer_class = LogConsultaSerializer
    permission_classes = [IsAuthenticated]
    filter_backends = [DjangoFilterBackend, filters.OrderingFilter]
    filterset_fields = ['tipo_consulta', 'usuario']
    ordering = ['-created_at']
    
    def get_queryset(self):
        if not self.request.user.is_superuser:
            return LogConsulta.objects.filter(usuario=self.request.user)
        return super().get_queryset()


# =============================================================================
# UPLOAD DE ARQUIVOS - ESTOQUE FEFO
# =============================================================================
ALLOWED_UPLOAD_EXTENSIONS = {'.xlsx', '.xls', '.csv'}

def _validar_extensao_arquivo(file, field_name: str) -> str | None:
    ext = '.' + file.name.rsplit('.', 1)[-1].lower() if '.' in file.name else ''
    if ext not in ALLOWED_UPLOAD_EXTENSIONS:
        allowed = ', '.join(sorted(ALLOWED_UPLOAD_EXTENSIONS))
        return f'"{field_name}": formato "{ext or "sem extensão"}" não permitido. Use: {allowed}.'
    return None

class UploadEstoqueView(APIView):
    """
    POST /api/upload/grade-020502/
    """
    permission_classes = [IsAuthenticated, CanManageUpload]

    def post(self, request):
        from .upload_service import UploadFefoService

        file_020502 = request.FILES.get('file_020502')
        file_020304 = request.FILES.get('file_020304')
        file_nri    = request.FILES.get('file_nri')
        unidade_negocio_id = request.data.get('unidade_negocio_id')

        erros_presenca = {}
        if not file_020502:
            erros_presenca['file_020502'] = 'Arquivo obrigatório não enviado.'
        if not file_020304:
            erros_presenca['file_020304'] = 'Arquivo obrigatório não enviado.'
        if not file_nri:
            erros_presenca['file_nri'] = 'Arquivo obrigatório não enviado.'
        if not unidade_negocio_id:
            erros_presenca['unidade_negocio_id'] = 'Campo obrigatório não informado.'

        if erros_presenca:
            return Response({'errors': erros_presenca}, status=status.HTTP_400_BAD_REQUEST)

        erros_extensao = {}
        for field, file in [
            ('file_020502', file_020502),
            ('file_020304', file_020304),
            ('file_nri',    file_nri),
        ]:
            erro = _validar_extensao_arquivo(file, field)
            if erro:
                erros_extensao[field] = erro

        if erros_extensao:
            return Response({'errors': erros_extensao}, status=status.HTTP_400_BAD_REQUEST)

        user = request.user
        try:
            unidade_negocio_id_int = int(unidade_negocio_id)
        except (ValueError, TypeError):
            return Response(
                {'errors': {'unidade_negocio_id': 'Valor inválido; esperado um inteiro.'}},
                status=status.HTTP_400_BAD_REQUEST
            )

        if not user.is_superuser:
            if not user.tem_acesso_unidade(unidade_negocio_id_int):
                return Response({'error': 'Sem permissão para esta unidade.'}, status=status.HTTP_403_FORBIDDEN)

        nome_arquivos = ' | '.join([file_020502.name, file_020304.name, file_nri.name])

        try:
            unidade = UnidadeNegocio.objects.get(id=unidade_negocio_id_int)
            result = UploadFefoService.processar_estoque_fefo(
                file_020502=file_020502,
                file_020304=file_020304,
                file_nri=file_nri,
                unidade_negocio_id=unidade_negocio_id_int,
            )

            skus_atualizados = result.get('skus_atualizados', 0)

            HistoricoUpload.objects.create(
                tipo_arquivo='FEFO',
                usuario=user,
                unidade_negocio=unidade,
                status='SUCESSO' if result.get('success') else 'ERRO',
                linhas_processadas=skus_atualizados,
                nome_arquivo=nome_arquivos,
                mensagem_erro=result.get('error') if not result.get('success') else None,
            )

            if result.get('success'):
                return Response(result, status=status.HTTP_200_OK)
            else:
                return Response(result, status=status.HTTP_400_BAD_REQUEST)

        except UnidadeNegocio.DoesNotExist:
            return Response({'error': 'Unidade de negócio não encontrada.'}, status=status.HTTP_404_NOT_FOUND)
        except Exception as e:
            try:
                unidade = UnidadeNegocio.objects.get(id=unidade_negocio_id_int)
                HistoricoUpload.objects.create(
                    tipo_arquivo='FEFO',
                    usuario=user,
                    unidade_negocio=unidade,
                    status='ERRO',
                    linhas_processadas=0,
                    nome_arquivo=nome_arquivos,
                    mensagem_erro=str(e),
                )
            except Exception:
                pass

            return Response({'error': f'Erro ao processar arquivos: {str(e)}'}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# =============================================================================
# HISTÓRICO DE UPLOAD
# =============================================================================
class HistoricoUploadViewSet(UnidadeAccessMixin, viewsets.ReadOnlyModelViewSet):
    """
    ViewSet somente leitura para HistoricoUpload.
    """
    serializer_class = HistoricoUploadSerializer
    permission_classes = [IsAuthenticated]
    pagination_class = HistoricoUploadPagination
    filter_backends = [DjangoFilterBackend, filters.OrderingFilter]
    filterset_fields = ['tipo_arquivo', 'status', 'unidade_negocio']
    ordering_fields = ['created_at']
    ordering = ['-created_at']
    
    def get_queryset(self):
        queryset = HistoricoUpload.objects.filter(ativo=True).select_related('usuario', 'unidade_negocio')
        
        unidade_id = self.get_unidade_ativa()
        if unidade_id:
            queryset = queryset.filter(unidade_negocio_id=unidade_id)
        else:
            unidades_ids = self.get_user_unidades()
            queryset = queryset.filter(unidade_negocio_id__in=unidades_ids)
        
        return queryset
    
    @action(detail=False, methods=['get'])
    def ultimo(self, request):
        unidade_id = self.get_unidade_ativa()
        if unidade_id is None:
            return Response({'error': 'Parâmetro unidade_id é obrigatório'}, status=status.HTTP_400_BAD_REQUEST)
        
        ultimo_upload = HistoricoUpload.objects.filter(
            ativo=True,
            unidade_negocio_id=unidade_id,
            status='SUCESSO'
        ).order_by('-created_at').first()
        
        if ultimo_upload:
            return Response({
                'data_upload': ultimo_upload.created_at,
                'tipo_arquivo': ultimo_upload.tipo_arquivo,
                'tipo_arquivo_display': ultimo_upload.get_tipo_arquivo_display(),
            })
        else:
            return Response({
                'data_upload': None,
                'tipo_arquivo': None,
                'tipo_arquivo_display': None,
            })


# =============================================================================
# NOTIFICAÇÕES DE ALERTA DE VALIDADE
# =============================================================================
class NotificacoesAlertaView(UnidadeAccessMixin, APIView):
    """
    GET /api/notificacoes/
    """
    permission_classes = [IsAuthenticated]
    
    def get(self, request):
        unidade_id = self.get_unidade_ativa()
        if unidade_id is None:
            return Response({'error': 'Parâmetro unidade_id é obrigatório e deve ser uma unidade válida'}, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            unidade = UnidadeNegocio.objects.get(id=unidade_id, ativo=True)
        except UnidadeNegocio.DoesNotExist:
            return Response({'error': 'Unidade não encontrada'}, status=status.HTTP_404_NOT_FOUND)
        
        config = getattr(unidade, 'configuracao_alerta', None)
        if config is None:
            config = ConfiguracaoAlerta.objects.filter(unidade__isnull=True, ativo=True).first()
        
        dias_pre_bloqueio = config.dias_pre_bloqueio if config else 60
        dias_bloqueado = config.dias_bloqueado if config else 30
        dias_extremamente_critico = config.dias_extremamente_critico if config else 7
        
        hoje = date.today()
        from datetime import timedelta
        data_limite_pre_bloqueio = hoje + timedelta(days=dias_pre_bloqueio)
        
        skus_alerta = SKU.objects.filter(
            ativo=True,
            qtd_disponivel_venda__gt=0,
            unidade_negocio_id=unidade_id,
            validade_inicio_range__isnull=False,
            validade_inicio_range__gte=hoje,
            validade_inicio_range__lte=data_limite_pre_bloqueio,
        ).select_related('unidade_negocio').order_by('validade_inicio_range')
        
        notificacoes = []
        for sku in skus_alerta:
            dias_restantes = (sku.validade_inicio_range - hoje).days
            
            if dias_restantes <= dias_extremamente_critico:
                status_val = 'EXTREMAMENTE_CRITICO'
            elif dias_restantes <= dias_bloqueado:
                status_val = 'BLOQUEADO'
            else:
                status_val = 'PRE_BLOQUEIO'
            
            notificacoes.append({
                'sku_id': sku.id,
                'sku_codigo': sku.codigo_sku,
                'sku_nome': sku.nome_produto,
                'data_validade': sku.validade_inicio_range,
                'dias_restantes': dias_restantes,
                'qtd_estoque': sku.qtd_disponivel_venda,
                'status': status_val,
                'status_label': STATUS_LABELS.get(status_val, 'Indefinido'),
                'status_cor': STATUS_CORES.get(status_val, '#9E9E9E'),
                'unidade_id': unidade.id,
                'unidade_codigo': unidade.codigo_unb,
                'unidade_nome': unidade.nome,
            })
        
        resumo = {
            'extremamente_critico': sum(1 for n in notificacoes if n['status'] == 'EXTREMAMENTE_CRITICO'),
            'bloqueado': sum(1 for n in notificacoes if n['status'] == 'BLOQUEADO'),
            'pre_bloqueio': sum(1 for n in notificacoes if n['status'] == 'PRE_BLOQUEIO'),
            'total': len(notificacoes),
        }
        
        return Response({
            'resumo': resumo,
            'notificacoes': NotificacaoAlertaSerializer(notificacoes, many=True).data,
        })


# =============================================================================
# MENUS DINÂMICOS (CONTROLE DE ACESSO)
# =============================================================================
class MeusMenusView(APIView):
    """
    GET /api/menus/meus-menus/?unidade_id=X
    """
    permission_classes = [IsAuthenticated]

    def get(self, request, *args, **kwargs):
        unidade_id = request.query_params.get('unidade_id')
        if not unidade_id:
            return Response({'error': 'Parâmetro unidade_id é obrigatório.'}, status=status.HTTP_400_BAD_REQUEST)
            
        try:
            unidade_id = int(unidade_id)
        except ValueError:
            return Response({'error': 'unidade_id inválido.'}, status=status.HTTP_400_BAD_REQUEST)
            
        usuario = request.user
        papel = usuario.get_papel_unidade(unidade_id)
        
        if usuario.is_superuser:
            modulos = ModuloMenu.objects.filter(globalmente_ativo=True)
        else:
            if not papel:
                return Response([]) 
                
            modulos_permitidos_ids = PermissaoMenu.objects.filter(
                papel=papel,
                visivel=True,
                modulo__globalmente_ativo=True
            ).values_list('modulo_id', flat=True)
            
            modulos = ModuloMenu.objects.filter(id__in=modulos_permitidos_ids)
            
        serializer = MenuDinamicoSerializer(modulos, many=True)
        return Response(serializer.data)