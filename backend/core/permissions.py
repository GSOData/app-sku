"""
Permissões customizadas baseadas em papéis (RBAC).

Papéis:
- VENDEDOR: Somente leitura (SKUs, Lotes)
- GERENTE: CRUD completo na sua unidade
- DIRETORIA: Dashboards e relatórios consolidados (todas unidades)
"""
from rest_framework.permissions import BasePermission, SAFE_METHODS


def get_unidade_from_request(request) -> int | None:
    """
    Extrai o ID da unidade do request.
    Verifica query params, corpo e headers.
    """
    # Query params (GET, DELETE)
    unidade_id = request.query_params.get('unidade_id')
    if unidade_id:
        return int(unidade_id)
    
    # Body (POST, PUT, PATCH)
    if hasattr(request, 'data') and request.data:
        unidade_id = request.data.get('unidade_id') or request.data.get('unidade')
        if unidade_id:
            return int(unidade_id)
    
    # Header customizado
    unidade_id = request.headers.get('X-Unidade-ID')
    if unidade_id:
        return int(unidade_id)
    
    return None


class IsVendedor(BasePermission):
    """
    Permissão para VENDEDOR: somente leitura.
    Permite acesso de leitura a usuários com papel VENDEDOR ou superior.
    """
    message = "Você não tem permissão para acessar este recurso."

    def has_permission(self, request, view):
        if not request.user.is_authenticated:
            return False
        
        # Superusuários sempre têm acesso
        if request.user.is_superuser:
            return True
        
        # Qualquer papel autenticado pode ler
        # VENDEDOR = somente SAFE_METHODS
        # GERENTE e DIRETORIA podem tudo
        unidade_id = get_unidade_from_request(request)
        if not unidade_id:
            # Sem unidade, permite apenas leitura básica
            return request.method in SAFE_METHODS
        
        papel = request.user.get_papel_unidade(unidade_id)
        if not papel:
            return False
        
        # VENDEDOR só pode ler
        if papel == 'VENDEDOR':
            return request.method in SAFE_METHODS
        
        # GERENTE e DIRETORIA podem tudo
        return papel in ['GERENTE', 'DIRETORIA']


class IsGerente(BasePermission):
    """
    Permissão para GERENTE: CRUD completo na unidade.
    Permite todas operações para GERENTE e DIRETORIA.
    """
    message = "Apenas gerentes podem realizar esta operação."

    def has_permission(self, request, view):
        if not request.user.is_authenticated:
            return False
        
        if request.user.is_superuser:
            return True
        
        unidade_id = get_unidade_from_request(request)
        if not unidade_id:
            # Sem unidade, verifica papel máximo
            max_papel = request.user.get_max_papel()
            return max_papel in ['GERENTE', 'DIRETORIA']
        
        papel = request.user.get_papel_unidade(unidade_id)
        return papel in ['GERENTE', 'DIRETORIA']


class IsDiretoria(BasePermission):
    """
    Permissão para DIRETORIA: acesso consolidado a todas unidades.
    Usado para relatórios gerenciais e dashboards consolidados.
    """
    message = "Apenas diretoria pode acessar dados consolidados."

    def has_permission(self, request, view):
        if not request.user.is_authenticated:
            return False
        
        if request.user.is_superuser:
            return True
        
        return request.user.is_diretoria()


class IsGerenteOuDiretoria(BasePermission):
    """
    Permissão combinada para GERENTE ou DIRETORIA.
    Útil para gestão de usuários e configurações.
    """
    message = "Apenas gerentes ou diretoria podem acessar este recurso."

    def has_permission(self, request, view):
        if not request.user.is_authenticated:
            return False
        
        if request.user.is_superuser:
            return True
        
        max_papel = request.user.get_max_papel()
        return max_papel in ['GERENTE', 'DIRETORIA']


class CanReadSKU(BasePermission):
    """
    Permissão para leitura de SKUs.
    Todos os papéis autenticados podem ler.
    """
    message = "Você não tem permissão para visualizar SKUs."

    def has_permission(self, request, view):
        if not request.user.is_authenticated:
            return False
        
        if request.method in SAFE_METHODS:
            return True
        
        # Escrita requer GERENTE ou superior
        if request.user.is_superuser:
            return True
        
        unidade_id = get_unidade_from_request(request)
        if unidade_id:
            papel = request.user.get_papel_unidade(unidade_id)
            return papel in ['GERENTE', 'DIRETORIA']
        
        return request.user.get_max_papel() in ['GERENTE', 'DIRETORIA']


class CanManageUpload(BasePermission):
    """
    Permissão para uploads (estoque, contagens).
    Apenas GERENTE pode fazer upload na sua unidade.
    """
    message = "Apenas gerentes podem realizar uploads de dados."

    def has_permission(self, request, view):
        if not request.user.is_authenticated:
            return False
        
        if request.user.is_superuser:
            return True
        
        unidade_id = get_unidade_from_request(request)
        if not unidade_id:
            return False
        
        papel = request.user.get_papel_unidade(unidade_id)
        return papel == 'GERENTE'


class ObjectBelongsToUserUnit(BasePermission):
    """
    Verifica se o objeto pertence a uma unidade que o usuário tem acesso.
    Usado em conjunto com outras permissões em has_object_permission.
    """
    message = "Você não tem acesso a este objeto."

    def has_object_permission(self, request, view, obj):
        if request.user.is_superuser or request.user.is_diretoria():
            return True
        
        # Tenta obter unidade do objeto
        unidade_id = None
        if hasattr(obj, 'unidade_id'):
            unidade_id = obj.unidade_id
        elif hasattr(obj, 'unidade'):
            unidade_id = obj.unidade.id if obj.unidade else None
        
        if not unidade_id:
            return False
        
        return request.user.tem_acesso_unidade(unidade_id)
