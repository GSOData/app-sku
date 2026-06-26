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
# SKU - CONSULTA DE VALIDADE
# =============================================================================
class SKUViewSet(UnidadeAccessMixin, viewsets.ModelViewSet):
    """
    ViewSet para SKU com busca avançada.
    
    Implementa:
    - Busca por codigo_sku OU nome_produto (parâmetro 'search')
    - Filtro por unidade_negocio
    - Filtro por categoria
    - Campos calculados de status
    - Paginação de 20 itens por página
    - Oculta vencidos para VENDEDOR
    
    Permissões RBAC:
    - VENDEDOR: somente leitura (não vê itens vencidos)
    - GERENTE: CRUD completo
    - DIRETORIA: leitura consolidada
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
        
        # Filtra pela unidade ativa (obrigatório)
        queryset = self.filter_by_unidade_ativa(queryset)
        
        # Busca por codigo_sku OU nome_produto
        search = self.request.query_params.get('search', None)
        if search:
            queryset = queryset.filter(
                Q(codigo_sku__icontains=search) |
                Q(nome_produto__icontains=search)
            )
        
        return queryset.distinct()
    
    def retrieve(self, request, *args, **kwargs):
        """Override para logar consulta de validade."""
        instance = self.get_object()
        
        # Log de consulta
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
        """
        GET /api/skus/consulta_validade/?search=xxx&unidade_id=1
        
        Endpoint específico para a Tela de Consulta de Validade.
        Busca por código SKU ou nome do produto.
        
        Parâmetros:
        - search: Termo de busca (codigo_sku ou nome_produto)
        - unidade_id: ID da unidade (OBRIGATÓRIO)
        
        Retorna lista com status calculado.
        """
        search = request.query_params.get('search', None)
        
        # Valida unidade ativa
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
        
        # get_queryset já aplica o filtro de unidade ativa e o filtro de search
        queryset = self.get_queryset()
        
        # Log de consulta
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

    @action(detail=False, methods=['post'], permission_classes=[IsAuthenticated, IsAdmin])
    def limpar_banco(self, request):
        """
        POST /api/skus/limpar_banco/
        
        PERIGO: Remove TODOS os SKUs do sistema.
        Apenas usuários ADMIN podem executar.
        
        Body (opcional):
        {
            "confirmacao": "CONFIRMAR EXCLUSAO"
        }
        """
        # Exige confirmação explícita
        confirmacao = request.data.get('confirmacao', '')
        if confirmacao != 'CONFIRMAR EXCLUSAO':
            return Response(
                {
                    'detail': 'Confirmação inválida. Envie {"confirmacao": "CONFIRMAR EXCLUSAO"} no body.',
                    'error': 'confirmation_required'
                },
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Contagem antes da exclusão
        total_skus = SKU.objects.count()
        
        # Deleta todos os SKUs
        SKU.objects.all().delete()
        
        # Log da operação
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
# RELATÓRIO DE CRITICIDADE
# =============================================================================
class RelatorioCriticidadeView(UnidadeAccessMixin, APIView):
    """
    GET /api/relatorio-criticidade/?unidade_id=1
    
    Endpoint específico para a Tela de Itens em Criticidade.
    
    Retorna JSON separado:
    {
        'bloqueados': [...],   # Extremamente Crítico + Bloqueado (+ Vencidos para não-vendedores)
        'pre_bloqueio': [...]  # Pré-bloqueio
    }
    
    RBAC:
    - VENDEDOR: NÃO vê SKUs com status VENCIDO
    - GERENTE/DIRETORIA: Vê todos os status incluindo VENCIDO
    """
    permission_classes = [IsAuthenticated]
    
    def get(self, request):
        unidade_id = request.query_params.get('unidade_id', None)
        codigo_unb = request.query_params.get('codigo_unb', None)
        
        # Busca unidade por ID ou código
        unidade = None
        if unidade_id:
            try:
                unidade = UnidadeNegocio.objects.get(id=unidade_id, ativo=True)
            except UnidadeNegocio.DoesNotExist:
                return Response(
                    {'detail': 'Unidade não encontrada.'},
                    status=status.HTTP_404_NOT_FOUND
                )
        elif codigo_unb:
            try:
                unidade = UnidadeNegocio.objects.get(codigo_unb=codigo_unb, ativo=True)
            except UnidadeNegocio.DoesNotExist:
                return Response(
                    {'detail': 'Unidade não encontrada.'},
                    status=status.HTTP_404_NOT_FOUND
                )
        
        # Verifica permissão do usuário
        if unidade and not request.user.is_superuser:
            if not request.user.tem_acesso_unidade(unidade.id):
                return Response(
                    {'detail': 'Sem permissão para esta unidade.'},
                    status=status.HTTP_403_FORBIDDEN
                )
        
        # Busca configuração de alerta
        config = None
        if unidade:
            config = getattr(unidade, 'configuracao_alerta', None)
        if not config:
            config = ConfiguracaoAlerta.objects.filter(
                unidade__isnull=True,
                ativo=True
            ).first()
        
        dias_pre_bloqueio = config.dias_pre_bloqueio if config else 60
        dias_bloqueado = config.dias_bloqueado if config else 30
        dias_extremamente_critico = config.dias_extremamente_critico if config else 7
        
        # Verifica se o usuário é vendedor na unidade
        is_vendedor = False
        if unidade and not request.user.is_superuser:
            is_vendedor = request.user.is_vendedor(unidade.id)
        
        # Monta queryset base de SKUs com estoque disponível
        queryset = SKU.objects.filter(
            ativo=True,
            qtd_disponivel_venda__gt=0,
        ).select_related('unidade_negocio')
        
        if unidade:
            queryset = queryset.filter(unidade_negocio=unidade)
        else:
            unidades_ids = request.user.get_unidades_ids()
            queryset = queryset.filter(unidade_negocio_id__in=unidades_ids)
        
        # Classifica SKUs por status
        bloqueados = []   # VENCIDO + EXTREMAMENTE_CRITICO + BLOQUEADO
        pre_bloqueio = []
        
        for sku in queryset:
            status_info = sku.get_status(config)
            status_code = status_info.get('status')
            
            # Vendedor não vê SKUs com status VENCIDO
            if is_vendedor and status_code == 'VENCIDO':
                continue
            
            if status_code in ('VENCIDO', 'EXTREMAMENTE_CRITICO', 'BLOQUEADO'):
                bloqueados.append(sku)
            elif status_code == 'PRE_BLOQUEIO':
                pre_bloqueio.append(sku)
        
        # Log de consulta
        log_consulta(
            usuario=request.user,
            tipo='CRITICIDADE',
            parametros={
                'unidade_id': unidade.id if unidade else None,
                'codigo_unb': codigo_unb,
            },
            request=request
        )
        
        # Serializa
        bloqueados_data = SKUCriticidadeSerializer(
            bloqueados,
            many=True,
            context={'request': request}
        ).data
        
        pre_bloqueio_data = SKUCriticidadeSerializer(
            pre_bloqueio,
            many=True,
            context={'request': request}
        ).data
        
        return Response({
            'unidade': UnidadeNegocioResumoSerializer(unidade).data if unidade else None,
            'config': {
                'dias_pre_bloqueio': dias_pre_bloqueio,
                'dias_bloqueado': dias_bloqueado,
                'dias_extremamente_critico': dias_extremamente_critico,
            },
            'resumo': {
                'total_bloqueados': len(bloqueados),
                'total_pre_bloqueio': len(pre_bloqueio),
            },
            'bloqueados': bloqueados_data,
            'pre_bloqueio': pre_bloqueio_data,
        })


# =============================================================================
# ESTOQUE INICIAL
# =============================================================================
class EstoqueViewSet(UnidadeAccessMixin, viewsets.ReadOnlyModelViewSet):
    """
    ViewSet para Estoque Inicial (somente leitura).
    
    GET /api/estoque/
    GET /api/estoque/{id}/
    
    Retorna SKUs com:
    - Quantidade total em estoque
    - Quantidade em trânsito
    - Quantidade total (estoque + trânsito)
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
        
        # Filtra pela unidade ativa (obrigatório)
        queryset = self.filter_by_unidade_ativa(queryset)
        
        # Busca por codigo_sku ou nome
        search = self.request.query_params.get('search', None)
        if search:
            queryset = queryset.filter(
                Q(codigo_sku__icontains=search) |
                Q(nome_produto__icontains=search)
            )
        
        return queryset.distinct()
    
    def list(self, request, *args, **kwargs):
        """Override para logar consulta de estoque."""
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
        """
        GET /api/estoque/resumo_geral/
        
        Retorna totalizadores do estoque.
        """
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
    
    Permissões RBAC:
    - Apenas GERENTE e DIRETORIA podem gerenciar configurações
    """
    queryset = ConfiguracaoAlerta.objects.filter(ativo=True)
    serializer_class = ConfiguracaoAlertaSerializer
    permission_classes = [IsAuthenticated, IsGerenteOuDiretoria]
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ['unidade']


# =============================================================================
# MOVIMENTAÇÃO DE ESTOQUE
# =============================================================================
class MovimentacaoEstoqueViewSet(UnidadeAccessMixin, viewsets.ModelViewSet):
    """
    ViewSet para MovimentacaoEstoque.
    
    Permissões RBAC:
    - VENDEDOR: somente leitura
    - GERENTE: CRUD completo
    - DIRETORIA: leitura consolidada
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
        
        # Filtra por unidades do usuário
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
    
    Permissões RBAC:
    - GERENTE: pode gerenciar usuários da sua unidade
    - DIRETORIA: pode gerenciar usuários de todas as unidades
    - VENDEDOR: não tem acesso
    """
    serializer_class = UsuarioSerializer
    permission_classes = [IsAuthenticated, IsGerenteOuDiretoria]
    filter_backends = [DjangoFilterBackend, filters.SearchFilter, filters.OrderingFilter]
    search_fields = ['first_name', 'last_name', 'email', 'username']
    ordering_fields = ['first_name', 'last_name', 'email', 'created_at']
    ordering = ['first_name', 'last_name']
    
    def get_queryset(self):
        """
        Filtra usuários conforme papel do usuário autenticado:
        - DIRETORIA/Superuser: vê todos os usuários
        - GERENTE: vê apenas usuários das suas unidades
        """
        user = self.request.user
        
        if user.is_superuser or user.is_diretoria():
            queryset = Usuario.objects.filter(is_active=True)
        else:
            # GERENTE vê apenas usuários das suas unidades
            unidades_ids = user.get_unidades_ids()
            queryset = Usuario.objects.filter(
                is_active=True,
                unidades__id__in=unidades_ids
            ).distinct()
        
        # Filtro por unidade específica (query param)
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
        """
        POST /api/usuarios/{id}/vincular_unidade/
        Body: { "unidade_id": int, "papel": str }
        
        Vincula usuário a uma unidade com papel específico.
        """
        usuario = self.get_object()
        unidade_id = request.data.get('unidade_id')
        papel = request.data.get('papel', 'VENDEDOR')
        
        if not unidade_id:
            return Response(
                {'error': 'unidade_id é obrigatório'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        if papel not in ['VENDEDOR', 'GERENTE', 'DIRETORIA', 'CONTROLE']:
            return Response(
                {'error': 'Papel inválido. Use: VENDEDOR, GERENTE, DIRETORIA ou CONTROLE'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        # Verifica permissão: só DIRETORIA pode criar outros DIRETORIA
        if papel == 'DIRETORIA' and not request.user.is_diretoria():
            return Response(
                {'error': 'Apenas diretoria pode criar usuários DIRETORIA'},
                status=status.HTTP_403_FORBIDDEN
            )
        
        try:
            unidade = UnidadeNegocio.objects.get(id=unidade_id, ativo=True)
            
            # Verifica se GERENTE tem acesso a essa unidade
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
            return Response(
                {'error': 'Unidade não encontrada'},
                status=status.HTTP_404_NOT_FOUND
            )
    
    @action(detail=True, methods=['post'])
    def desvincular_unidade(self, request, pk=None):
        """
        POST /api/usuarios/{id}/desvincular_unidade/
        Body: { "unidade_id": int }
        
        Remove vínculo do usuário com uma unidade.
        """
        usuario = self.get_object()
        unidade_id = request.data.get('unidade_id')
        
        if not unidade_id:
            return Response(
                {'error': 'unidade_id é obrigatório'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            vinculo = UsuarioUnidade.objects.get(
                usuario=usuario,
                unidade_id=unidade_id
            )
            
            # Verifica se GERENTE tem acesso a essa unidade
            if not request.user.is_superuser and not request.user.is_diretoria():
                if not request.user.tem_acesso_unidade(int(unidade_id)):
                    return Response(
                        {'error': 'Você não tem acesso a esta unidade'},
                        status=status.HTTP_403_FORBIDDEN
                    )
            
            vinculo.delete()
            return Response({
                'success': True,
                'message': 'Vínculo removido com sucesso'
            })
            
        except UsuarioUnidade.DoesNotExist:
            return Response(
                {'error': 'Vínculo não encontrado'},
                status=status.HTTP_404_NOT_FOUND
            )


# =============================================================================
# LOG DE CONSULTAS (somente leitura)
# =============================================================================
class LogConsultaViewSet(viewsets.ReadOnlyModelViewSet):
    """
    ViewSet para LogConsulta (somente leitura).
    Apenas superusuários podem ver todos os logs.
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
    """
    Valida a extensão de um arquivo enviado via multipart/form-data.

    Retorna uma mensagem de erro (str) se inválida, ou None se válida.
    Não lança exceção para permitir coleta de todos os erros antes de responder.
    """
    ext = '.' + file.name.rsplit('.', 1)[-1].lower() if '.' in file.name else ''
    if ext not in ALLOWED_UPLOAD_EXTENSIONS:
        allowed = ', '.join(sorted(ALLOWED_UPLOAD_EXTENSIONS))
        return f'"{field_name}": formato "{ext or "sem extensão"}" não permitido. Use: {allowed}.'
    return None


class UploadEstoqueView(APIView):
    """
    POST /api/upload/grade-020502/

    Recebe 3 planilhas simultâneas via multipart/form-data e executa o
    cálculo de estoque gerencial FEFO Reverso via UploadFefoService.

    Form data obrigatório:
    - file_020502      : Grade 020502 (.xlsx, .xls ou .csv)
    - file_020304      : Grade 020304 (.xlsx, .xls ou .csv)
    - file_nri         : Planilha NRI  (.xlsx, .xls ou .csv)
    - unidade_negocio_id : ID da unidade de negócio (int)

    Permissões RBAC:
    - Apenas GERENTE pode fazer upload na sua unidade.

    Registra histórico de upload em HistoricoUpload com os nomes dos 3
    arquivos concatenados e o número de SKUs atualizados.
    """
    permission_classes = [IsAuthenticated, CanManageUpload]

    def post(self, request):
        from .upload_service import UploadFefoService

        # ------------------------------------------------------------------
        # 1. Coleta de parâmetros
        # ------------------------------------------------------------------
        file_020502 = request.FILES.get('file_020502')
        file_020304 = request.FILES.get('file_020304')
        file_nri    = request.FILES.get('file_nri')
        unidade_negocio_id = request.data.get('unidade_negocio_id')

        # ------------------------------------------------------------------
        # 2. Validação de presença (falha rápida, lista todos os ausentes)
        # ------------------------------------------------------------------
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
            return Response(
                {'errors': erros_presenca},
                status=status.HTTP_400_BAD_REQUEST
            )

        # ------------------------------------------------------------------
        # 3. Validação de extensões (coleta todos os erros antes de retornar)
        # ------------------------------------------------------------------
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
            return Response(
                {'errors': erros_extensao},
                status=status.HTTP_400_BAD_REQUEST
            )

        # ------------------------------------------------------------------
        # 4. Validação de permissão de acesso à unidade
        # ------------------------------------------------------------------
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
                return Response(
                    {'error': 'Sem permissão para esta unidade.'},
                    status=status.HTTP_403_FORBIDDEN
                )

        # ------------------------------------------------------------------
        # 5. Nome consolidado dos 3 arquivos (para HistoricoUpload)
        # ------------------------------------------------------------------
        nome_arquivos = ' | '.join([
            file_020502.name,
            file_020304.name,
            file_nri.name,
        ])

        # ------------------------------------------------------------------
        # 6. Processamento principal
        # ------------------------------------------------------------------
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
            return Response(
                {'error': 'Unidade de negócio não encontrada.'},
                status=status.HTTP_404_NOT_FOUND
            )
        except Exception as e:
            # Tenta persistir o erro no histórico antes de propagar a resposta.
            # O bloco interno tem try/except próprio para não mascarar o erro
            # original caso o próprio save do histórico falhe.
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

            return Response(
                {'error': f'Erro ao processar arquivos: {str(e)}'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )


# =============================================================================
# HISTÓRICO DE UPLOAD
# =============================================================================
class HistoricoUploadViewSet(UnidadeAccessMixin, viewsets.ReadOnlyModelViewSet):
    """
    ViewSet somente leitura para HistoricoUpload.
    
    GET /api/historico-upload/
    GET /api/historico-upload/{id}/
    GET /api/historico-upload/ultimo/?unidade_id=X
    
    Retorna histórico de uploads ordenado do mais recente para o mais antigo.
    """
    serializer_class = HistoricoUploadSerializer
    permission_classes = [IsAuthenticated]
    pagination_class = HistoricoUploadPagination
    filter_backends = [DjangoFilterBackend, filters.OrderingFilter]
    filterset_fields = ['tipo_arquivo', 'status', 'unidade_negocio']
    ordering_fields = ['created_at']
    ordering = ['-created_at']
    
    def get_queryset(self):
        queryset = HistoricoUpload.objects.filter(
            ativo=True
        ).select_related(
            'usuario',
            'unidade_negocio'
        )
        
        unidade_id = self.get_unidade_ativa()
        if unidade_id:
            queryset = queryset.filter(unidade_negocio_id=unidade_id)
        else:
            unidades_ids = self.get_user_unidades()
            queryset = queryset.filter(unidade_negocio_id__in=unidades_ids)
        
        return queryset
    
    @action(detail=False, methods=['get'])
    def ultimo(self, request):
        """
        GET /api/historico-upload/ultimo/?unidade_id=X
        
        Retorna apenas a data_upload mais recente da unidade.
        """
        unidade_id = self.get_unidade_ativa()
        if unidade_id is None:
            return Response(
                {'error': 'Parâmetro unidade_id é obrigatório'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
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
    
    Retorna lista de SKUs em estado de alerta (Pré-Bloqueio, Bloqueado, Extremamente Crítico).
    
    Query Params:
    - unidade_id: ID da unidade de negócio (obrigatório)
    
    Retorna dados estruturados para exibição no sininho de notificações.
    """
    permission_classes = [IsAuthenticated]
    
    def get(self, request):
        unidade_id = self.get_unidade_ativa()
        if unidade_id is None:
            return Response(
                {'error': 'Parâmetro unidade_id é obrigatório e deve ser uma unidade válida'},
                status=status.HTTP_400_BAD_REQUEST
            )
        
        try:
            unidade = UnidadeNegocio.objects.get(id=unidade_id, ativo=True)
        except UnidadeNegocio.DoesNotExist:
            return Response(
                {'error': 'Unidade não encontrada'},
                status=status.HTTP_404_NOT_FOUND
            )
        
        config = getattr(unidade, 'configuracao_alerta', None)
        if config is None:
            config = ConfiguracaoAlerta.objects.filter(
                unidade__isnull=True,
                ativo=True
            ).first()
        
        dias_pre_bloqueio = config.dias_pre_bloqueio if config else 60
        dias_bloqueado = config.dias_bloqueado if config else 30
        dias_extremamente_critico = config.dias_extremamente_critico if config else 7
        
        hoje = date.today()
        
        from datetime import timedelta
        data_limite_pre_bloqueio = hoje + timedelta(days=dias_pre_bloqueio)
        
        # Busca SKUs com estoque e validade_inicio_range dentro da janela de alerta.
        # Exclui vencidos (data < hoje) — notificações são apenas para itens ainda válidos
        # mas dentro de alguma faixa crítica.
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
    
    Retorna os módulos de menu que o usuário atual tem permissão de acessar
    na unidade informada. Superusuários recebem todos os módulos ativos globalmente.
    """
    permission_classes = [IsAuthenticated]

    def get(self, request, *args, **kwargs):
        unidade_id = request.query_params.get('unidade_id')
        if not unidade_id:
            return Response(
                {'error': 'Parâmetro unidade_id é obrigatório.'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
            
        try:
            unidade_id = int(unidade_id)
        except ValueError:
            return Response(
                {'error': 'unidade_id inválido.'}, 
                status=status.HTTP_400_BAD_REQUEST
            )
            
        usuario = request.user
        
        # Recupera o papel que o usuário desempenha especificamente nesta filial
        papel = usuario.get_papel_unidade(unidade_id)
        
        # Se for superuser, ignora restrições e traz tudo o que estiver ativo globalmente
        if usuario.is_superuser:
            modulos = ModuloMenu.objects.filter(globalmente_ativo=True)
        else:
            if not papel:
                return Response([]) # Sem vínculo com a unidade = nenhum menu
                
            # Busca os IDs dos módulos que estão explicitamente visíveis para o papel dele
            modulos_permitidos_ids = PermissaoMenu.objects.filter(
                papel=papel,
                visivel=True,
                modulo__globalmente_ativo=True
            ).values_list('modulo_id', flat=True)
            
            # Filtra os módulos que estão permitidos e ativos globalmente
            modulos = ModuloMenu.objects.filter(id__in=modulos_permitidos_ids)
            
        serializer = MenuDinamicoSerializer(modulos, many=True)
        return Response(serializer.data)